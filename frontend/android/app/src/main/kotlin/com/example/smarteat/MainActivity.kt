package com.example.smarteat

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var bluetoothPrinterChannel: BluetoothPrinterChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bluetoothPrinterChannel = BluetoothPrinterChannel(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        bluetoothPrinterChannel?.onRequestPermissionsResult(
            requestCode,
            grantResults,
        )
    }

    override fun onDestroy() {
        bluetoothPrinterChannel?.dispose()
        bluetoothPrinterChannel = null
        super.onDestroy()
    }
}
