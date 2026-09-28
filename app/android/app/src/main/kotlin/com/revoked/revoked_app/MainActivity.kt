package com.revoked.revoked_app

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "revoked/file_viewer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> result.success(
                        openFile(
                            call.argument<ByteArray>("bytes") ?: ByteArray(0),
                            call.argument<String>("name") ?: "file",
                            call.argument<String>("mime"),
                        )
                    )
                    "purge" -> {
                        File(cacheDir, VIEW_DIR).deleteRecursively()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Hands the bytes to whichever app views this type. The copy sits in the
     * app's private cache and is reachable only through a one-off read grant on
     * the content URI, so no storage permission is involved.
     */
    private fun openFile(bytes: ByteArray, name: String, mime: String?): Boolean {
        val dir = File(cacheDir, "$VIEW_DIR/${UUID.randomUUID()}")
        // Any failure answers false, which Dart turns into the share sheet; a
        // checked exception escaping this handler would crash the app instead.
        return try {
            dir.mkdirs()
            val file = File(dir, name)
            // The name arrives sanitized; this refuses anything that still escapes.
            if (file.canonicalFile.parentFile != dir.canonicalFile) return false
            file.writeBytes(bytes)

            val uri = FileProvider.getUriForFile(this, "$packageName.fileviewer", file)
            val type = mime?.takeIf { it.isNotBlank() } ?: "application/octet-stream"
            startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, type)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            )
            true
        } catch (e: Exception) {
            dir.deleteRecursively()
            false
        }
    }

    private companion object {
        const val VIEW_DIR = "revoked-view"
    }
}
