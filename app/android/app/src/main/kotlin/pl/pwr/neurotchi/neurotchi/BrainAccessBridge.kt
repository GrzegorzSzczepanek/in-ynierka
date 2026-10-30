package pl.pwr.neurotchi.neurotchi

import android.app.Activity
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import com.neurotec.brainaccess.core.BrainAccessClient
import com.neurotec.brainaccess.core.DeviceSession
import com.neurotec.brainaccess.core.DeviceState
import com.neurotec.brainaccess.core.DiscoveredDevice
import com.neurotec.brainaccess.core.EegChunk
import com.neurotec.brainaccess.transport.BlePermissions
import com.neurotec.brainaccess.transport.NordicTransport
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.takeWhile
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/** Most Dart <-> BrainAccessKit (Kotlin SDK): skan, polaczenie i strumien EEG. */
class BrainAccessBridge(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private val client = BrainAccessClient(NordicTransport(activity))
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var session: DeviceSession? = null
    private var streamJob: Job? = null
    private var permissionResult: CompletableDeferred<Boolean>? = null

    init {
        MethodChannel(messenger, "pl.pwr.neurotchi/brainaccess").setMethodCallHandler(this)
        EventChannel(messenger, "pl.pwr.neurotchi/brainaccess/stream").setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "scan" -> scope.launch {
                try {
                    requirePermissions()
                    result.success(scan(SCAN_MS).map { it.name }.distinct())
                } catch (e: Throwable) {
                    result.error("scan", e.message, null)
                }
            }
            "start" -> scope.launch {
                try {
                    start(
                        call.argument<String>("device")!!,
                        call.argument<Int>("channels") ?: 0,
                        call.argument<List<Int>>("bias") ?: emptyList(),
                    )
                    result.success(null)
                } catch (e: Throwable) {
                    result.error("start", e.message ?: e.toString(), null)
                }
            }
            "stop" -> scope.launch {
                stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private suspend fun requirePermissions() {
        val missing = BlePermissions.required.filter {
            activity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) return
        val answer = CompletableDeferred<Boolean>()
        permissionResult = answer
        activity.requestPermissions(missing.toTypedArray(), REQ_BLE)
        if (!answer.await()) error("Brak zgody na Bluetooth")
        if (!client.bluetoothState.value) error("Bluetooth jest wylaczony")
    }

    fun onPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQ_BLE) return
        permissionResult?.complete(
            grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED },
        )
        permissionResult = null
    }

    private suspend fun scan(ms: Long, until: String? = null): List<DiscoveredDevice> {
        val found = mutableListOf<DiscoveredDevice>()
        withTimeoutOrNull(ms) {
            client.scan().takeWhile { d ->
                found += d
                until == null || d.name != until
            }.collect {}
        }
        return found
    }

    private suspend fun start(deviceName: String, channelCount: Int, bias: List<Int>) {
        stop()
        requirePermissions()
        val device = scan(CONNECT_SCAN_MS, deviceName).lastOrNull { it.name == deviceName }
            ?: error("Nie znaleziono czepka $deviceName")
        val s = client.connect(device).getOrThrow()
        session = s
        val cfg = s.currentConfig()
        val n = if (channelCount in 1..cfg.channelCount) channelCount else cfg.channelCount
        s.configure(
            cfg.copy(
                active = List(cfg.channelCount) { it < n },
                bias = List(cfg.channelCount) { it in bias },
                srate = SRATE,
            ),
        ).getOrThrow()

        emit(mapOf("t" to "ready", "channels" to n, "fs" to SRATE))
        s.state.onEach {
            if (it is DeviceState.Disconnected || it is DeviceState.Error) {
                emit(mapOf("t" to "disconnected", "reason" to it.toString()))
            }
        }.launchIn(scope)
        streamJob = scope.launch {
            try {
                s.stream().collect { emit(chunkMessage(it)) }
            } catch (e: Throwable) {
                emit(mapOf("t" to "disconnected", "reason" to (e.message ?: "stream")))
            }
        }
    }

    private fun chunkMessage(c: EegChunk): Map<String, Any> {
        val n = c.channels.size
        val size = c.sampleCount
        val flat = DoubleArray(n * size)
        for (i in 0 until size) for (ch in 0 until n) flat[ch * size + i] = c.samples[i * n + ch].toDouble()
        return mapOf(
            "t" to "chunk",
            "first" to c.firstSampleIndex,
            "size" to size,
            "channels" to n,
            "samples" to flat,
            "contact" to ByteArray(n) { if (c.contact[it]) 1 else 0 },
            "dummy" to ByteArray(size) { if (c.isDummy[it]) 1 else 0 },
        )
    }

    private fun emit(message: Map<String, Any>) {
        main.post { sink?.success(message) }
    }

    private suspend fun stop() {
        streamJob?.cancel()
        streamJob = null
        session?.disconnect()
        session = null
    }

    fun dispose() {
        scope.cancel()
    }

    private companion object {
        const val REQ_BLE = 4711
        const val SRATE = 250
        const val SCAN_MS = 5000L
        const val CONNECT_SCAN_MS = 12000L
    }
}
