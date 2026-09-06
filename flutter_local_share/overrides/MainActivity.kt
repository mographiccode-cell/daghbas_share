package com.mographiccode.local_share

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    private val channelName = "local_share/native"

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

                "shareFile" -> {
                    val path = call.argument<String>("path")
                    val requestedName = call.argument<String>("name")
                    if (path.isNullOrBlank()) {
                        result.error("INVALID_PATH", "Missing file path", null)
                        return@setMethodCallHandler
                    }
                    try {
                        shareFile(path, requestedName)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("SHARE_FAILED", e.message ?: "Unable to share file", null)
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

                else -> result.notImplemented()
            }
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

    private fun shareFile(raw: String, requestedName: String?) {
        val shareUri: Uri
        val mime: String
        if (raw.startsWith("content://", ignoreCase = true)) {
            shareUri = Uri.parse(raw)
            mime = contentResolver.getType(shareUri) ?: "application/octet-stream"
        } else {
            val source = File(raw).canonicalFile
            if (!source.exists() || !source.isFile) {
                throw IllegalStateException("File does not exist")
            }
            val allowedRoots = listOfNotNull(
                cacheDir,
                externalCacheDir,
                filesDir,
                getExternalFilesDir(null),
            ).map { it.canonicalFile }
            var shareSource = source
            val insideOwnedStorage = allowedRoots.any { root ->
                source.path == root.path || source.path.startsWith(root.path + File.separator)
            }
            if (!insideOwnedStorage) {
                val shareDir = File(cacheDir, "share-out").apply { mkdirs() }
                shareDir.listFiles()?.filter { it.isFile && System.currentTimeMillis() - it.lastModified() > 86_400_000L }
                    ?.forEach { it.delete() }
                val target = File(
                    shareDir,
                    "${System.currentTimeMillis()}-${sanitizeFileName(requestedName ?: source.name)}",
                )
                source.inputStream().use { input ->
                    target.outputStream().use { output -> input.copyTo(output, 1024 * 1024) }
                }
                shareSource = target
            }
            shareUri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                shareSource,
            )
            val extension = shareSource.name.substringAfterLast('.', "").lowercase()
            mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
                ?: "application/octet-stream"
        }

        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_STREAM, shareUri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, "مشاركة الملف"))
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
