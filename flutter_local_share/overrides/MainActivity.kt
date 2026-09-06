package com.mographiccode.local_share

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    private val channelName = "local_share/native"
    private val pendingSharedFiles = mutableListOf<String>()
    private var pendingSharedText: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureShareIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
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

                "consumeSharedContent" -> {
                    synchronized(pendingSharedFiles) {
                        val payload = hashMapOf<String, Any?>(
                            "files" to pendingSharedFiles.toList(),
                            "text" to pendingSharedText,
                        )
                        pendingSharedFiles.clear()
                        pendingSharedText = null
                        result.success(payload)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun captureShareIntent(sourceIntent: Intent?) {
        if (sourceIntent == null) return
        val action = sourceIntent.action ?: return
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return

        val sharedText = sourceIntent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
        if (!sharedText.isNullOrEmpty()) pendingSharedText = sharedText.take(4096)

        val uris = mutableListOf<Uri>()
        if (action == Intent.ACTION_SEND) {
            @Suppress("DEPRECATION")
            sourceIntent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.add(it) }
        } else {
            @Suppress("DEPRECATION")
            sourceIntent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.addAll(it) }
        }

        if (uris.isEmpty()) return
        val inbox = File(cacheDir, "localshare_share_inbox").apply { mkdirs() }
        uris.take(50).forEachIndexed { index, uri ->
            try {
                val displayName = queryDisplayName(uri) ?: "shared_${System.currentTimeMillis()}_$index"
                val safeName = sanitizeFileName(displayName)
                var target = File(inbox, safeName)
                var suffix = 1
                while (target.exists() && suffix < 10000) {
                    val dot = safeName.lastIndexOf('.')
                    val stem = if (dot > 0) safeName.substring(0, dot) else safeName
                    val ext = if (dot > 0) safeName.substring(dot) else ""
                    target = File(inbox, "$stem ($suffix)$ext")
                    suffix++
                }
                contentResolver.openInputStream(uri).use { input ->
                    if (input == null) return@forEachIndexed
                    target.outputStream().use { output -> input.copyTo(output, 1024 * 1024) }
                }
                synchronized(pendingSharedFiles) {
                    pendingSharedFiles.add(target.absolutePath)
                }
            } catch (_: Exception) {
                // Skip unreadable shared items without crashing LocalShare.
            }
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
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
}
