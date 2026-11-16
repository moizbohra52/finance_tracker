package com.finance.tracker

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// A FragmentActivity: local_auth shows the fingerprint / face prompt
// (BiometricPrompt) as a fragment.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The home screen widget's text (HomeWidgetService.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.finance.tracker/home_widget")
            .setMethodCallHandler { call, result ->
                if (call.method == "update") {
                    BalanceWidget.save(applicationContext, call.arguments as? Map<*, *>)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
