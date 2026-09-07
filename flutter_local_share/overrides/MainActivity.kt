package com.mographiccode.local_share

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "local_share/native"
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingShares = mutableListOf<Map<String, Any>>()
    private var nativeChannel: MethodChannel? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nativeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        nativeChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "exportToDownloads" -> {
                    val path = call.argument<String>("path")
                    val requestedName = call.argument<String>("name")
                    if (path.isNullOrBlank()) {
                        result.error("INVALID_PATH", "Missing source path", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val source = File(path).canonicalFile
                        val appRoot = getExternalFilesDir(null)?.canonicalFile
                        if (!source.exists() || !source.isFile) {
                            result.error("NOT_FOUND", "Source file does not exist", null)
                            return@setMethodCallHandler
                        }
                        if (appRoot != null && !source.path.startsWith(appRoot.path + File.separator)) {
                            result.error("OUTSIDE_APP_STORAGE", "Source must be inside LocalShare storage", null)
                            return@setMethodCallHandler
                        }
                        val safeName = sanitizeFileName(requestedName ?: source.name)
                        val saved = saveToDownloads(source, safeName)
                        result.success(saved)
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.message ?: "Unable to save file", null)
                    }
                }

                "openUri" -> {
                    val raw = call.argument<String>("uri")
                    if (raw.isNullOrBlank()) {
                        result.error("INVALID_URI", "Missing URI", null)
                        return@setMethodCallHandler
                    }
                    try {
                        openUri(raw)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("OPEN_FAILED", e.message ?: "Unable to open URI", null)
                    }
                }

                "shareUri" -> {
                    val raw = call.argument<String>("uri")
                    val name = call.argument<String>("name")
                    if (raw.isNullOrBlank()) {
                        result.error("INVALID_URI", "Missing URI", null)
                        return@setMethodCallHandler
                    }
                    try {
                        shareUri(raw, name)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("SHARE_FAILED", e.message ?: "Unable to share URI", null)
                    }
                }

                "acquireMulticastLock" -> {
                    try {
                        acquireMulticastLock()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("MULTICAST_LOCK_FAILED", e.message ?: "Unable to enable LAN discovery", null)
                    }
                }

                "consumeSharedItems" -> {
                    val items = synchronized(pendingShares) {
                        val copy = pendingShares.toList()
                        pendingShares.clear()
                        copy
                    }
                    result.success(items)
                }

                else -> result.notImplemented()
            }
        }

        captureShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureShareIntent(intent)
    }

    override fun onDestroy() {
        try {
            multicastLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {}
        multicastLock = null
        nativeChannel = null
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun acquireMulticastLock() {
        if (multicastLock?.isHeld == true) return
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifiManager.createMulticastLock("LocalShareDiscovery").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun captureShareIntent(sourceIntent: Intent?) {
        val action = sourceIntent?.action ?: return
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return
        if (sourceIntent.getBooleanExtra("localshare_consumed", false)) return
        sourceIntent.putExtra("localshare_consumed", true)

        val text = sourceIntent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        val uris = mutableListOf<Uri>()

        @Suppress("DEPRECATION")
        if (action == Intent.ACTION_SEND) {
            sourceIntent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.add(it) }
        } else {
            @Suppress("DEPRECATION")
            sourceIntent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.addAll(it) }
        }

        if (text.isBlank() && uris.isEmpty()) return

        executor.execute {
            val paths = mutableListOf<String>()
            for (uri in uris.take(100)) {
                try {
                    paths.add(copySharedUriToCache(uri))
                } catch (_: Exception) {
                    // Skip only the unreadable item; other shared items can still be sent.
                }
            }

            if (text.isNotBlank() || paths.isNotEmpty()) {
                val payload: Map<String, Any> = mapOf(
                    "id" to UUID.randomUUID().toString(),
                    "text" to text.take(4096),
                    "paths" to paths,
                )
                synchronized(pendingShares) {
                    pendingShares.add(payload)
                    while (pendingShares.size > 20) pendingShares.removeAt(0)
                }
                mainHandler.post {
                    nativeChannel?.invokeMethod("sharedItems", payload)
                }
            }
        }
    }

    private fun copySharedUriToCache(uri: Uri): String {
        if (uri.scheme?.lowercase() != "content" && uri.scheme?.lowercase() != "file") {
            throw IllegalArgumentException("Unsupported shared URI")
        }

        val root = File(externalCacheDir ?: cacheDir, "LocalShare/shared_inbox")
        if (!root.exists() && !root.mkdirs()) {
            throw IllegalStateException("Unable to create LocalShare share cache")
        }

        val originalName = queryDisplayName(uri) ?: uri.lastPathSegment ?: "shared_file"
        val safeName = sanitizeFileName(originalName)
        val destination = File(root, "${System.currentTimeMillis()}_${UUID.randomUUID()}_$safeName").canonicalFile
        if (!destination.path.startsWith(root.canonicalPath + File.separator)) {
            throw SecurityException("Invalid shared file destination")
        }

        val input = if (uri.scheme?.lowercase() == "file") {
            FileInputStream(File(requireNotNull(uri.path)).canonicalFile)
        } else {
            contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("Unable to open shared item")
        }

        val maxBytes = 50L * 1024L * 1024L * 1024L
        input.use { source ->
            FileOutputStream(destination).use { output ->
                val buffer = ByteArray(1024 * 1024)
                var total = 0L
                while (true) {
                    val read = source.read(buffer)
                    if (read <= 0) break
                    total += read
                    if (total > maxBytes) {
                        destination.delete()
                        throw IllegalArgumentException("Shared file exceeds LocalShare limit")
                    }
                    output.write(buffer, 0, read)
                }
                output.fd.sync()
            }
        }
        return destination.path
    }

    private fun queryDisplayName(uri: Uri): String? {
        if (uri.scheme?.lowercase() != "content") return null
        return try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (!cursor.moveToFirst()) return@use null
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index < 0) null else cursor.getString(index)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun sanitizeFileName(value: String): String {
        var name = File(value).name
            .replace(Regex("[\\u0000-\\u001F\\u007F<>:\"|?*]"), "_")
            .replace(Regex("[. ]+$"), "")
            .take(180)
        if (name.isBlank() || name == "." || name == "..") name = "received_file"
        val stem = name.substringBeforeLast('.', name)
        if (Regex("^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$", RegexOption.IGNORE_CASE).matches(stem)) {
            name = "_$name"
        }
        return name
    }

    private fun saveToDownloads(source: File, fileName: String): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            throw IllegalStateException("Android 10 or newer is required for public Downloads saving")
        }

        val resolver = contentResolver
        val extension = fileName.substringAfterLast('.', "").lowercase()
        val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "application/octet-stream"
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, mime)
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/LocalShare")
            put(MediaStore.Downloads.IS_PENDING, 1)
        }

        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Unable to create Downloads entry")

        try {
            resolver.openOutputStream(uri, "w").use { output ->
                if (output == null) throw IllegalStateException("Unable to open destination")
                FileInputStream(source).use { input -> input.copyTo(output, 1024 * 1024) }
            }
            val finished = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
            resolver.update(uri, finished, null, null)
            return uri.toString()
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }

    private fun openUri(raw: String) {
        val uri = Uri.parse(raw)
        val scheme = uri.scheme?.lowercase()
        val intent = Intent(Intent.ACTION_VIEW).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (scheme == "content") {
                val mime = contentResolver.getType(uri) ?: "application/octet-stream"
                setDataAndType(uri, mime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } else {
                data = uri
            }
        }
        startActivity(intent)
    }

    private fun shareUri(raw: String, name: String?) {
        val uri = Uri.parse(raw)
        if (uri.scheme?.lowercase() != "content") {
            throw IllegalArgumentException("Only LocalShare content URIs can be shared")
        }
        val mime = contentResolver.getType(uri) ?: "application/octet-stream"
        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_STREAM, uri)
            if (!name.isNullOrBlank()) putExtra(Intent.EXTRA_TITLE, sanitizeFileName(name))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            clipData = android.content.ClipData.newRawUri("LocalShare", uri)
        }
        startActivity(Intent.createChooser(sendIntent, "مشاركة عبر").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
