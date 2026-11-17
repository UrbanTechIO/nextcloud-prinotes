package com.prinotes.app

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.view.WindowInsets
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Height (dp) of the status bar while it is really visible; 0 when the phone hides it for the app.
        // The app uses it to place the header: below the bar when shown, at the top when hidden.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "prinotes/system").setMethodCallHandler { call, result ->
            if (call.method == "statusBarHeight") {
                val insets = window.decorView.rootWindowInsets
                if (insets == null) {
                    result.success(null)
                } else {
                    val px = insets.getInsets(WindowInsets.Type.statusBars()).top
                    result.success(px / resources.displayMetrics.density.toDouble())
                }
            } else if (call.method == "canInstallApks") {
                result.success(packageManager.canRequestPackageInstalls())
            } else if (call.method == "openInstallSettings") {
                // "Install unknown apps" page for PriNotes, where the user allows installing the update.
                startActivity(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                result.success(null)
            } else if (call.method == "installApk") {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("no_path", "path missing", null)
                } else {
                    val uri = FileProvider.getUriForFile(this, "$packageName.updates", File(path))
                    startActivity(
                        Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
