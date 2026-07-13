package com.tibus.courrier

import com.tibus.courrier.printer.P3PrinterChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Pont imprimante P3/Wiseasy (SDK Wangpos repris de tibus-v2-HUB) —
        // no-op sur un appareil sans ce hardware, voir printer_service.dart.
        P3PrinterChannel.register(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }
}
