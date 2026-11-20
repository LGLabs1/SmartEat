package com.example.smarteat

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID

class BluetoothPrinterChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val PERMISSION_REQUEST = 7412
        private val SPP_UUID: UUID =
            UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    private val methodChannel =
        MethodChannel(messenger, "com.example.smarteat/bluetooth_printer")
    private val eventChannel =
        EventChannel(messenger, "com.example.smarteat/bluetooth_printer/devices")
    private val handler = Handler(Looper.getMainLooper())
    private val bluetoothManager =
        activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    private val adapter: BluetoothAdapter? = bluetoothManager?.adapter
    private val connectedSockets = mutableMapOf<String, BluetoothSocket>()

    private var eventSink: EventChannel.EventSink? = null
    private var receiverRegistered = false

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                BluetoothDevice.ACTION_FOUND -> {
                    val device = intent.getParcelableExtra<BluetoothDevice>(
                        BluetoothDevice.EXTRA_DEVICE
                    )
                    if (device != null) {
                        emitDevice(device, device.bondState == BluetoothDevice.BOND_BONDED)
                    }
                }

                BluetoothAdapter.ACTION_DISCOVERY_STARTED -> {
                    eventSink?.success(mapOf("type" to "scanStarted"))
                }

                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                    eventSink?.success(mapOf("type" to "scanFinished"))
                }

                BluetoothAdapter.ACTION_STATE_CHANGED -> {
                    val state = intent.getIntExtra(
                        BluetoothAdapter.EXTRA_STATE,
                        BluetoothAdapter.ERROR
                    )
                    if (state == BluetoothAdapter.STATE_ON) {
                        startDiscovery(false)
                    } else if (state == BluetoothAdapter.STATE_OFF) {
                        emitState("disabled")
                    }
                }
            }
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        registerReceiver()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getState" -> result.success(stateMap())

            "startDiscovery" -> {
                startDiscovery(true)
                result.success(null)
            }

            "stopDiscovery" -> {
                stopDiscovery()
                result.success(null)
            }

            "connect" -> {
                val address = call.argument<String>("address")?.trim().orEmpty()
                if (address.isEmpty()) {
                    result.error("invalid_address", "Printer address is missing", null)
                    return
                }
                if (!hasPermissions()) {
                    emitState("permission")
                    requestPermissions()
                    result.success(false)
                    return
                }
                Thread {
                    val connected = connectInternal(address)
                    handler.post { result.success(connected) }
                }.start()
            }

            "disconnect" -> {
                val address = call.argument<String>("address")?.trim().orEmpty()
                if (address.isEmpty()) {
                    result.error("invalid_address", "Printer address is missing", null)
                    return
                }
                Thread {
                    val disconnected = disconnectInternal(address)
                    handler.post { result.success(disconnected) }
                }.start()
            }

            "print" -> {
                val address = call.argument<String>("address")?.trim().orEmpty()
                val bytes = call.argument<ByteArray>("bytes")
                if (address.isEmpty() || bytes == null) {
                    result.error("invalid_receipt", "Printer address or receipt data is missing", null)
                    return
                }
                Thread {
                    val printed = printInternal(address, bytes)
                    handler.post { result.success(printed) }
                }.start()
            }

            "isConnected" -> {
                val address = call.argument<String>("address")?.trim().orEmpty()
                result.success(isConnectedInternal(address))
            }

            "openSettings" -> {
                try {
                    activity.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                    result.success(null)
                } catch (e: Exception) {
                    result.error("settings_error", e.message, null)
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun stateMap(): Map<String, Any> {
        val supported = adapter != null
        val permissionGranted = hasPermissions()
        val enabled = supported && permissionGranted && adapter?.isEnabled == true
        return mapOf(
            "supported" to supported,
            "permissionGranted" to permissionGranted,
            "enabled" to enabled,
        )
    }

    private fun hasPermissions(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return activity.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) ==
                PackageManager.PERMISSION_GRANTED &&
                activity.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
                PackageManager.PERMISSION_GRANTED
        }
        return activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestPermissions() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
            )
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        activity.requestPermissions(permissions, PERMISSION_REQUEST)
    }

    private fun startDiscovery(requestPermission: Boolean) {
        val adapter = adapter
        if (adapter == null) {
            emitState("unsupported")
            return
        }
        if (!hasPermissions()) {
            emitState("permission")
            if (requestPermission) requestPermissions()
            return
        }
        if (!adapter.isEnabled) {
            emitState("disabled")
            return
        }

        emitState("enabled")
        try {
            adapter.bondedDevices.forEach { device ->
                emitDevice(device, true)
            }
        } catch (_: SecurityException) {
        }

        try {
            if (adapter.isDiscovering) adapter.cancelDiscovery()
            adapter.startDiscovery()
        } catch (_: SecurityException) {
            emitState("permission")
        }
    }

    private fun stopDiscovery() {
        try {
            if (adapter?.isDiscovering == true) {
                adapter.cancelDiscovery()
            }
        } catch (_: SecurityException) {
        }
    }

    private fun emitState(state: String) {
        eventSink?.success(
            mapOf(
                "type" to "state",
                "state" to state,
            )
        )
    }

    private fun emitDevice(device: BluetoothDevice, bonded: Boolean) {
        val name = try {
            device.name
        } catch (_: SecurityException) {
            null
        }
        val address = try {
            device.address
        } catch (_: SecurityException) {
            null
        } ?: return
        eventSink?.success(
            mapOf(
                "type" to "device",
                "name" to name,
                "address" to address,
                "bonded" to bonded,
            )
        )
    }

    @Synchronized
    private fun connectInternal(address: String): Boolean {
        val adapter = adapter ?: return false
        if (!adapter.isEnabled) return false
        val existing = connectedSockets[address]
        if (existing?.isConnected == true) return true
        if (existing != null) {
            try {
                existing.close()
            } catch (_: IOException) {
            }
            connectedSockets.remove(address)
        }

        try {
            if (adapter.isDiscovering) adapter.cancelDiscovery()
            val device = adapter.getRemoteDevice(address)
            var socket: BluetoothSocket? = null
            try {
                socket = device.createRfcommSocketToServiceRecord(SPP_UUID)
                socket.connect()
            } catch (_: IOException) {
                try {
                    socket?.close()
                } catch (_: IOException) {
                }
                try {
                    socket = device.createInsecureRfcommSocketToServiceRecord(SPP_UUID)
                    socket.connect()
                } catch (_: IOException) {
                    try {
                        socket?.close()
                    } catch (_: IOException) {
                    }
                    return false
                }
            }
            connectedSockets[address] = socket ?: return false
            return true
        } catch (_: Exception) {
            return false
        }
    }

    @Synchronized
    private fun printInternal(address: String, bytes: ByteArray): Boolean {
        val socket = connectedSockets[address] ?: return false
        if (!socket.isConnected) {
            connectedSockets.remove(address)
            try {
                socket.close()
            } catch (_: IOException) {
            }
            return false
        }
        return try {
            val output = socket.outputStream
            output.write(bytes)
            output.flush()
            true
        } catch (_: Exception) {
            connectedSockets.remove(address)
            try {
                socket.close()
            } catch (_: IOException) {
            }
            false
        }
    }

    @Synchronized
    private fun disconnectInternal(address: String): Boolean {
        val socket = connectedSockets.remove(address) ?: return true
        return try {
            socket.close()
            true
        } catch (_: IOException) {
            false
        }
    }

    @Synchronized
    private fun isConnectedInternal(address: String): Boolean {
        return connectedSockets[address]?.isConnected == true
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        if (grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        ) {
            startDiscovery(false)
        } else {
            emitState("permission")
        }
        return true
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        startDiscovery(true)
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        stopDiscovery()
    }

    fun dispose() {
        stopDiscovery()
        connectedSockets.values.forEach { socket ->
            try {
                socket.close()
            } catch (_: IOException) {
            }
        }
        connectedSockets.clear()
        if (receiverRegistered) {
            try {
                activity.unregisterReceiver(receiver)
            } catch (_: IllegalArgumentException) {
            }
            receiverRegistered = false
        }
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    private fun registerReceiver() {
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_STARTED)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
        }
        activity.registerReceiver(receiver, filter)
        receiverRegistered = true
    }
}
