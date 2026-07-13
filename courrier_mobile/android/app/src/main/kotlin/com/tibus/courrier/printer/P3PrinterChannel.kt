package com.tibus.courrier.printer

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Pont MethodChannel exposant P3PrinterModule (SDK Wangpos/Wiseasy, repris
 * tel quel de tibus-v2-HUB) à Dart. Équivalent du couple
 * WisePrinterBridge/TPE printReceipt58/80 côté WebView, mais pour Flutter :
 * pas de JS, un appel de méthode direct.
 *
 * Côté Dart : lib/data/services/printer_service.dart (canal
 * "com.tibus.courrier/p3_printer").
 */
class P3PrinterChannel(context: Context) : MethodCallHandler {
    private val printer = P3PrinterModule(context)
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "warmUp" -> {
                printer.warmUp()
                result.success(null)
            }
            "status" -> runOnIo(result) { printer.status() }
            "printReceiptText" -> runOnIo(result) {
                val title = call.argument<String>("title") ?: ""
                val text = call.argument<String>("text") ?: ""
                val qr = call.argument<String>("qr") ?: ""
                val widthMm = call.argument<Int>("paperWidthMm") ?: 58
                if (widthMm >= 80) printer.printReceipt80(title, text, qr) else printer.printReceipt58(title, text, qr)
                null
            }
            "printReceiptStructured" -> runOnIo(result) {
                @Suppress("UNCHECKED_CAST")
                val header = (call.argument<List<Any?>>("header") ?: emptyList()).map { it.toString() }
                val reference = call.argument<String>("reference") ?: ""
                @Suppress("UNCHECKED_CAST")
                val rawRows = call.argument<List<List<Any?>>>("rows") ?: emptyList()
                val rows = rawRows.mapNotNull { row ->
                    if (row.size >= 2) row[0].toString() to row[1].toString() else null
                }
                val qr = call.argument<String>("qr") ?: ""
                val footer = call.argument<String>("footer") ?: "Powered by Tibus"
                val widthMm = call.argument<Int>("paperWidthMm") ?: 58
                if (widthMm >= 80) printer.printReceipt80(header, reference, rows, qr, footer)
                else printer.printReceipt58(header, reference, rows, qr, footer)
                null
            }
            "release" -> {
                printer.release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // Le SDK Wangpos fait des appels bloquants (I/O) : on l'exécute hors du
    // thread UI. MethodChannel.Result doit en revanche être invoqué sur le
    // thread principal (contrainte Flutter) — d'où le withContext(Main) pour
    // renvoyer le résultat.
    private fun runOnIo(result: Result, block: () -> Any?) {
        scope.launch {
            try {
                val value = block()
                withContext(Dispatchers.Main) { result.success(value) }
            } catch (t: Throwable) {
                withContext(Dispatchers.Main) {
                    result.error("P3_PRINTER_ERROR", t.message ?: t::class.java.simpleName, null)
                }
            }
        }
    }

    companion object {
        const val CHANNEL_NAME = "com.tibus.courrier/p3_printer"

        fun register(context: Context, messenger: io.flutter.plugin.common.BinaryMessenger) {
            MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler(P3PrinterChannel(context))
        }
    }
}
