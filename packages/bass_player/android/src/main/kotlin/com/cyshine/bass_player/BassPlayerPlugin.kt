package com.cyshine.bass_player

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.os.SystemClock
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
import java.io.File
import java.io.IOException
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

    private val diagnostics = PlaybackDiagnostics { record ->
        val value = linkedMapOf<String, Any?>("event" to "diagnostic", "record" to record)
        mainHandler.post { eventSink?.success(value) }
    }
    private var snapshotSequence = 0L
    private var previousClockSource: String? = null
    private var previousClockPosition = 0L
    private var previousClockTime = 0L
    private val grooveShift: GrooveShiftEngine by lazy {
        GrooveShiftEngine(applicationContext, engineHandler,
            { path, flags -> createFileStream(normalizedFormat(null, Uri.parse(path)), path, flags) },
            { phase, id, details ->
                val value = LinkedHashMap(snapshot())
                value["event"] = "groove-shift"
                value["phase"] = phase
                value["transitionId"] = id
                value.putAll(details)
                if (phase == "handoff" || phase == "finished") {
                    durationMs = grooveShiftDuration()
                    value["durationMs"] = durationMs
                }
                if (diagnostics.smartTransitionEnabled) {
                    diagnostics.record("phase_$phase", value.filterKeys { it != "event" } + grooveShift.clockDetails())
                }
                mainHandler.post { eventSink?.success(value) }
            })
    }
    private fun grooveShiftDuration(): Long? = grooveShift.duration()
    private var initialized = false
    private var stream = 0
    private var sourceDescriptor: ParcelFileDescriptor? = null
    private var remoteSource = false
    // Remote files stream through this cache unless the format needs BASS's
    // own HTTP stream (remoteSource), eg. AAC decoded by Android codecs.
    @Volatile private var httpSource: ProgressiveHttpSource? = null
    @Volatile private var openingSource: ProgressiveHttpSource? = null
    private var pendingSeekMs: Long? = null
    private var pendingSeekPlay = false
    private var pendingSeekOriginMs = 0L
    private var startBufferBytes = ProgressiveHttpSource.DEFAULT_RESUME_BYTES
    private var reportedNetworkError: String? = null
    private var reportedSourceFailure = false
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    @Volatile private var networkAvailable: Boolean? = null
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
            completePendingSeekWhenBuffered()
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
        engineHandler.post(::clearStreamCache)
        registerNetworkCallback()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        eventSink = null
        unregisterNetworkCallback()
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
            "setDiagnosticRecording" -> postResult(result) {
                diagnostics.configure(
                    playback = call.argument<Boolean>("playback") == true,
                    smartTransition = call.argument<Boolean>("smartTransition") == true,
                )
                grooveShift.onDiagnostic = if (diagnostics.smartTransitionEnabled) {
                    { action, fields -> diagnostics.record(action, fields) }
                } else null
                emptyMap<String, Any?>()
            }
            "getDiagnostics" -> postResult(result) { mapOf("lines" to diagnostics.recent()) }
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
            "setGrooveShift" -> postResult(result) {
                grooveShift.configure(call.argument<Boolean>("enabled") == true)
                snapshot()
            }
            "setGrooveShiftNext" -> postResult(result) {
                grooveShift.next(call.argument<String>("id"), call.argument<String>("uri"))
                snapshot()
            }
            "confirmGrooveShift" -> postResult(result) {
                grooveShift.confirm(call.argument<String>("id") ?: "")
                snapshot()
            }
            "cancelGrooveShift" -> {
                grooveShift.invalidate()
                postResult(result) { grooveShift.cancel(); snapshot() }
            }
            "play" -> {
                httpSource?.interruptBlocking()
                postResult(result) { play() }
            }
            "pause" -> {
                httpSource?.interruptBlocking()
                postResult(result) { pause() }
            }
            "stop" -> {
                loadGeneration.incrementAndGet()
                cancelPendingNetworkLoad()
                postResult(result) { stop() }
            }
            "seek" -> {
                val positionMs = call.argument<Number>("positionMs")?.toLong() ?: 0L
                // A newer target replaces a seek that is still waiting for data.
                httpSource?.interruptBlocking()
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
        setConfig(BASS.BASS_CONFIG_NET_TIMEOUT, ProgressiveHttpSource.CONNECT_TIMEOUT_MS, "network connect timeout")
        setConfig(BASS.BASS_CONFIG_NET_READTIMEOUT, 20_000, "network read timeout")
        setConfig(BASS.BASS_CONFIG_NET_BUFFER, 60_000, "network buffer")
        setConfig(BASS.BASS_CONFIG_NET_PREBUF, 20, "network prebuffer")

        // Both output backends share the same BASS decoding and EQ chain.
        if (!BASS.BASS_Init(-1, 44_100, OUTPUT_BACKEND.initFlags)) {
            fail("initialize output")
        }
        BASS.BASS_Start()
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
        logOutputState("initialize")
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
        grooveShift.resetPlaybackEnded()
        playing = false
        completed = false
        durationMs = null
        processingState = STATE_LOADING
        emitSnapshot()

        val parsed = Uri.parse(source)
        val flags = BASS.BASS_SAMPLE_FLOAT
        val format = normalizedFormat(formatHint, parsed)
        val scheme = parsed.scheme?.lowercase()
        val isRemote = scheme in setOf("http", "https", "ftp")
        var openedDescriptor: ParcelFileDescriptor? = null
        var progressive: ProgressiveHttpSource? = null
        var requestToken: Any? = null
        val handle = try {
            if (!isRemote) grooveShift.load(source) else when (scheme) {
                "http", "https", "ftp" -> {
                    val opened = if (scheme != "ftp" && supportsProgressive(format, parsed)) {
                        openProgressiveStream(source, headers, format, flags, generation)
                    } else {
                        null
                    }
                    progressive = opened?.source
                    when {
                        opened != null -> opened.handle
                        generation != loadGeneration.get() -> 0
                        else -> {
                            requestToken = Any()
                            pendingNetworkRequest = requestToken
                            createNetworkStream(
                                format,
                                urlWithHeaders(source, headers),
                                flags,
                                requestToken,
                                generation,
                            )
                        }
                    }
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
            progressive?.close()
            processingState = STATE_ERROR
            emitSnapshot()
            throw error
        } finally {
            if (pendingNetworkRequest === requestToken) pendingNetworkRequest = null
        }

        if (generation != loadGeneration.get()) {
            if (handle != 0) BASS.BASS_StreamFree(handle)
            progressive?.close()
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
        remoteSource = isRemote && progressive == null
        httpSource = progressive
        reportedNetworkError = null
        reportedSourceFailure = false
        try {
            if (!BASS.BASS_ChannelSetAttribute(stream, BASS.BASS_ATTRIB_VOL, channelVolume)) {
                fail("set volume")
            }
            installSynchronizers()
            applyEqualizerChain(equalizer, null)
            logOutputState("load")
            durationMs = readDurationMs()
            progressive?.let(::configureProgressiveBuffering)
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
        if (diagnostics.playbackEnabled) {
            diagnostics.record("play", grooveShift.clockDetails(), category = DiagnosticCategory.PLAYBACK)
        }
        initializeEngine()
        if (stream == 0) failWith(BASS.BASS_ERROR_HANDLE, "play")
        grooveShift.resetPlaybackEnded()
        if (pendingSeekMs != null) {
            // The pending seek starts the channel once its target has downloaded.
            pendingSeekPlay = true
            refreshPlaybackState()
            startTicker()
            emitSnapshot()
            return snapshot()
        }
        // A download waiting out a retry delay should try again right away.
        httpSource?.retryNow(reconnect = false)
        if (completed) {
            val position = BASS.BASS_ChannelSeconds2Bytes(stream, 0.0)
            if (!(if (grooveShift.active) grooveShift.seek(0) else BASS.BASS_ChannelSetPosition(stream, position, BASS.BASS_POS_BYTE))) {
                fail("restart stream")
            }
            completed = false
        }
        if (!startOutputDeviceAndPlay(stream)) fail("play")
        playing = true
        acquireWakeLock()
        refreshPlaybackState()
        startTicker()
        emitSnapshot()
        return snapshot()
    }

    private fun pause(): Map<String, Any?> {
        if (diagnostics.playbackEnabled) {
            diagnostics.record("pause", grooveShift.clockDetails(), category = DiagnosticCategory.PLAYBACK)
        }
        if (stream == 0) return snapshot()
        if (pendingSeekMs != null) {
            // The channel is already paused; the ticker still completes the seek.
            pendingSeekPlay = false
            refreshPlaybackState()
            emitSnapshot()
            return snapshot()
        }
        if (!BASS.BASS_ChannelPause(stream) &&
            BASS.BASS_ErrorGetCode() !in setOf(BASS.BASS_ERROR_NOPLAY, BASS.BASS_ERROR_ALREADY)
        ) {
            fail("pause")
        }
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
        val source = httpSource
        if (source != null && !grooveShift.active) return seekProgressive(source, targetMs)
        val originMs = readPositionMs()
        val bytePosition = BASS.BASS_ChannelSeconds2Bytes(stream, targetMs / 1000.0)
        var success = if (grooveShift.active) grooveShift.seek(targetMs) else bytePosition >= 0 && BASS.BASS_ChannelSetPosition(stream, bytePosition, BASS.BASS_POS_BYTE)
        if (!success && remoteSource && BASS.BASS_ErrorGetCode() == BASS.BASS_ERROR_POSITION) {
            val startWait = SystemClock.uptimeMillis()
            val maxWaitMs = 1500L
            while (!success && (SystemClock.uptimeMillis() - startWait) < maxWaitMs) {
                try {
                    Thread.sleep(50)
                } catch (_: InterruptedException) {
                    break
                }
                if (stream == 0) break
                success = BASS.BASS_ChannelSetPosition(stream, bytePosition, BASS.BASS_POS_BYTE)
            }
        }
        if (!success) {
            if (remoteSource) {
                Log.w(
                    TAG,
                    "Remote stream seek to ${targetMs}ms failed (bassCode=${BASS.BASS_ErrorGetCode()}), staying at ${originMs}ms",
                )
                val origin = BASS.BASS_ChannelSeconds2Bytes(stream, originMs / 1000.0)
                if (origin >= 0) {
                    BASS.BASS_ChannelSetPosition(stream, origin, BASS.BASS_POS_BYTE)
                }
            } else {
                fail("seek")
            }
        }
        completed = false
        processingState = if (playing) STATE_READY else STATE_READY
        refreshPlaybackState()
        emitSnapshot()
        return snapshot()
    }

    /**
     * Seeks without failing on data that has not downloaded yet. The stream reports
     * the target as buffering and the position ticker applies the seek once the
     * decoder can read there.
     */
    private fun seekProgressive(source: ProgressiveHttpSource, targetMs: Long): Map<String, Any?> {
        if (pendingSeekMs == null) {
            pendingSeekPlay = playing
            pendingSeekOriginMs = readPositionMs()
        }
        pendingSeekMs = targetMs
        completed = false
        // Silence the old position meanwhile; a failed FLAC attempt would also rewind to 0.
        val active = BASS.BASS_ChannelIsActive(stream)
        if (active == BASS.BASS_ACTIVE_PLAYING || active == BASS.BASS_ACTIVE_STALLED) {
            BASS.BASS_ChannelPause(stream)
        }
        source.prioritize(estimateFileOffset(targetMs, source))
        if (!attemptPendingSeek(source, 0)) {
            tracePlayback(
                "seek_waiting",
                mapOf("targetMs" to targetMs, "fileOffset" to source.priorityPosition),
            )
        }
        refreshPlaybackState()
        startTicker()
        emitSnapshot()
        return snapshot()
    }

    /** Applies the pending seek; false while the decoder still lacks data at the target. */
    private fun attemptPendingSeek(source: ProgressiveHttpSource, budgetMs: Long): Boolean {
        val targetMs = pendingSeekMs ?: return true
        val bytes = BASS.BASS_ChannelSeconds2Bytes(stream, targetMs / 1000.0)
        source.beginBlocking(budgetMs)
        val moved = bytes >= 0 && BASS.BASS_ChannelSetPosition(stream, bytes, BASS.BASS_POS_BYTE)
        val code = BASS.BASS_ErrorGetCode()
        val starved = source.endBlocking()
        // Even a seek that "worked" without its data lands inexactly on some
        // formats (MP3), so redo it once the decoder can read at the target.
        if (starved) return false
        pendingSeekMs = null
        source.prioritize(null)
        if (!moved) {
            Log.w(TAG, "Progressive seek to ${targetMs}ms failed (bassCode=$code), staying at ${pendingSeekOriginMs}ms")
            val origin = BASS.BASS_ChannelSeconds2Bytes(stream, pendingSeekOriginMs / 1000.0)
            if (origin >= 0) BASS.BASS_ChannelSetPosition(stream, origin, BASS.BASS_POS_BYTE)
        }
        tracePlayback("seek_applied", mapOf("targetMs" to targetMs, "moved" to moved, "bassCode" to code))
        // Resume from a few seconds of buffer instead of stuttering on the first bytes.
        source.holdUntilBuffered(startBufferBytes)
        if (pendingSeekPlay && !startOutputDeviceAndPlay(stream)) {
            Log.w(TAG, "Unable to resume after seek (bassCode=${BASS.BASS_ErrorGetCode()})")
        }
        return true
    }

    private fun startOutputDeviceAndPlay(channel: Int): Boolean {
        // Ensure the BASS global audio output system is running.
        // BASS_IsStarted returns 0 (stopped), 1 (started), 2 (paused).
        if (BASS.BASS_IsStarted() != 1) {
            if (!BASS.BASS_Start()) {
                val startErr = BASS.BASS_ErrorGetCode()
                if (startErr != BASS.BASS_ERROR_ALREADY) {
                    Log.w(TAG, "BASS_Start returned false (bassCode=$startErr)")
                }
            }
        }
        if (BASS.BASS_ChannelPlay(channel, false)) return true
        val error = BASS.BASS_ErrorGetCode()
        if (error == BASS.BASS_ERROR_START) {
            Log.w(TAG, "BASS_ChannelPlay failed with BASS_ERROR_START, attempting recovery with BASS_Start")
            if (BASS.BASS_Start() && BASS.BASS_ChannelPlay(channel, false)) {
                return true
            }
            // Device routing changed (eg. screen mirroring / wireless display / bluetooth)
            // Reinitialize the output device while preserving channels.
            val currentDevice = BASS.BASS_GetDevice()
            val reinitDevice = if (currentDevice >= 0) currentDevice else -1
            Log.w(TAG, "Attempting BASS device reinit on device $reinitDevice")
            if (BASS.BASS_Init(reinitDevice, 44_100, BASS.BASS_DEVICE_REINIT or OUTPUT_BACKEND.initFlags)) {
                BASS.BASS_Start()
                if (BASS.BASS_ChannelPlay(channel, false)) return true
            }
        }
        return false
    }

    private fun completePendingSeekWhenBuffered() {
        val targetMs = pendingSeekMs ?: return
        val source = httpSource ?: return
        val position = source.priorityPosition
            ?: estimateFileOffset(targetMs, source).also(source::prioritize)
        if (source.isBuffered(position, SEEK_PROBE_BYTES) && attemptPendingSeek(source, SEEK_ATTEMPT_BUDGET_MS)) {
            // A seek finishing while paused gets no further ticker snapshots.
            refreshPlaybackState()
            emitSnapshot()
        }
    }

    private fun estimateFileOffset(targetMs: Long, source: ProgressiveHttpSource): Long {
        val duration = durationMs ?: return 0
        if (duration <= 0) return 0
        val fraction = (targetMs.toDouble() / duration).coerceIn(0.0, 1.0)
        return audioDataStart() + (audioDataBytes(source) * fraction).toLong()
    }

    private fun audioDataStart(): Long =
        BASS.BASS_StreamGetFilePosition(stream, BASS.BASS_FILEPOS_START).coerceAtLeast(0)

    // FILEPOS_END excludes leading tags, so it is the audio length counted from FILEPOS_START.
    private fun audioDataBytes(source: ProgressiveHttpSource): Long {
        val end = BASS.BASS_StreamGetFilePosition(stream, BASS.BASS_FILEPOS_END)
        return if (end > 0) end else source.totalBytes - audioDataStart()
    }

    private fun configureProgressiveBuffering(source: ProgressiveHttpSource) {
        val duration = durationMs
        val audioBytes = audioDataBytes(source)
        val bytesPerSecond = if (duration != null && duration > 0 && audioBytes > 0) {
            audioBytes * 1000.0 / duration
        } else {
            FALLBACK_BYTES_PER_SECOND
        }
        startBufferBytes = (bytesPerSecond * START_BUFFER_SECONDS).toLong()
            .coerceIn(MIN_BUFFER_BYTES, MAX_BUFFER_BYTES)
        source.setResumeBytes(
            (bytesPerSecond * RESUME_BUFFER_SECONDS).toLong().coerceIn(MIN_BUFFER_BYTES, MAX_BUFFER_BYTES),
        )
        source.holdUntilBuffered(startBufferBytes)
    }

    private fun setVolume(requested: Float): Map<String, Any?> {
        channelVolume = requested.coerceIn(0f, 1f)
        if (stream != 0 &&
            !BASS.BASS_ChannelSetAttribute(stream, BASS.BASS_ATTRIB_VOL, channelVolume)
        ) {
            fail("set volume")
        }
        if (initialized) logOutputState("volume")
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
            if (configuration.enabled != previous.enabled) logOutputState("equalizer")
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

    private fun logOutputState(reason: String) {
        val info = BASS.BASS_INFO()
        if (!BASS.BASS_GetInfo(info)) return
        val backend = when {
            info.initflags and BASS.BASS_DEVICE_AUDIOTRACK != 0 -> "AudioTrack"
            info.initflags and BASS.BASS_DEVICE_OPENSLES != 0 -> "OpenSL ES"
            else -> "AAudio"
        }
        val volume = BASS.FloatValue()
        val actualVolume = if (stream != 0 &&
            BASS.BASS_ChannelGetAttribute(stream, BASS.BASS_ATTRIB_VOL, volume)
        ) volume.value else null
        Log.i(
            TAG,
            "Output ($reason): backend=$backend, mixRate=${info.freq}Hz, " +
                "mixChannels=${info.speakers}, initFlags=0x${info.initflags.toString(16)}, " +
                "globalStreamVolume=${BASS.BASS_GetConfig(BASS.BASS_CONFIG_GVOL_STREAM)}, " +
                "channelVolume=$actualVolume, eq=${equalizer.enabled}, " +
                "inputGainFx=$inputGainFx, bandFxCount=${bandFx.size}, outputGainFx=$outputGainFx",
        )
    }

    private fun installSynchronizers() {
        val channel = stream
        endSyncCallback = BASS.SYNCPROC { _, callbackChannel, _, _ ->
            engineHandler.post {
                if (stream != channel || callbackChannel != channel) return@post
                if (remoteSource && legacyStreamEndedEarly()) {
                    // BASS ends an internet stream whose download broke off. Report a
                    // failure so the player reloads here instead of skipping the track.
                    playing = false
                    processingState = STATE_READY
                    releaseWakeLock()
                    stopTicker()
                    tracePlayback(
                        "remote_truncated",
                        mapOf("positionMs" to readPositionMs(), "durationMs" to durationMs),
                    )
                    emitError(BASS.BASS_ERROR_ENDED, "network stream ended before the track finished", "stream-ended")
                    return@post
                }
                completed = true
                grooveShift.markPlaybackEnded()
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
            // The same stream is reused after seeking for repeat-one/replay.
            // Keep reporting completion on every pass until the stream is freed.
            BASS.BASS_SYNC_END,
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

    private fun legacyStreamEndedEarly(): Boolean {
        val duration = durationMs ?: return false
        if (readPositionMs() >= duration - TRUNCATED_END_TOLERANCE_MS) return false
        val size = BASS.BASS_StreamGetFilePosition(stream, BASS.BASS_FILEPOS_SIZE)
        val downloaded = BASS.BASS_StreamGetFilePosition(stream, BASS.BASS_FILEPOS_DOWNLOAD)
        // Android codec streams only expose the size, so the early position is the evidence.
        if (downloaded < 0 || size <= 0) return true
        return audioDataStart() + downloaded < size
    }

    private fun refreshPlaybackState() {
        if (stream == 0 || completed || processingState == STATE_LOADING ||
            processingState == STATE_ERROR
        ) {
            return
        }
        durationMs = readDurationMs() ?: durationMs
        if (pendingSeekMs != null) {
            playing = pendingSeekPlay
            processingState = STATE_BUFFERING
            if (playing) acquireWakeLock() else releaseWakeLock()
            return
        }
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
        val position = pendingSeekMs ?: readPositionMs()
        val sourceId = grooveShift.sourceId() ?: "load-${loadGeneration.get()}"
        val now = SystemClock.elapsedRealtime()
        if (diagnostics.smartTransitionEnabled && grooveShift.active && (previousClockSource != sourceId ||
                position < previousClockPosition - 600 ||
                position > previousClockPosition + (now - previousClockTime) + 1500)) {
            diagnostics.record("clock_jump", grooveShift.clockDetails() + mapOf(
                "fromSource" to previousClockSource, "toSource" to sourceId,
                "fromMs" to previousClockPosition, "toMs" to position,
                "elapsedMs" to (now-previousClockTime), "durationMs" to durationMs,
                "snapshotSeq" to (snapshotSequence+1)), 1000)
        }
        previousClockSource = sourceId
        previousClockPosition = position
        previousClockTime = now
        if(diagnostics.smartTransitionEnabled && grooveShift.active) diagnostics.record("clock", grooveShift.clockDetails() + mapOf(
            "positionMs" to position, "durationMs" to durationMs,
            "playing" to playing, "state" to processingState), 1000)
        return linkedMapOf(
            "event" to "snapshot",
            "snapshotSeq" to ++snapshotSequence,
            "sourceId" to sourceId,
            "nativeMonoMs" to now,
            "playing" to playing,
            "processingState" to processingState,
            "positionMs" to position,
            "bufferedPositionMs" to readBufferedPositionMs(position),
            "durationMs" to durationMs,
            "networkError" to httpSource?.networkError,
            "networkAvailable" to networkAvailable,
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
        if (grooveShift.active) return grooveShift.position()
        if (stream == 0) return 0
        val bytes = BASS.BASS_ChannelGetPosition(stream, BASS.BASS_POS_BYTE)
        if (bytes < 0) return 0
        val seconds = BASS.BASS_ChannelBytes2Seconds(stream, bytes)
        return if (seconds.isFinite() && seconds >= 0) (seconds * 1000).toLong() else 0
    }

    private fun readDurationMs(): Long? {
        if (grooveShift.active) return grooveShift.duration()
        if (stream == 0) return null
        val bytes = BASS.BASS_ChannelGetLength(stream, BASS.BASS_POS_BYTE)
        if (bytes <= 0) return null
        val seconds = BASS.BASS_ChannelBytes2Seconds(stream, bytes)
        return if (seconds.isFinite() && seconds > 0) (seconds * 1000).toLong() else null
    }

    private fun readBufferedPositionMs(positionMs: Long): Long {
        val end = durationMs ?: return positionMs
        val source = httpSource
        if (source != null) {
            if (pendingSeekMs != null) return positionMs
            val audioBytes = audioDataBytes(source)
            val decoded = BASS.BASS_StreamGetFilePosition(stream, BASS.BASS_FILEPOS_CURRENT)
            if (audioBytes <= 0 || decoded < 0) return positionMs
            val start = audioDataStart()
            val buffered = source.runEnd(start + decoded) - start
            return (end.toDouble() * buffered / audioBytes).toLong().coerceIn(positionMs, end)
        }
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
        grooveShift.close()
        stopTicker()
        releaseWakeLock()
        pendingSeekMs = null
        if (stream != 0) {
            detachEqualizer()
            BASS.BASS_StreamFree(stream)
        }
        stream = 0
        // BASS no longer reads a freed stream, so its download and cache can go.
        httpSource?.close()
        httpSource = null
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
        openingSource?.cancel()
        httpSource?.interruptBlocking()
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

    // MP4 audio is mostly AAC, which BASS hands to Android codecs. Those end the
    // stream when a read comes back empty, so it keeps BASS's own HTTP stream.
    private fun supportsProgressive(format: String, source: Uri): Boolean {
        if (format == "m4a") return false
        val extension = source.path.orEmpty().substringAfterLast('.', "").lowercase()
        return extension !in LEGACY_STREAM_EXTENSIONS
    }

    private class ProgressiveStream(val handle: Int, val source: ProgressiveHttpSource)

    /** Opens [url] through a range-request cache; null when BASS's HTTP stream must play it. */
    private fun openProgressiveStream(
        url: String,
        headers: Map<String, String>,
        format: String,
        flags: Int,
        generation: Int,
    ): ProgressiveStream? {
        val directory = File(applicationContext.cacheDir, STREAM_CACHE_DIRECTORY).apply { mkdirs() }
        val source = try {
            ProgressiveHttpSource(
                url,
                headers,
                File(directory, "stream-${SystemClock.elapsedRealtimeNanos()}.part"),
                ::onSourceStateChanged,
            )
        } catch (error: IOException) {
            Log.w(TAG, "Unable to create a stream cache, using a BASS stream", error)
            return null
        }
        openingSource = source
        val started = SystemClock.elapsedRealtime()
        try {
            if (generation != loadGeneration.get()) {
                source.close()
                return null
            }
            try {
                source.open(SOURCE_OPEN_TIMEOUT_MS)
            } catch (failure: SourceException) {
                source.close()
                tracePlayback("progressive_open_failed", mapOf("kind" to failure.kind.name, "error" to failure.message))
                if (failure.kind == SourceException.Kind.UNSUPPORTED ||
                    failure.kind == SourceException.Kind.CANCELLED
                ) {
                    return null
                }
                throw BassFailure(failure.bassCode(), "load network", failure.message ?: "network error")
            }
            source.beginBlocking(STREAM_CREATE_BUDGET_MS)
            val handle = createUserStream(format, source, flags)
            val starved = source.endBlocking()
            tracePlayback(
                "progressive_open",
                mapOf(
                    "handle" to handle,
                    "elapsedMs" to SystemClock.elapsedRealtime() - started,
                    "totalBytes" to source.totalBytes,
                    "starved" to starved,
                    "bassCode" to if (handle == 0) BASS.BASS_ErrorGetCode() else 0,
                ),
            )
            if (handle != 0) return ProgressiveStream(handle, source)
            source.close()
            if (starved && generation == loadGeneration.get()) {
                throw BassFailure(BASS.BASS_ERROR_TIMEOUT, "load network", "timed out reading the stream header")
            }
            return null
        } catch (error: Throwable) {
            source.close()
            throw error
        } finally {
            if (openingSource === source) openingSource = null
        }
    }

    private fun createUserStream(format: String, source: ProgressiveHttpSource, flags: Int): Int {
        // Keep progressive streams on BASS decoders; see supportsProgressive.
        val androidCodecs = BASS.BASS_GetConfig(BASS.BASS_CONFIG_AM_DISABLE)
        if (androidCodecs >= 0) BASS.BASS_SetConfig(BASS.BASS_CONFIG_AM_DISABLE, 1)
        try {
            val system = BASS.STREAMFILE_NOBUFFER
            val decoders = when (format) {
                "flac", "lossless" -> listOf(FLAC_DECODER, GENERIC_DECODER)
                "ape" -> listOf(APE_DECODER, GENERIC_DECODER)
                "alac" -> listOf(ALAC_DECODER, GENERIC_DECODER)
                else -> listOf(GENERIC_DECODER, FLAC_DECODER)
            }
            for (decoder in decoders) {
                // A rejected attempt may leave the read position anywhere in the file.
                source.rewind()
                val handle = when (decoder) {
                    FLAC_DECODER -> BASSFLAC.BASS_FLAC_StreamCreateFileUser(system, flags, source, null)
                    APE_DECODER -> BASSAPE.BASS_APE_StreamCreateFileUser(system, flags, source, null)
                    ALAC_DECODER -> BASSALAC.BASS_ALAC_StreamCreateFileUser(system, flags, source, null)
                    else -> BASS.BASS_StreamCreateFileUser(system, flags, source, null)
                }
                if (handle != 0) return handle
            }
            return 0
        } finally {
            if (androidCodecs >= 0) BASS.BASS_SetConfig(BASS.BASS_CONFIG_AM_DISABLE, androidCodecs)
        }
    }

    private fun onSourceStateChanged(source: ProgressiveHttpSource) {
        engineHandler.post { handleSourceState(source) }
    }

    private fun handleSourceState(source: ProgressiveHttpSource) {
        if (source !== httpSource) return
        val networkError = source.networkError
        if (networkError != reportedNetworkError) {
            reportedNetworkError = networkError
            Log.i(TAG, "Progressive stream network ${networkError ?: "recovered"}")
            tracePlayback(
                if (networkError == null) "network_recovered" else "network_retrying",
                mapOf(
                    "error" to networkError,
                    "positionMs" to readPositionMs(),
                    "downloadedBytes" to source.downloadedBytes,
                    "totalBytes" to source.totalBytes,
                ),
            )
            emitSnapshot()
        }
        val failure = source.failure
        if (failure != null && !reportedSourceFailure) {
            reportedSourceFailure = true
            tracePlayback("network_failed", mapOf("error" to failure.message, "status" to failure.status))
            emitError(
                failure.bassCode(),
                failure.message ?: "network error",
                if (failure.expiredUrl) "source-expired" else "network",
            )
        }
        if (source.isComplete) emitSnapshot()
    }

    private fun SourceException.bassCode(): Int = when (kind) {
        SourceException.Kind.OFFLINE -> BASS.BASS_ERROR_NONET
        SourceException.Kind.TIMEOUT -> BASS.BASS_ERROR_TIMEOUT
        SourceException.Kind.HTTP -> BASS.BASS_ERROR_FILEOPEN
        SourceException.Kind.UNSUPPORTED -> BASS.BASS_ERROR_FILEFORM
        SourceException.Kind.CANCELLED -> CANCELLED
    }

    private fun tracePlayback(action: String, fields: Map<String, Any?>) {
        if (diagnostics.playbackEnabled) {
            diagnostics.record(action, fields, category = DiagnosticCategory.PLAYBACK)
        }
    }

    private fun clearStreamCache() {
        File(applicationContext.cacheDir, STREAM_CACHE_DIRECTORY).listFiles()?.forEach { it.delete() }
    }

    private fun registerNetworkCallback() {
        val manager = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE)
            as? ConnectivityManager ?: return
        networkAvailable = try {
            manager.activeNetwork?.let(manager::getNetworkCapabilities)
                ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        } catch (_: RuntimeException) {
            null
        }
        // Default-network callbacks report on the current network; synchronous
        // ConnectivityManager queries are unreliable while they run.
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = updateNetwork(true, replaced = true)

            override fun onLost(network: Network) = updateNetwork(false, replaced = false)

            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) =
                updateNetwork(
                    capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET),
                    replaced = false,
                )
        }
        try {
            manager.registerDefaultNetworkCallback(callback)
            networkCallback = callback
        } catch (error: RuntimeException) {
            Log.w(TAG, "Unable to observe network changes", error)
        }
    }

    private fun unregisterNetworkCallback() {
        val callback = networkCallback ?: return
        networkCallback = null
        val manager = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE)
            as? ConnectivityManager ?: return
        try {
            manager.unregisterNetworkCallback(callback)
        } catch (_: RuntimeException) {
        }
    }

    // Runs on the connectivity thread.
    private fun updateNetwork(available: Boolean, replaced: Boolean) {
        val previous = networkAvailable
        networkAvailable = available
        if (available && (previous != true || replaced)) {
            // Sockets of a replaced network can hang until they time out; reconnect at once.
            engineHandler.post { httpSource?.retryNow(reconnect = previous == true) }
        }
        if (previous == available) return
        val event = mapOf("event" to "network", "available" to available)
        mainHandler.post { eventSink?.success(event) }
        engineHandler.post { tracePlayback(if (available) "network_available" else "network_lost", emptyMap()) }
    }

    private fun createNetworkStream(
        format: String,
        request: String,
        flags: Int,
        requestToken: Any,
        generation: Int,
    ): Int = when (format) {
        "flac" -> networkWithFallback(request, flags, requestToken, generation) {
            BASSFLAC.BASS_FLAC_StreamCreateURL(request, 0, flags, null, requestToken)
        }
        "ape" -> networkWithFallback(request, flags, requestToken, generation) {
            BASSAPE.BASS_APE_StreamCreateURL(request, 0, flags, null, requestToken)
        }
        "alac" -> networkWithFallback(request, flags, requestToken, generation) {
            BASSALAC.BASS_ALAC_StreamCreateURL(request, 0, flags, null, requestToken)
        }
        "m4a" -> {
            val generic = BASS.BASS_StreamCreateURL(request, 0, flags, null, requestToken)
            if (generic != 0 || generation != loadGeneration.get()) {
                generic
            } else {
                BASSALAC.BASS_ALAC_StreamCreateURL(request, 0, flags, null, requestToken)
            }
        }
        "lossless" -> {
            val generic = BASS.BASS_StreamCreateURL(request, 0, flags, null, requestToken)
            if (generic != 0 || generation != loadGeneration.get()) {
                generic
            } else {
                BASSFLAC.BASS_FLAC_StreamCreateURL(request, 0, flags, null, requestToken)
            }
        }
        else -> BASS.BASS_StreamCreateURL(request, 0, flags, null, requestToken)
    }

    private inline fun networkWithFallback(
        request: String,
        flags: Int,
        requestToken: Any,
        generation: Int,
        specialized: () -> Int,
    ): Int {
        val specializedHandle = specialized()
        // Cancellation also covers decoder fallback: do not start another
        // network connection after stop() or a newer load revoked this one.
        return if (specializedHandle != 0 || generation != loadGeneration.get()) {
            specializedHandle
        } else {
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

    private enum class OutputBackend(val initFlags: Int) {
        AUDIO_TRACK(BASS.BASS_DEVICE_AUDIOTRACK),
        // BASS defaults to AAudio on Android 8.1+, or OpenSL ES on older devices.
        AAUDIO(0),
    }

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
        val OUTPUT_BACKEND = OutputBackend.AUDIO_TRACK
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

        const val STREAM_CACHE_DIRECTORY = "bass-stream"
        const val SOURCE_OPEN_TIMEOUT_MS = 8_000L
        const val STREAM_CREATE_BUDGET_MS = 10_000L
        const val SEEK_PROBE_BYTES = 64L * 1024
        const val SEEK_ATTEMPT_BUDGET_MS = 2_000L
        const val START_BUFFER_SECONDS = 2.0
        const val RESUME_BUFFER_SECONDS = 5.0
        const val MIN_BUFFER_BYTES = 32L * 1024
        const val MAX_BUFFER_BYTES = 8L * 1024 * 1024
        const val FALLBACK_BYTES_PER_SECOND = 40_000.0
        const val TRUNCATED_END_TOLERANCE_MS = 5_000L
        const val GENERIC_DECODER = 0
        const val FLAC_DECODER = 1
        const val APE_DECODER = 2
        const val ALAC_DECODER = 3
        val LEGACY_STREAM_EXTENSIONS = setOf("m4a", "m4b", "mp4", "aac", "3gp", "ac3", "ec3", "eac3")

        const val STATE_IDLE = "idle"
        const val STATE_LOADING = "loading"
        const val STATE_BUFFERING = "buffering"
        const val STATE_READY = "ready"
        const val STATE_COMPLETED = "completed"
        const val STATE_ERROR = "error"
        const val TAG = "CyShineBass"
    }
}
