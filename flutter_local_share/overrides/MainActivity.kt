package com.mographiccode.local_share

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
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
            if (call.method != "exportToDownloads") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val path = call.argument<String>("path")
            val requestedName = call.argument<String>("name")
            if (path.isNullOrBlank()) {
                result.error("INVALID_PATH", "Missing source path", null)
                return@setMethodCallHandler
            }

            try {
                val source = File(path)
                if (!source.exists() || !source.isFile) {
                    result.error("NOT_FOUND", "Source file does not exist", null)
                    return@setMethodCallHandler
                }
                val safeName = File(requestedName ?: source.name).name
                val saved = saveToDownloads(source, safeName)
                result.success(saved)
            } catch (e: Exception) {
                result.error("SAVE_FAILED", e.message ?: "Unable to save file", null)
            }
        }
    }

    private fun saveToDownloads(source: File, fileName: String): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            throw IllegalStateException("Saving to public Downloads requires Android 10 or newer in this build")
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
}
