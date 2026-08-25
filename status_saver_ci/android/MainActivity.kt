package com.mographiccode.status_saver

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.util.Size
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.ArrayDeque

class MainActivity : FlutterActivity() {
    private val channelName = "status_saver/native"
    private val requestTree = 5107
    private val prefsName = "status_saver_prefs"
    private val prefTreeUri = "tree_uri"
    private var pendingFolderResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result -> handleCall(call, result) }
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "hasFolder" -> result.success(getTreeUri() != null)
                "getFolderLabel" -> result.success(getFolderLabel())
                "selectFolder" -> {
                    val kind = call.argument<String>("kind") ?: "whatsapp"
                    selectFolder(kind, result)
                }
                "listStatuses" -> result.success(listStatuses())
                "readBytes" -> {
                    val uri = requireUri(call)
                    result.success(contentResolver.openInputStream(uri)?.use { it.readBytes() })
                }
                "getThumbnail" -> {
                    val uri = requireUri(call)
                    val mime = call.argument<String>("mimeType") ?: ""
                    result.success(makeThumbnail(uri, mime))
                }
                "saveStatus" -> {
                    val uri = requireUri(call)
                    val name = call.argument<String>("name") ?: "status_${System.currentTimeMillis()}"
                    val mime = call.argument<String>("mimeType") ?: contentResolver.getType(uri) ?: "application/octet-stream"
                    val isVideo = call.argument<Boolean>("isVideo") ?: mime.startsWith("video/")
                    result.success(saveStatus(uri, sanitizeName(name), mime, isVideo))
                }
                "shareStatus" -> {
                    val uri = requireUri(call)
                    val mime = call.argument<String>("mimeType") ?: contentResolver.getType(uri) ?: "*/*"
                    shareStatus(uri, mime)
                    result.success(null)
                }
                "openStatus" -> {
                    val uri = requireUri(call)
                    val mime = call.argument<String>("mimeType") ?: contentResolver.getType(uri) ?: "*/*"
                    openStatus(uri, mime)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("STATUS_SAVER_ERROR", e.message ?: "Unexpected error", null)
        }
    }

    private fun requireUri(call: MethodCall): Uri {
        val raw = call.argument<String>("uri") ?: throw IllegalArgumentException("Missing uri")
        return Uri.parse(raw)
    }

    private fun getTreeUri(): Uri? {
        val value = getSharedPreferences(prefsName, MODE_PRIVATE).getString(prefTreeUri, null)
        return value?.let(Uri::parse)
    }

    private fun selectFolder(kind: String, result: MethodChannel.Result) {
        if (pendingFolderResult != null) {
            result.error("BUSY", "هناك نافذة اختيار مجلد مفتوحة بالفعل", null)
            return
        }
        pendingFolderResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                putExtra(DocumentsContract.EXTRA_INITIAL_URI, initialUri(kind))
            }
        }
        startActivityForResult(intent, requestTree)
    }

    private fun initialUri(kind: String): Uri {
        val docId = if (kind == "business") {
            "primary:Android/media/com.whatsapp.w4b/WhatsApp Business/Media"
        } else {
            "primary:Android/media/com.whatsapp/WhatsApp/Media"
        }
        return DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", docId)
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != requestTree) return
        val callback = pendingFolderResult
        pendingFolderResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            callback?.success(false)
            return
        }

        val uri = data.data!!
        try {
            val flags = data.flags and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            contentResolver.takePersistableUriPermission(uri, flags)
            findStatusesDirectory(uri)
                ?: throw IllegalArgumentException("لم أجد مجلد .Statuses. اختر مجلد Media الخاص بواتساب أو مجلد .Statuses مباشرة.")
            getSharedPreferences(prefsName, MODE_PRIVATE)
                .edit()
                .putString(prefTreeUri, uri.toString())
                .apply()
            callback?.success(true)
        } catch (e: Exception) {
            callback?.error("INVALID_FOLDER", e.message ?: "تعذر استخدام المجلد المحدد", null)
        }
    }

    private fun getFolderLabel(): String? {
        val tree = getTreeUri() ?: return null
        return try {
            val rootId = DocumentsContract.getTreeDocumentId(tree)
            val root = DocumentsContract.buildDocumentUriUsingTree(tree, rootId)
            queryName(root) ?: tree.lastPathSegment
        } catch (_: Exception) {
            tree.lastPathSegment
        }
    }

    private data class DirNode(val documentId: String, val depth: Int)

    private fun findStatusesDirectory(treeUri: Uri): Uri? {
        val rootId = DocumentsContract.getTreeDocumentId(treeUri)
        val rootUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, rootId)
        if (queryName(rootUri) == ".Statuses") return rootUri

        val queue = ArrayDeque<DirNode>()
        queue.add(DirNode(rootId, 0))
        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()
            if (node.depth > 5) continue
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, node.documentId)
            contentResolver.query(
                childrenUri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE
                ),
                null, null, null
            )?.use { cursor ->
                val idIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val mimeIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
                while (cursor.moveToNext()) {
                    val id = cursor.getString(idIndex)
                    val name = cursor.getString(nameIndex)
                    val mime = cursor.getString(mimeIndex)
                    if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                        if (name == ".Statuses") {
                            return DocumentsContract.buildDocumentUriUsingTree(treeUri, id)
                        }
                        queue.add(DirNode(id, node.depth + 1))
                    }
                }
            }
        }
        return null
    }

    private fun listStatuses(): List<Map<String, Any>> {
        val tree = getTreeUri() ?: throw IllegalStateException("اختر مجلد واتساب أولًا")
        val statusDir = findStatusesDirectory(tree)
            ?: throw IllegalStateException("لم أجد مجلد .Statuses داخل المجلد المحدد")
        val statusId = DocumentsContract.getDocumentId(statusDir)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, statusId)
        val output = mutableListOf<Map<String, Any>>()

        contentResolver.query(
            childrenUri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                DocumentsContract.Document.COLUMN_SIZE
            ),
            null, null, null
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val modifiedIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            val sizeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)

            while (cursor.moveToNext()) {
                val id = cursor.getString(idIndex)
                val name = cursor.getString(nameIndex) ?: continue
                var mime = cursor.getString(mimeIndex) ?: ""
                val ext = name.substringAfterLast('.', "").lowercase()
                val image = ext in setOf("jpg", "jpeg", "png", "webp")
                val video = ext in setOf("mp4", "3gp", "mkv", "webm")
                if (!image && !video && !mime.startsWith("image/") && !mime.startsWith("video/")) continue
                if (mime.isBlank() || mime == "application/octet-stream") {
                    mime = when {
                        video -> if (ext == "mkv") "video/x-matroska" else "video/$ext"
                        ext == "jpg" || ext == "jpeg" -> "image/jpeg"
                        else -> "image/$ext"
                    }
                }
                val uri = DocumentsContract.buildDocumentUriUsingTree(tree, id)
                output.add(
                    mapOf(
                        "uri" to uri.toString(),
                        "name" to name,
                        "mimeType" to mime,
                        "isVideo" to (mime.startsWith("video/") || video),
                        "lastModified" to if (modifiedIndex >= 0 && !cursor.isNull(modifiedIndex)) cursor.getLong(modifiedIndex) else 0L,
                        "size" to if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) cursor.getLong(sizeIndex) else 0L
                    )
                )
            }
        }
        return output.sortedByDescending { (it["lastModified"] as? Long) ?: 0L }
    }

    private fun queryName(uri: Uri): String? = contentResolver.query(
        uri,
        arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
        null, null, null
    )?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }

    private fun makeThumbnail(uri: Uri, mime: String): ByteArray? {
        val bitmap: Bitmap? = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                contentResolver.loadThumbnail(uri, Size(420, 420), null)
            } else if (mime.startsWith("video/")) {
                MediaMetadataRetriever().let { retriever ->
                    try {
                        retriever.setDataSource(this, uri)
                        retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    } finally {
                        retriever.release()
                    }
                }
            } else {
                contentResolver.openInputStream(uri)?.use(BitmapFactory::decodeStream)
            }
        } catch (_: Exception) {
            if (mime.startsWith("image/")) {
                try { contentResolver.openInputStream(uri)?.use(BitmapFactory::decodeStream) }
                catch (_: Exception) { null }
            } else null
        }
        if (bitmap == null) return null
        return ByteArrayOutputStream().use { stream ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 82, stream)
            stream.toByteArray()
        }
    }

    private fun saveStatus(source: Uri, originalName: String, mime: String, isVideo: Boolean): String {
        val safeName = if (originalName.isBlank()) "status_${System.currentTimeMillis()}" else originalName
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val relative = if (isVideo) "${Environment.DIRECTORY_MOVIES}/StatusSaver" else "${Environment.DIRECTORY_PICTURES}/StatusSaver"
            val collection = if (isVideo) {
                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            }
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, uniqueName(safeName))
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val target = contentResolver.insert(collection, values)
                ?: throw IllegalStateException("تعذر إنشاء ملف في المعرض")
            try {
                contentResolver.openInputStream(source)?.use { input ->
                    contentResolver.openOutputStream(target, "w")?.use { output -> input.copyTo(output) }
                        ?: throw IllegalStateException("تعذر فتح ملف الحفظ")
                } ?: throw IllegalStateException("تعذر قراءة الحالة")
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                contentResolver.update(target, values, null, null)
            } catch (e: Exception) {
                contentResolver.delete(target, null, null)
                throw e
            }
            return relative
        }

        val baseType = if (isVideo) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES
        val base = getExternalFilesDir(baseType) ?: filesDir
        val folder = File(base, "StatusSaver").apply { mkdirs() }
        val target = File(folder, uniqueFileName(folder, safeName))
        contentResolver.openInputStream(source)?.use { input ->
            FileOutputStream(target).use { output -> input.copyTo(output) }
        } ?: throw IllegalStateException("تعذر قراءة الحالة")
        MediaScannerConnection.scanFile(this, arrayOf(target.absolutePath), arrayOf(mime), null)
        return target.absolutePath
    }

    private fun uniqueName(name: String): String {
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        return "${base}_${System.currentTimeMillis()}$ext"
    }

    private fun uniqueFileName(folder: File, name: String): String {
        var candidate = name
        var i = 1
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        while (File(folder, candidate).exists()) {
            candidate = "${base}_$i$ext"
            i++
        }
        return candidate
    }

    private fun sanitizeName(name: String): String = name.replace(Regex("[\\\\/:*?\"<>|]"), "_")

    private fun shareStatus(uri: Uri, mime: String) {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, "مشاركة الحالة"))
    }

    private fun openStatus(uri: Uri, mime: String) {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, "فتح الحالة"))
    }
}
