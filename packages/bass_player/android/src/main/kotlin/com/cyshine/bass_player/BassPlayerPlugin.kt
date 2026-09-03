package com.cyshine.bass_player

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.util.Log
import com.un4seen.bass.BASS
import com.un4seen.bass.BASS_FX
import com.un4seen.bass.BASSALAC
import com.un4seen.bass.BASSAPE
import com.un4seen.bass.BASSFLAC
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.LinkedHashMap
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.sqrt

class BassPlayerPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private lateinit var applicationContext: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private val mainHandler = Handler(Looper.getMainLooper())
    private val engineThread = HandlerThread("CyShine-BASS")
    private lateinit var engineHandler: Handler

    @Volatile private var eventSink: EventChannel.EventSink? = null
    @Volatile private var pendingNetworkRequest: Any? = null
    private val loadGeneration = AtomicInteger()

    private var initialized = false
    private var stream = 0
    private var sourceDescriptor: ParcelFileDescriptor? = null
    private var remoteSource = false
    private var playing = false
    private var completed = false
    private var processingState = STATE_IDLE
    private var durationMs: Long? = null
    private var channelVolume = 1f
    private var tickerStarted = false
    private var wakeLock: PowerManager.WakeLock? = null

    private val pluginVersions = LinkedHashMap<String, String>()
    private var bassVersion = "unknown"
    private var bassFxVersion = "unknown"

    private var equalizer = EqualizerConfiguration.disabled()
    private var inputGainFx = 0
    private var outputGainFx = 0
    private val bandFx = LinkedHashMap<String, Int>()

    private var endSync = 0
    private var stallSync = 0
    private var downloadSync = 0
    private var deviceFailureSync = 0
    private var endSyncCallback: BASS.SYNCPROC? = null
    private var stallSyncCallback: BASS.SYNCPROC? = null
    private var downloadSyncCallback: BASS.SYNCPROC? = null
    private var deviceFailureSyncCallback: BASS.SYNCPROC? = null

    private val positionTicker = object : Runnable {
        override fun run() {
            if (!initialized || !tickerShouldRun()) {
                tickerStarted = false
                return
            }
            refreshPlaybackState()
            if (playing || processingState == STATE_BUFFERING || processingState == STATE_LOADING) {
                emitSnapshot()
            }
            if (tickerShouldRun()) {
                engineHandler.postDelayed(this, POSITION_UPDATE_MS)
            } else {
                tickerStarted = false
            }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        engineThread.start()
        engineHandler = Handler(engineThread.looper)
        methods = MethodChannel(
            binding.binaryMessenger,
            "com.cyshine.music/bass_player/methods",
        )
        events = EventChannel(
            binding.binaryMessenger,
            "com.cyshine.music/bass_player/events",
        )
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        eventSink = null
        cancelPendingNetworkLoad()
        engineHandler.post {
            disposeEngine()
            engineThread.quitSafely()
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        eventSink = sink
        if (::engineHandler.isInitialized) {
            engineHandler.post { emitSnapshot() }
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> postResult(result) { initializeEngine() }
            "load" -> {
                val uri = call.argument<String>("uri")
                if (uri.isNullOrBlank()) {
                    result.error("BASS_ARGUMENT", "uri is required", null)
                    return
                }
                val generation = loadGeneration.incrementAndGet()
                cancelPendingNetworkLoad()
                val headers = (call.argument<Map<*, *>>("headers") ?: emptyMap<Any, Any>())
                    .entries
                    .associate { it.key.toString() to it.value.toString() }
                val formatHint = call.argument<String>("formatHint")
                postResult(result) { load(uri, headers, formatHint, generation) }
            }
            "play" -> postResult(result) { play() }
            "pause" -> postResult(result) { pause() }
            "stop" -> {
                loadGeneration.incrementAndGet()
                cancelPendingNetworkLoad()
                postResult(result) { stop() }
            }
            "seek" -> {
                val positionMs = call.argument<Number>("positionMs")?.toLong() ?: 0L
                postResult(result) { seek(positionMs) }
            }
            "setVolume" -> {
                val volume = call.argument<Number>("volume")?.toFloat() ?: 1f
                postResult(result) { setVolume(volume) }
            }
            "setEqualizer" -> postResult(result) {
                setEqualizer(readEqualizerConfiguration(call.arguments))
            }
            "dispose" -> {
                loadGeneration.incrementAndGet()
                cancelPendingNetworkLoad()
                postResult(result) {
                    disposeEngine()
                    emptyMap<String, Any?>()
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun postResult(
        result: MethodChannel.Result,
        operation: () -> Map<String, Any?>,
    ) {
        engineHandler.post {
            try {
                val value = operation()
                mainHandler.post { result.success(value) }
            } catch (failure: BassFailure) {
                mainHandler.post {
                    result.error(
                        "BASS_${failure.code}",
                        failure.message,
                        mapOf(
                            "operation" to failure.operation,
                            "bassCode" to failure.code,
                        ),
                    )
                }
            } catch (error: Throwable) {
                val bassCode = BASS.BASS_ErrorGetCode()
                mainHandler.post {
                    result.error(
                        "BASS_NATIVE",
                        error.message ?: error.javaClass.simpleName,
                        mapOf(
                            "operation" to "native",
                            "bassCode" to bassCode,
                        ),
                    )
                }
            }
        }
    }

    private fun initializeEngine(): Map<String, Any?> {
        if (initialized) return engineInfo()

        val rawBassVersion = BASS.BASS_GetVersion()
        bassVersion = versionString(rawBassVersion)
        if ((rawBassVersion ushr 16) != BASS.BASSVERSION) {
            throw BassFailure(
                -1,
                "initialize",
                "BASS Java API 2.4 does not match native library $bassVersion",
            )
        }

        val rawFxVersion = BASS_FX.BASS_FX_GetVersion()
        bassFxVersion = versionString(rawFxVersion)
        if ((rawFxVersion ushr 16) != BASS.BASSVERSION) {
            throw BassFailure(
                -1,
                "initialize",
                "BASS_FX API 2.4 does not match native library $bassFxVersion",
            )
        }

        setConfig(BASS.BASS_CONFIG_BUFFER, 500, "output buffer")
        setConfig(BASS.BASS_CONFIG_UPDATEPERIOD, 50, "update period")
        setConfig(BASS.BASS_CONFIG_NET_TIMEOUT, 15_000, "network connect timeout")
        setConfig(BASS.BASS_CONFIG_NET_READTIMEOUT, 20_000, "network read timeout")
        setConfig(BASS.BASS_CONFIG_NET_BUFFER, 10_000, "network buffer")
        setConfig(BASS.BASS_CONFIG_NET_PREBUF, 20, "network prebuffer")

        if (!BASS.BASS_Init(-1, 44_100, 0)) {
            fail("initialize output")
        }
        initialized = true
        try {
            loadFormatLibraries()
        } catch (error: Throwable) {
            disposeEngine()
            throw error
        }

        wakeLock = (applicationContext.getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "CyShineMusic:BassPlayback")
            .apply { setReferenceCounted(false) }
        processingState = STATE_IDLE
        Log.i(TAG, "Initialized BASS $bassVersion, BASS_FX $bassFxVersion, formats=$pluginVersions")
        emitSnapshot()
        return engineInfo()
    }

    private fun setConfig(option: Int, value: Int, label: String) {
        if (!BASS.BASS_SetConfig(option, value)) fail("configure $label")
    }

    private fun loadFormatLibraries() {
        // Modern Android installs native libraries directly from the APK, so
        // there may be no filesystem path for BASS_PluginLoad. Loading the JNI
        // add-ons by name works in both extracted and in-APK configurations;
        // playback then calls each add-on's StreamCreate API directly.
        System.loadLibrary("bassflac")
        System.loadLibrary("bassape")
        System.loadLibrary("bassalac")
        pluginVersions["flac"] = "2.4.6.1"
        pluginVersions["ape"] = "2.4.1"
        pluginVersions["alac"] = "2.4.1"
    }

    private fun engineInfo(): Map<String, Any?> = mapOf(
        "version" to bassVersion,
        "fxVersion" to bassFxVersion,
        "plugins" to LinkedHashMap(pluginVersions),
    )

    private fun load(
        source: String,
        headers: Map<String, String>,
        formatHint: String?,
        generation: Int,
    ): Map<String, Any?> {
        initializeEngine()
        if (generation != loadGeneration.get()) {
            throw BassFailure(CANCELLED, "load", "load cancelled")
        }

        releaseStream()
        playing = false
        completed = false
        durationMs = null
        processingState = STATE_LOADING
        emitSnapshot()

        val parsed = Uri.parse(source)
        val flags = BASS.BASS_SAMPLE_FLOAT
        val format = normalizedFormat(formatHint, parsed)
        val isRemote = parsed.scheme?.lowercase() in setOf("http", "https", "ftp")
        var openedDescriptor: ParcelFileDescriptor? = null
        var requestToken: Any? = null
        val handle = try {
            when (parsed.scheme?.lowercase()) {
                "http", "https", "ftp" -> {
                    requestToken = Any()
                    pendingNetworkRequest = requestToken
                    createNetworkStream(
                        format,
                        urlWithHeaders(source, headers),
                        flags,
                        requestToken,
                    )
                }
                "content" -> {
                    openedDescriptor = applicationContext.contentResolver
                        .openFileDescriptor(parsed, "r")
                        ?: throw BassFailure(
                            BASS.BASS_ERROR_FILEOPEN,
                            "load content",
                            "unable to open content URI",
                        )
                    createDescriptorStream(format, openedDescriptor, flags)
                }
                "file" -> createFileStream(format, parsed.path ?: source, flags)
                null, "" -> createFileStream(format, source, flags)
                else -> throw BassFailure(
                    BASS.BASS_ERROR_FILEOPEN,
                    "load",
                    "unsupported URI scheme: ${parsed.scheme}",
                )
            }
        } catch (error: Throwable) {
            openedDescriptor?.close()
            processingState = STATE_ERROR
            emitSnapshot()
            throw error
        } finally {
            if (pendingNetworkRequest === requestToken) pendingNetworkRequest = null
        }

        if (generation != loadGeneration.get()) {
            if (handle != 0) BASS.BASS_StreamFree(handle)
            openedDescriptor?.close()
            throw BassFailure(CANCELLED, "load", "load cancelled")
        }
        if (handle == 0) {
            val code = BASS.BASS_ErrorGetCode()
            openedDescriptor?.close()
            processingState = STATE_ERROR
            emitSnapshot()
            throw BassFailure(code, "load stream", errorMessage(code))
        }

        stream = handle
        sourceDescriptor = openedDescriptor
        remoteSource = isRemote
        try {
            if (!BASS.BASS_ChannelSetAttribute(stream, BASS.BASS_ATTRIB_VOL, channelVolume)) {
                fail("set volume")
            }
            installSynchronizers()
            applyEqualizerChain(equalizer, null)
            durationMs = readDurationMs()
            processingState = STATE_READY
            refreshPlaybackState()
        } catch (error: Throwable) {
            releaseStream()
            processingState = STATE_ERROR
            throw error
        }
        emitSnapshot()
        return snapshot()
    }

    private fun play(): Map<String, Any?> {
        initializeEngine()
        if (stream == 0) failWith(BASS.BASS_ERROR_HANDLE, "play")
        if (completed) {
            val position = BASS.BASS_ChannelSeconds2Bytes(stream, 0.0)
            if (!BASS.BASS_ChannelSetPosition(stream, position, BASS.BASS_POS_BYTE)) {
                fail("restart stream")
            }
            completed = false
        }
        if (!BASS.BASS_ChannelPlay(stream, false)) fail("play")
        playing = true
        acquireWakeLock()
        refreshPlaybackState()
        startTicker()
        emitSnapshot()
        return snapshot()
    }

    private fun pause(): Map<String, Any?> {
        if (stream == 0) return snapshot()
        if (!BASS.BASS_ChannelPause(stream)) fail("pause")
        playing = false
        releaseWakeLock()
        refreshPlaybackState()
        stopTicker()
        emitSnapshot()
        return snapshot()
    }

    private fun stop(): Map<String, Any?> {
        releaseStream()
        processingState = STATE_IDLE
        playing = false
        completed = false
        durationMs = null
        emitSnapshot()
        return snapshot()
    }

    private fun seek(requestedMs: Long): Map<String, Any?> {
        if (stream == 0) failWith(BASS.BASS_ERROR_HANDLE, "seek")
        val end = durationMs
        val targetMs = if (end == null) requestedMs.coerceAtLeast(0) else {
            requestedMs.coerceIn(0, end)
        }
        val bytePosition = BASS.BASS_ChannelSeconds2Bytes(stream, targetMs / 1000.0)
        if (bytePosition < 0 ||
            !BASS.BASS_ChannelSetPosition(stream, bytePosition, BASS.BASS_POS_BYTE)
        ) {
            fail("seek")
        }
        completed = false
        processingState = if (playing) STATE_READY else STATE_READY
        refreshPlaybackState()
        emitSnapshot()
        return snapshot()
    }

    private fun setVolume(requested: Float): Map<String, Any?> {
        channelVolume = requested.coerceIn(0f, 1f)
        if (stream != 0 &&
            !BASS.BASS_ChannelSetAttribute(stream, BASS.BASS_ATTRIB_VOL, channelVolume)
        ) {
            fail("set volume")
        }
        return snapshot()
    }

    private fun setEqualizer(configuration: EqualizerConfiguration): Map<String, Any?> {
        if (stream == 0) {
            equalizer = configuration
            return snapshot()
        }

        val previous = equalizer
        try {
            applyEqualizerChain(configuration, previous)
            equalizer = configuration
        } catch (failure: BassFailure) {
            detachEqualizer()
            try {
                applyEqualizerChain(previous, null)
            } catch (rollbackFailure: BassFailure) {
                Log.e(TAG, "Failed to restore equalizer after update failure", rollbackFailure)
                throw BassFailure(
                    failure.code,
                    failure.operation,
                    "${failure.message}; equalizer rollback failed: ${rollbackFailure.message}",
                )
            }
            throw failure
        }
        return snapshot()
    }

    private fun installSynchronizers() {
        val channel = stream
        endSyncCallback = BASS.SYNCPROC { _, callbackChannel, _, _ ->
            engineHandler.post {
                if (stream != channel || callbackChannel != channel) return@post
                completed = true
                playing = false
                processingState = STATE_COMPLETED
                releaseWakeLock()
                stopTicker()
                emitSnapshot()
            }
        }
        stallSyncCallback = BASS.SYNCPROC { _, callbackChannel, _, _ ->
            engineHandler.post {
                if (stream != channel || callbackChannel != channel) return@post
                refreshPlaybackState()
                emitSnapshot()
            }
        }
        downloadSyncCallback = BASS.SYNCPROC { _, callbackChannel, _, _ ->
            engineHandler.post {
                if (stream != channel || callbackChannel != channel) return@post
                durationMs = readDurationMs() ?: durationMs
                emitSnapshot()
            }
        }
        deviceFailureSyncCallback = BASS.SYNCPROC { _, callbackChannel, _, _ ->
            engineHandler.post {
                if (stream != channel || callbackChannel != channel) return@post
                playing = false
                processingState = STATE_ERROR
                releaseWakeLock()
                stopTicker()
                emitError(BASS.BASS_ERROR_DRIVER, "output device failed", "device")
            }
        }

        endSync = BASS.BASS_ChannelSetSync(
            stream,
            BASS.BASS_SYNC_END or BASS.BASS_SYNC_ONETIME,
            0,
            endSyncCallback,
            null,
        )
        stallSync = BASS.BASS_ChannelSetSync(
            stream,
            BASS.BASS_SYNC_STALL,
            0,
            stallSyncCallback,
            null,
        )
        downloadSync = BASS.BASS_ChannelSetSync(
            stream,
            BASS.BASS_SYNC_DOWNLOAD or BASS.BASS_SYNC_ONETIME,
            0,
            downloadSyncCallback,
            null,
        )
        deviceFailureSync = BASS.BASS_ChannelSetSync(
            stream,
            BASS.BASS_SYNC_DEV_FAIL,
            0,
            deviceFailureSyncCallback,
            null,
        )
        if (endSync == 0 || stallSync == 0 || deviceFailureSync == 0) {
            fail("install playback synchronizers")
        }
        // Local streams do not expose a download synchronizer.
        if (remoteSource && downloadSync == 0) fail("install download synchronizer")
    }

    private fun refreshPlaybackState() {
        if (stream == 0 || completed || processingState == STATE_LOADING ||
            processingState == STATE_ERROR
        ) {
            return
        }
        durationMs = readDurationMs() ?: durationMs
        when (BASS.BASS_ChannelIsActive(stream)) {
            BASS.BASS_ACTIVE_PLAYING -> {
                playing = true
                processingState = STATE_READY
                acquireWakeLock()
            }
            BASS.BASS_ACTIVE_STALLED -> {
                playing = true
                processingState = STATE_BUFFERING
                acquireWakeLock()
            }
            BASS.BASS_ACTIVE_PAUSED,
            BASS.BASS_ACTIVE_PAUSED_DEVICE,
            -> {
                playing = false
                processingState = STATE_READY
                releaseWakeLock()
            }
            BASS.BASS_ACTIVE_STOPPED -> {
                playing = false
                processingState = STATE_READY
                releaseWakeLock()
            }
        }
    }

    private fun snapshot(): Map<String, Any?> {
        val position = readPositionMs()
        return linkedMapOf(
            "event" to "snapshot",
            "playing" to playing,
            "processingState" to processingState,
            "positionMs" to position,
            "bufferedPositionMs" to readBufferedPositionMs(position),
            "durationMs" to durationMs,
        )
    }

    private fun emitSnapshot() {
        val value = snapshot()
        mainHandler.post { eventSink?.success(value) }
    }

    private fun emitError(code: Int, message: String, operation: String) {
        val value = LinkedHashMap(snapshot())
        value["event"] = "error"
        value["errorCode"] = code
        value["bassCode"] = code
        value["errorMessage"] = message
        value["operation"] = operation
        mainHandler.post { eventSink?.success(value) }
    }

    private fun readPositionMs(): Long {
        if (stream == 0) return 0
        val bytes = BASS.BASS_ChannelGetPosition(stream, BASS.BASS_POS_BYTE)
        if (bytes < 0) return 0
        val seconds = BASS.BASS_ChannelBytes2Seconds(stream, bytes)
        return if (seconds.isFinite() && seconds >= 0) (seconds * 1000).toLong() else 0
    }

    private fun readDurationMs(): Long? {
        if (stream == 0) return null
        val bytes = BASS.BASS_ChannelGetLength(stream, BASS.BASS_POS_BYTE)
        if (bytes <= 0) return null
        val seconds = BASS.BASS_ChannelBytes2Seconds(stream, bytes)
        return if (seconds.isFinite() && seconds > 0) (seconds * 1000).toLong() else null
    }

    private fun readBufferedPositionMs(positionMs: Long): Long {
        val end = durationMs ?: return positionMs
        if (!remoteSource) return end

        val fileEnd = BASS.BASS_StreamGetFilePosition(stream, BASS.BASS_FILEPOS_END)
        val downloaded = BASS.BASS_StreamGetFilePosition(stream, BASS.BASS_FILEPOS_DOWNLOAD)
        if (fileEnd > 0 && downloaded >= 0) {
            return ((end.toDouble() * downloaded / fileEnd).toLong())
                .coerceIn(positionMs, end)
        }
        // BASS_FILEPOS_BUFFERING is the current prebuffer percentage, not the
        // downloaded position in the complete file. Mapping it over the track
        // duration would advertise data that has not actually been buffered.
        return positionMs
    }

    private fun applyEqualizerChain(
        configuration: EqualizerConfiguration,
        previous: EqualizerConfiguration?,
    ) {
        if (stream == 0) return
        if (!configuration.enabled) {
            val wasAttached = inputGainFx != 0 || outputGainFx != 0 || bandFx.isNotEmpty()
            detachEqualizer(strict = true)
            if (wasAttached) Log.i(TAG, "Equalizer disabled")
            return
        }

        val previousBands = previous
            ?.takeIf { it.enabled }
            ?.bands
            ?.filter { it.enabled }
            .orEmpty()
        val previousById = previousBands.associateBy { it.id }
        val previousIndexes = previousBands
            .mapIndexed { index, band -> band.id to index }
            .toMap()

        val enabledBands = configuration.bands.filter { it.enabled }
        if (enabledBands.isEmpty() &&
            configuration.inputGainDb == 0.0 &&
            configuration.outputGainDb == 0.0
        ) {
            detachEqualizer(strict = true)
            return
        }

        val newChain = inputGainFx == 0
        if (inputGainFx == 0) {
            inputGainFx = BASS.BASS_ChannelSetFX(
                stream,
                BASS_FX.BASS_FX_BFX_VOLUME,
                INPUT_GAIN_PRIORITY,
            )
            if (inputGainFx == 0) fail("attach input gain")
        }
        if (newChain || previous?.inputGainDb != configuration.inputGainDb) {
            setGain(inputGainFx, configuration.inputGainDb, "input gain")
        }

        val expectedIds = enabledBands.mapTo(mutableSetOf()) { it.id }
        val removedIds = bandFx.keys.filterNot { expectedIds.contains(it) }
        for (id in removedIds) {
            val handle = bandFx[id] ?: continue
            if (!BASS.BASS_ChannelRemoveFX(stream, handle)) {
                fail("remove EQ band $id")
            }
            bandFx.remove(id)
        }

        val info = BASS.BASS_CHANNELINFO()
        val nyquist = if (BASS.BASS_ChannelGetInfo(stream, info)) {
            (info.freq / 2f - 1f).coerceAtLeast(1f)
        } else {
            22_049f
        }
        enabledBands.forEachIndexed { index, band ->
            var handle = bandFx[band.id] ?: 0
            val created = handle == 0
            if (handle == 0) {
                handle = BASS.BASS_ChannelSetFX(
                    stream,
                    BASS_FX.BASS_FX_BFX_BQF,
                    BAND_PRIORITY - index,
                )
                if (handle == 0) fail("attach EQ band ${band.id}")
                bandFx[band.id] = handle
            } else if (previousIndexes[band.id] != index) {
                if (!BASS.BASS_FXSetPriority(handle, BAND_PRIORITY - index)) {
                    fail("order EQ band ${band.id}")
                }
            }
            if (created || previousById[band.id] != band) {
                setBand(handle, band, nyquist)
            }
        }

        if (outputGainFx == 0) {
            outputGainFx = BASS.BASS_ChannelSetFX(
                stream,
                BASS_FX.BASS_FX_BFX_VOLUME,
                OUTPUT_GAIN_PRIORITY,
            )
            if (outputGainFx == 0) fail("attach output gain")
        }
        if (newChain || previous?.outputGainDb != configuration.outputGainDb) {
            setGain(outputGainFx, configuration.outputGainDb, "output gain")
        }
        if (newChain) {
            Log.i(
                TAG,
                "Equalizer attached: bands=${enabledBands.size}, " +
                    "input=${configuration.inputGainDb}dB, " +
                    "output=${configuration.outputGainDb}dB",
            )
        }
    }

    private fun setBand(handle: Int, band: EqualizerBand, nyquist: Float) {
        val parameters = BASS_FX.BASS_BFX_BQF().apply {
            lFilter = band.filter.bassValue
            fCenter = band.frequencyHz.toFloat().coerceAtMost(nyquist)
            fGain = if (band.filter.hasGain) band.gainDb.toFloat() else 0f
            fBandwidth = if (band.filter == EqualizerFilter.PEAKING_EQ) {
                qToBandwidth(band.q).toFloat()
            } else {
                0f
            }
            fQ = if (band.filter.isPass) band.q.toFloat() else 0f
            fS = if (band.filter.isShelf) {
                qToShelfSlope(band.gainDb, band.q).toFloat()
            } else {
                0f
            }
            lChannel = BASS_FX.BASS_BFX_CHANALL
        }
        if (!BASS.BASS_FXSetParameters(handle, parameters)) {
            fail("configure EQ band ${band.id}")
        }
    }

    private fun qToBandwidth(q: Double): Double =
        2.0 * ln((sqrt(4.0 * q * q + 1.0) + 1.0) / (2.0 * q)) / LN_2

    private fun qToShelfSlope(gainDb: Double, q: Double): Double {
        val amplitude = 10.0.pow(gainDb / 40.0)
        val slope = 1.0 / (((1.0 / (q * q) - 2.0) / (1.0 / amplitude + amplitude)) + 1.0)
        return slope.coerceAtLeast(MIN_SHELF_SLOPE)
    }

    private fun setGain(handle: Int, gainDb: Double, label: String) {
        val parameters = BASS_FX.BASS_BFX_VOLUME().apply {
            lChannel = BASS_FX.BASS_BFX_CHANNONE
            fVolume = 10.0.pow(gainDb / 20.0).toFloat()
        }
        if (!BASS.BASS_FXSetParameters(handle, parameters)) fail("configure $label")
    }

    private fun detachEqualizer(strict: Boolean = false) {
        if (stream == 0) {
            clearEqualizerHandles()
            return
        }
        if (inputGainFx != 0) removeFx(inputGainFx, "input gain", strict)
        for ((id, handle) in bandFx) {
            removeFx(handle, "EQ band $id", strict)
        }
        if (outputGainFx != 0) removeFx(outputGainFx, "output gain", strict)
        clearEqualizerHandles()
    }

    private fun removeFx(handle: Int, label: String, strict: Boolean) {
        if (BASS.BASS_ChannelRemoveFX(stream, handle)) return
        val code = BASS.BASS_ErrorGetCode()
        if (strict) throw BassFailure(code, "remove $label", errorMessage(code))
        Log.w(TAG, "Unable to detach $label, bassCode=$code")
    }

    private fun clearEqualizerHandles() {
        inputGainFx = 0
        outputGainFx = 0
        bandFx.clear()
    }

    private fun releaseStream() {
        stopTicker()
        releaseWakeLock()
        if (stream != 0) {
            detachEqualizer()
            BASS.BASS_StreamFree(stream)
        }
        stream = 0
        sourceDescriptor?.close()
        sourceDescriptor = null
        remoteSource = false
        endSync = 0
        stallSync = 0
        downloadSync = 0
        deviceFailureSync = 0
        endSyncCallback = null
        stallSyncCallback = null
        downloadSyncCallback = null
        deviceFailureSyncCallback = null
    }

    private fun disposeEngine() {
        engineHandler.removeCallbacks(positionTicker)
        tickerStarted = false
        releaseStream()
        pluginVersions.clear()
        if (initialized) BASS.BASS_Free()
        initialized = false
        processingState = STATE_IDLE
        playing = false
        completed = false
        durationMs = null
        wakeLock = null
    }

    private fun startTicker() {
        if (tickerStarted || !tickerShouldRun()) return
        tickerStarted = true
        engineHandler.post(positionTicker)
    }

    private fun stopTicker() {
        engineHandler.removeCallbacks(positionTicker)
        tickerStarted = false
    }

    private fun tickerShouldRun(): Boolean =
        initialized && stream != 0 &&
            (playing || processingState == STATE_LOADING || processingState == STATE_BUFFERING)

    private fun acquireWakeLock() {
        val lock = wakeLock ?: return
        if (!lock.isHeld) lock.acquire()
    }

    private fun releaseWakeLock() {
        val lock = wakeLock ?: return
        if (lock.isHeld) lock.release()
    }

    private fun cancelPendingNetworkLoad() {
        val request = pendingNetworkRequest ?: return
        // BASS_StreamCancel is specifically designed to be called from the
        // thread requesting cancellation while BASS_StreamCreateURL is pending.
        BASS.BASS_StreamCancel(request)
    }

    private fun urlWithHeaders(source: String, headers: Map<String, String>): String {
        if (headers.isEmpty()) return source
        return buildString {
            append(source)
            append("\r\n")
            headers.forEach { (name, value) ->
                val safeName = name.replace("\r", "").replace("\n", "")
                val safeValue = value.replace("\r", "").replace("\n", "")
                append(safeName)
                append(": ")
                append(safeValue)
                append("\r\n")
            }
            append("\r\n")
        }
    }

    private fun normalizedFormat(formatHint: String?, source: Uri): String {
        val hint = formatHint?.trim()?.lowercase().orEmpty()
        val path = source.path.orEmpty()
        val extension = path.substringAfterLast('.', "").lowercase()
        if (extension in setOf("flac", "ape", "alac", "m4a")) return extension
        return when (hint) {
            "flac", "ape", "alac", "m4a" -> hint
            "flac24bit", "hires", "master" -> "lossless"
            else -> "generic"
        }
    }

    private fun createNetworkStream(
        format: String,
        request: String,
        flags: Int,
        requestToken: Any,
    ): Int = when (format) {
        "flac" -> networkWithFallback(request, flags, requestToken) {
            BASSFLAC.BASS_FLAC_StreamCreateURL(request, 0, flags, null, requestToken)
        }
        "ape" -> networkWithFallback(request, flags, requestToken) {
            BASSAPE.BASS_APE_StreamCreateURL(request, 0, flags, null, requestToken)
        }
        "alac" -> networkWithFallback(request, flags, requestToken) {
            BASSALAC.BASS_ALAC_StreamCreateURL(request, 0, flags, null, requestToken)
        }
        "m4a" -> {
            val generic = BASS.BASS_StreamCreateURL(request, 0, flags, null, requestToken)
            if (generic != 0) generic else BASSALAC.BASS_ALAC_StreamCreateURL(
                request,
                0,
                flags,
                null,
                requestToken,
            )
        }
        "lossless" -> {
            val generic = BASS.BASS_StreamCreateURL(request, 0, flags, null, requestToken)
            if (generic != 0) generic else BASSFLAC.BASS_FLAC_StreamCreateURL(
                request,
                0,
                flags,
                null,
                requestToken,
            )
        }
        else -> BASS.BASS_StreamCreateURL(request, 0, flags, null, requestToken)
    }

    private inline fun networkWithFallback(
        request: String,
        flags: Int,
        requestToken: Any,
        specialized: () -> Int,
    ): Int {
        val specializedHandle = specialized()
        return if (specializedHandle != 0) specializedHandle else {
            BASS.BASS_StreamCreateURL(request, 0, flags, null, requestToken)
        }
    }

    private fun createFileStream(format: String, path: String, flags: Int): Int =
        when (format) {
            "flac" -> BASSFLAC.BASS_FLAC_StreamCreateFile(path, 0, 0, flags)
            "ape" -> BASSAPE.BASS_APE_StreamCreateFile(path, 0, 0, flags)
            "alac" -> BASSALAC.BASS_ALAC_StreamCreateFile(path, 0, 0, flags)
            "m4a" -> {
                val generic = BASS.BASS_StreamCreateFile(path, 0, 0, flags)
                if (generic != 0) generic else {
                    BASSALAC.BASS_ALAC_StreamCreateFile(path, 0, 0, flags)
                }
            }
            else -> BASS.BASS_StreamCreateFile(path, 0, 0, flags)
        }

    private fun createDescriptorStream(
        format: String,
        descriptor: ParcelFileDescriptor,
        flags: Int,
    ): Int = when (format) {
        "flac" -> BASSFLAC.BASS_FLAC_StreamCreateFile(descriptor, 0, 0, flags)
        "ape" -> BASSAPE.BASS_APE_StreamCreateFile(descriptor, 0, 0, flags)
        "alac" -> BASSALAC.BASS_ALAC_StreamCreateFile(descriptor, 0, 0, flags)
        "m4a" -> {
            val generic = BASS.BASS_StreamCreateFile(descriptor, 0, 0, flags)
            if (generic != 0) generic else {
                BASSALAC.BASS_ALAC_StreamCreateFile(descriptor, 0, 0, flags)
            }
        }
        else -> BASS.BASS_StreamCreateFile(descriptor, 0, 0, flags)
    }

    private fun readEqualizerConfiguration(arguments: Any?): EqualizerConfiguration {
        val map = arguments as? Map<*, *> ?: return EqualizerConfiguration.disabled()
        val rawBands = map["bands"] as? List<*> ?: emptyList<Any?>()
        if (rawBands.size > MAX_EQ_BANDS) {
            throw invalidEqualizer("at most $MAX_EQ_BANDS bands are supported")
        }
        val bands = rawBands.mapIndexed { index, raw -> readEqualizerBand(raw, index) }
        if (bands.map { it.id }.toSet().size != bands.size) {
            throw invalidEqualizer("duplicate band id")
        }
        return EqualizerConfiguration(
            enabled = map["enabled"] as? Boolean ?: false,
            inputGainDb = finiteNumber(map["inputGainDb"], 0.0, "inputGainDb")
                .coerceIn(MIN_GAIN_DB, MAX_GAIN_DB),
            outputGainDb = finiteNumber(map["outputGainDb"], 0.0, "outputGainDb")
                .coerceIn(MIN_GAIN_DB, MAX_GAIN_DB),
            bands = bands,
        )
    }

    private fun readEqualizerBand(raw: Any?, index: Int): EqualizerBand {
        val map = raw as? Map<*, *> ?: throw BassFailure(
            BASS.BASS_ERROR_ILLPARAM,
            "equalizer",
            "band $index is invalid",
        )
        val id = map["id"]?.toString()?.trim().orEmpty()
        if (id.isEmpty()) {
            throw invalidEqualizer("band id is required")
        }
        return EqualizerBand(
            id = id,
            enabled = map["enabled"] as? Boolean ?: true,
            filter = filterType(map["filter"]?.toString()),
            frequencyHz = finiteNumber(map["frequencyHz"], 1_000.0, "band $id frequencyHz")
                .coerceIn(MIN_FREQUENCY_HZ, MAX_FREQUENCY_HZ),
            gainDb = finiteNumber(map["gainDb"], 0.0, "band $id gainDb")
                .coerceIn(MIN_GAIN_DB, MAX_GAIN_DB),
            q = finiteNumber(map["q"], 1.0, "band $id q").coerceIn(MIN_Q, MAX_Q),
        )
    }

    private fun filterType(value: String?): EqualizerFilter = when (value) {
        "peaking", "peakingEq" -> EqualizerFilter.PEAKING_EQ
        "lowShelf" -> EqualizerFilter.LOW_SHELF
        "highShelf" -> EqualizerFilter.HIGH_SHELF
        "lowPass" -> EqualizerFilter.LOW_PASS
        "highPass" -> EqualizerFilter.HIGH_PASS
        else -> throw invalidEqualizer("unsupported filter: ${value ?: "null"}")
    }

    private fun finiteNumber(value: Any?, fallback: Double, label: String): Double {
        val number = (value as? Number)?.toDouble() ?: fallback
        if (!number.isFinite()) throw invalidEqualizer("$label must be finite")
        return number
    }

    private fun invalidEqualizer(message: String): BassFailure = BassFailure(
        BASS.BASS_ERROR_ILLPARAM,
        "equalizer",
        message,
    )

    private fun fail(operation: String): Nothing {
        val code = BASS.BASS_ErrorGetCode()
        throw BassFailure(code, operation, errorMessage(code))
    }

    private fun failWith(code: Int, operation: String): Nothing {
        throw BassFailure(code, operation, errorMessage(code))
    }

    private fun errorMessage(code: Int): String = when (code) {
        BASS.BASS_ERROR_MEM -> "out of memory"
        BASS.BASS_ERROR_FILEOPEN -> "unable to open the source"
        BASS.BASS_ERROR_DRIVER -> "audio output device unavailable"
        BASS.BASS_ERROR_HANDLE -> "invalid playback handle"
        BASS.BASS_ERROR_FORMAT -> "unsupported audio format"
        BASS.BASS_ERROR_POSITION -> "position is not seekable"
        BASS.BASS_ERROR_INIT -> "BASS is not initialized"
        BASS.BASS_ERROR_START -> "audio output could not start"
        BASS.BASS_ERROR_SSL -> "HTTPS support is unavailable"
        BASS.BASS_ERROR_TIMEOUT -> "network connection timed out"
        BASS.BASS_ERROR_UNSTREAMABLE -> "remote file cannot be streamed"
        BASS.BASS_ERROR_DENIED -> "source access denied"
        else -> "BASS operation failed"
    }

    private fun versionString(version: Int): String = listOf(
        version ushr 24 and 0xff,
        version ushr 16 and 0xff,
        version ushr 8 and 0xff,
        version and 0xff,
    ).dropLastWhile { it == 0 }.joinToString(".")

    private data class EqualizerConfiguration(
        val enabled: Boolean,
        val inputGainDb: Double,
        val outputGainDb: Double,
        val bands: List<EqualizerBand>,
    ) {
        companion object {
            fun disabled() = EqualizerConfiguration(false, 0.0, 0.0, emptyList())
        }
    }

    private data class EqualizerBand(
        val id: String,
        val enabled: Boolean,
        val filter: EqualizerFilter,
        val frequencyHz: Double,
        val gainDb: Double,
        val q: Double,
    )

    private enum class EqualizerFilter(
        val bassValue: Int,
        val hasGain: Boolean = false,
        val isShelf: Boolean = false,
        val isPass: Boolean = false,
    ) {
        PEAKING_EQ(BASS_FX.BASS_BFX_BQF_PEAKINGEQ, hasGain = true),
        LOW_SHELF(BASS_FX.BASS_BFX_BQF_LOWSHELF, hasGain = true, isShelf = true),
        HIGH_SHELF(BASS_FX.BASS_BFX_BQF_HIGHSHELF, hasGain = true, isShelf = true),
        LOW_PASS(BASS_FX.BASS_BFX_BQF_LOWPASS, isPass = true),
        HIGH_PASS(BASS_FX.BASS_BFX_BQF_HIGHPASS, isPass = true),
    }

    private class BassFailure(
        val code: Int,
        val operation: String,
        message: String,
    ) : RuntimeException(message)

    private companion object {
        const val POSITION_UPDATE_MS = 100L
        const val MAX_EQ_BANDS = 32
        const val MIN_FREQUENCY_HZ = 20.0
        const val MAX_FREQUENCY_HZ = 20_000.0
        const val MIN_GAIN_DB = -24.0
        const val MAX_GAIN_DB = 24.0
        const val MIN_Q = 0.1
        const val MAX_Q = 10.0
        const val MIN_SHELF_SLOPE = 0.1
        val LN_2 = ln(2.0)
        const val INPUT_GAIN_PRIORITY = 100
        const val BAND_PRIORITY = 50
        const val OUTPUT_GAIN_PRIORITY = -100
        const val CANCELLED = -2

        const val STATE_IDLE = "idle"
        const val STATE_LOADING = "loading"
        const val STATE_BUFFERING = "buffering"
        const val STATE_READY = "ready"
        const val STATE_COMPLETED = "completed"
        const val STATE_ERROR = "error"
        const val TAG = "CyShineBass"
    }
}
