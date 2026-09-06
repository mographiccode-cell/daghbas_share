package com.mographiccode.local_share

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "local_share/native"
    private val maxShareItems = 20
    private val maxSharedFileBytes = 50L * 1024L * 1024L * 1024L
    private val maxSharedTextChars = 65536
    private var nativeChannel: MethodChannel? = null
    private val pendingSharedItems = mutableListOf<Map<String, Any?>>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nativeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).also { channel ->
            channel.setMethodCallHandler { call, result ->
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
                            result.success(saveToDownloads(source, safeName))
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

                    "moveToBackground" -> {
                        moveTaskToBack(true)
                        result.success(null)
                    }

                    "consumeSharedItems" -> {
                        val copy = synchronized(pendingSharedItems) {
                            val value = pendingSharedItems.toList()
                            pendingSharedItems.clear()
                            value
                        }
                        result.success(copy)
                    }

                    "materializeSharedUri" -> {
                        val raw = call.argument<String>("uri")
                        val requestedName = call.argument<String>("name")
                        if (raw.isNullOrBlank()) {
                            result.error("INVALID_URI", "Missing shared URI", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val uri = Uri.parse(raw)
                            if (uri.scheme?.lowercase() != "content") {
                                result.error("INVALID_URI", "Only content URIs are accepted", null)
                                return@setMethodCallHandler
                            }
                            val safeName = sanitizeFileName(
                                requestedName?.takeIf { it.isNotBlank() } ?: queryDisplayName(uri)
                            )
                            result.success(materializeSharedUri(uri, safeName).absolutePath)
                        } catch (e: Exception) {
                            result.error("SHARE_COPY_FAILED", e.message ?: "Unable to prepare shared file", null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
        }
        handleShareIntent(intent, notifyDart = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (handleShareIntent(intent, notifyDart = false)) {
            nativeChannel?.invokeMethod("sharedItemsAvailable", null)
        }
    }

    private fun handleShareIntent(intent: Intent?, notifyDart: Boolean): Boolean {
        if (intent == null || (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE)) {
            return false
        }

        val items = mutableListOf<Map<String, Any?>>()
        val sharedText = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.trim()
        if (!sharedText.isNullOrEmpty()) {
            items += mapOf(
                "kind" to "text",
                "text" to sharedText.take(maxSharedTextChars),
            )
        }

        val seen = linkedSetOf<String>()
        for (uri in extractStreamUris(intent)) {
            if (items.size >= maxShareItems) break
            if (uri.scheme?.lowercase() != "content") continue
            val raw = uri.toString()
            if (!seen.add(raw)) continue
            items += mapOf(
                "kind" to "uri",
                "uri" to raw,
                "name" to sanitizeFileName(queryDisplayName(uri)),
            )
        }

        if (items.isEmpty()) return false
        synchronized(pendingSharedItems) {
            val room = (maxShareItems - pendingSharedItems.size).coerceAtLeast(0)
            if (room > 0) pendingSharedItems.addAll(items.take(room))
        }
        if (notifyDart) nativeChannel?.invokeMethod("sharedItemsAvailable", null)
        return true
    }

    @Suppress("DEPRECATION")
    private fun extractStreamUris(intent: Intent): List<Uri> {
        val result = mutableListOf<Uri>()
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            val values = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            if (values != null) result.addAll(values)
        } else {
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(result::add)
        }
        val clip = intent.clipData
        if (clip != null) {
            for (index in 0 until clip.itemCount.coerceAtMost(maxShareItems)) {
                clip.getItemAt(index).uri?.let(result::add)
            }
        }
        return result
    }

    private fun queryDisplayName(uri: Uri): String {
        return try {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            } ?: "shared_file"
        } catch (_: Exception) {
            "shared_file"
        }
    }

    private fun materializeSharedUri(uri: Uri, fileName: String): File {
        val folder = File(cacheDir, "localshare-share-inbox")
        if (!folder.exists() && !folder.mkdirs()) {
            throw IllegalStateException("Unable to create share inbox")
        }
        val destination = uniqueFile(folder, fileName)
        var total = 0L
        try {
            val input = contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("Unable to open shared content")
            input.use { source ->
                FileOutputStream(destination).use { output ->
                    val buffer = ByteArray(1024 * 1024)
                    while (true) {
                        val count = source.read(buffer)
                        if (count < 0) break
                        total += count
                        if (total > maxSharedFileBytes) {
                            throw IllegalStateException("Shared file exceeds the 50 GB safety limit")
                        }
                        output.write(buffer, 0, count)
                    }
                    output.fd.sync()
                }
            }
            return destination
        } catch (e: Exception) {
            destination.delete()
            throw e
        }
    }

    private fun uniqueFile(folder: File, requestedName: String): File {
        val safeName = sanitizeFileName(requestedName)
        var candidate = File(folder, safeName)
        if (!candidate.exists()) return candidate
        val dot = safeName.lastIndexOf('.')
        val stem = if (dot > 0) safeName.substring(0, dot) else safeName
        val ext = if (dot > 0) safeName.substring(dot) else ""
        var index = 2
        while (candidate.exists() && index < 10000) {
            candidate = File(folder, "$stem ($index)$ext")
            index++
        }
        if (candidate.exists()) {
            candidate = File(folder, "${System.currentTimeMillis()}-$safeName")
        }
        return candidate
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
}
