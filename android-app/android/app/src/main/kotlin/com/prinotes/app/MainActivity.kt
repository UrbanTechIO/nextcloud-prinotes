package com.prinotes.app

import android.view.WindowInsets
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
            } else {
                result.notImplemented()
            }
        }
    }
}
