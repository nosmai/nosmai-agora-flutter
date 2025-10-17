package com.nosmai.nosmai_flutter

import androidx.annotation.Keep
import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.util.Base64
import android.graphics.Color
import android.util.Log
import android.view.Surface
import android.view.ViewGroup
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry
import android.os.Handler
import android.os.Looper
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import android.content.ContentValues
import android.provider.MediaStore
import android.os.Build
import android.os.Environment
import java.io.IOException
import android.media.MediaRecorder
import android.media.MediaMuxer
import android.media.MediaFormat
import android.media.MediaCodec
import android.media.MediaExtractor

import com.nosmai.effect.api.NosmaiSDK
import com.nosmai.effect.api.NosmaiBeauty
import com.nosmai.effect.NosmaiEffects
import com.nosmai.effect.api.NosmaiPreviewView
import com.nosmai.effect.api.NosmaiCloud

@Keep
class NosmaiFlutterPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var textures: TextureRegistry
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingLicenseKey: String? = null
    private var isSdkInitialized = false

    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null
    private var pendingSurfaceWidth: Int? = null
    private var pendingSurfaceHeight: Int? = null
    private var isSurfaceReady: Boolean = false
    private var pendingStartProcessing: Boolean = false

    private var previewView: NosmaiPreviewView? = null
    private var platformContainer: android.widget.FrameLayout? = null
    private var switchOverlayView: android.view.View? = null
    private var camera2Helper: Camera2Helper? = null
    private val REQ_CAMERA = 2001
    private var surfaceReboundOnce = false
    private var fpsCount = 0
    private var fpsLastMs = 0L
    private var cleanupInProgress: Boolean = false
    private var lastCleanupAtMs: Long = 0L
    private var usingPlatformView: Boolean = false
    private val mainHandler = Handler(Looper.getMainLooper())

    private fun runOnMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else mainHandler.post(block)
    }

    companion object {
        private const val TAG = "NosmaiFlutterPlugin"
        private const val CHANNEL = "nosmai_camera_sdk"
        private const val ASSET_MANIFEST_PATH = "flutter_assets/AssetManifest.json"
        private const val FILTERS_PREFIX = "assets/filters/"
        private const val CACHE_DIR_NAME = "NosmaiLocalFilters"
    }

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        textures = flutterPluginBinding.textureRegistry
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)

        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            "nosmai_camera_preview",
            object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                override fun create(context: Context?, viewId: Int, args: Any?): PlatformView {
                    val ctx = context ?: this@NosmaiFlutterPlugin.context
                    val container = android.widget.FrameLayout(ctx)
                    val pv = NosmaiPreviewView(ctx)
                    container.addView(
                        pv,
                        android.widget.FrameLayout.LayoutParams(
                            android.widget.FrameLayout.LayoutParams.MATCH_PARENT,
                            android.widget.FrameLayout.LayoutParams.MATCH_PARENT
                        )
                    )
                    // Add a black overlay for smooth crossfade during camera switch
                    val overlay = android.view.View(ctx)
                    overlay.setBackgroundColor(Color.BLACK)
                    overlay.alpha = 0f
                    overlay.visibility = android.view.View.GONE
                    container.addView(
                        overlay,
                        android.widget.FrameLayout.LayoutParams(
                            android.widget.FrameLayout.LayoutParams.MATCH_PARENT,
                            android.widget.FrameLayout.LayoutParams.MATCH_PARENT
                        )
                    )
                    previewView = pv
                    platformContainer = container
                    switchOverlayView = overlay
                    usingPlatformView = true
                    // Ensure GL pipeline is initialized for the new PreviewView
                    try {
                        previewView?.initializePipeline()
                    } catch (_: Throwable) {}
                    try { attemptDeferredStart() } catch (_: Throwable) {}
                    return object : PlatformView {
                        override fun getView(): android.view.View = container
                        override fun dispose() {
                            try { container.removeAllViews() } catch (_: Throwable) {}
                            usingPlatformView = false
                            platformContainer = null
                            switchOverlayView = null
                        }
                    }
                }
            }
        )
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        try { surface?.release() } catch (_: Throwable) {}
        surface = null
        isSurfaceReady = false
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android")
            "getLocalFilters" -> handleGetLocalFilters(result)
            "applyEffect" -> handleApplyEffect(call, result)
            "initWithLicense" -> handleInitWithLicense(call, result)
            "createTexture", "createPreviewTexture" -> handleCreateTexture(result)
            "setRenderSurface" -> handleSetRenderSurface(call, result)
            "clearRenderSurface" -> handleClearRenderSurface(result)
            "configureCamera" -> handleConfigureCamera(call, result)
            "startProcessing" -> handleStartProcessing(result)
            "stopProcessing" -> handleStopProcessing(result)
            "switchCamera" -> handleSwitchCamera(result)
            "detachCameraView" -> handleDetachCameraView(result)
            "removeAllFilters" -> handleRemoveAllFilters(result)
            "startRecording" -> handleStartRecording(result)
            "stopRecording" -> handleStopRecording(result)
            "isRecording" -> result.success(isRecording)
            "getCurrentRecordingDuration" -> result.success(getCurrentRecordingDurationSeconds())
            "applySkinSmoothing" -> handleApplySkinSmoothing(call, result)
            "applySkinWhitening" -> handleApplySkinWhitening(call, result)
            "applyFaceSlimming" -> handleApplyFaceSlimming(call, result)
            "applyEyeEnlargement" -> handleApplyEyeEnlargement(call, result)
            "applyNoseSize" -> handleApplyNoseSize(call, result)
            "applyBrightnessFilter" -> handleApplyBrightness(call, result)
            "applyContrastFilter" -> handleApplyContrast(call, result)
            "applyHue" -> handleApplyHue(call, result)
            "applyRGBFilter" -> handleApplyRGBFilter(call, result)
            "applyLipstick" -> handleApplyLipstick(call, result)
            "applyBlusher" -> handleApplyBlusher(call, result)
            "applyMakeupBlendLevel" -> handleApplyMakeupBlendLevel(call, result)
            "removeBuiltInFilters" -> handleRemoveBuiltInBeautyFilters(result)
            "isCloudFilterEnabled" -> handleIsCloudFilterEnabled(result)
            "getCloudFilters" -> handleGetCloudFilters(result)
            "downloadCloudFilter" -> handleDownloadCloudFilter(call, result)
            "getFilters" -> handleGetFilters(result)
            "capturePhoto" -> handleCapturePhoto(result)
            "saveImageToGallery" -> handleSaveImageToGallery(call, result)
            "saveVideoToGallery" -> handleSaveVideoToGallery(call, result)
            "cleanup" -> handleCleanup(result)
            "clearFilterCache" -> handleClearFilterCache(result)
            "reinitializePreview" -> handleReinitializePreview(result)
            else -> result.notImplemented()
        }
    }

    // --- Local Filters ---
    private fun handleGetLocalFilters(result: Result) {
        try {
            val manifestJson = readAssetText(ASSET_MANIFEST_PATH)
            if (manifestJson == null) {
                result.success(emptyList<Any>())
                return
            }

            val manifest = JSONObject(manifestJson)
            val keys = manifest.keys()
            val out = ArrayList<Map<String, Any?>>()

            while (keys.hasNext()) {
                val assetPath = keys.next()
                if (!assetPath.startsWith(FILTERS_PREFIX) || !assetPath.endsWith(".nosmai")) continue

                val name = File(assetPath).nameWithoutExtension
                val displayName = toTitleCase(name)

                val cachedFile = ensureAssetCached(assetPath)
                val fileSize = if (cachedFile != null && cachedFile.exists()) cachedFile.length().toInt() else 0

                val (ftype, disp, desc, hasPreview) = extractManifestFieldsFromNosmai(name)

                val map = HashMap<String, Any?>()
                map["id"] = name
                map["name"] = name
                map["displayName"] = if (!disp.isNullOrBlank()) disp else displayName
                map["description"] = desc ?: ""
                map["path"] = cachedFile?.absolutePath ?: ""
                map["fileSize"] = fileSize
                map["type"] = "local"
                if (ftype == "filter" || ftype == "effect") map["filterType"] = ftype
                map["isDownloaded"] = true
                map["isFree"] = true

                val previewB64 = tryExtractPreviewBase64(name)
                if (!previewB64.isNullOrBlank()) {
                    map["previewImageBase64"] = previewB64
                    map["previewUrl"] = "data:image/jpeg;base64,$previewB64"
                }

                out.add(map)
            }

            result.success(out)
        } catch (t: Throwable) {
            Log.e(TAG, "getLocalFilters error", t)
            result.error("FILTER_LOAD_ERROR", t.message, null)
        }
    }

    // --- Apply Effect (.nosmai) ---
    private fun handleApplyEffect(call: MethodCall, result: Result) {
        val effectPathArg = call.argument<String>("effectPath")
        if (effectPathArg.isNullOrBlank()) {
            result.success(false)
            return
        }

        try {
            val file = resolveEffectToFile(effectPathArg)
            if (file == null || !file.exists()) {
                Log.w(TAG, "Effect file not found for: $effectPathArg")
                result.success(false)
                return
            }

            NosmaiEffects.applyEffect(file.absolutePath)
            result.success(true)
        } catch (t: Throwable) {
            Log.e(TAG, "applyEffect error", t)
            result.success(false)
        }
    }

    // --- Initialization ---
    private fun handleInitWithLicense(call: MethodCall, result: Result) {
        try {
            val key = call.argument<String>("licenseKey").orEmpty()
            val act = activity
            if (act == null) {
                pendingLicenseKey = key
                result.success(true)
                return
            }
            initializeSdk(act, key)
            result.success(true)
        } catch (t: Throwable) {
            Log.e(TAG, "initWithLicense error", t)
            result.success(false)
        }
    }

    private fun initializeSdk(act: Activity, key: String) {
        if (isSdkInitialized) return
        NosmaiSDK.initialize(act, key)
        if (previewView == null) previewView = NosmaiPreviewView(act)
        val root = act.findViewById<ViewGroup>(android.R.id.content)
        if (previewView?.parent == null) {
            val lp = ViewGroup.LayoutParams(1, 1)
            root.addView(previewView, lp)
            previewView?.alpha = 0f
        }
                    try {
                        if (!isSwitchingCamera && pendingMirrorForNextFrame == null) {
                            NosmaiSDK.setMirrorX(isFrontCamera)
                        } else {
                            pendingMirrorForNextFrame = isFrontCamera
                        }
                    } catch (_: Throwable) {}
        
        try {
            previewView?.initializePipeline()
            Log.i(TAG, "✅ Pipeline initialized - GLView set for beauty filters")
        } catch (e: Throwable) {
            Log.w(TAG, "⚠️ Pipeline initialization warning: ${e.message}")
        }
        
        isSdkInitialized = true
        
        
        try {
            val w = pendingSurfaceWidth
            val h = pendingSurfaceHeight
            if (surface != null && w != null && h != null) {
                NosmaiSDK.setRenderSurface(surface!!, w, h)
                if (!isSwitchingCamera && pendingMirrorForNextFrame == null) {
                    NosmaiSDK.setMirrorX(isFrontCamera)
                } else {
                    pendingMirrorForNextFrame = isFrontCamera
                }
                pendingSurfaceWidth = null
                pendingSurfaceHeight = null
                isSurfaceReady = true
                if (pendingStartProcessing && !isProcessingActive && previewView != null) {
                    try {
                        NosmaiSDK.startProcessing(previewView!!)
                        isProcessingActive = true
                        ensureCameraPermissionThenStart()
                    } catch (_: Throwable) {}
                    pendingStartProcessing = false
                }
            }
        } catch (_: Throwable) {}
    }
    

    private fun handleCreateTexture(result: Result) {
        try {
            textureEntry = textures.createSurfaceTexture()
            surfaceReboundOnce = false
            isSurfaceReady = false
            result.success(textureEntry!!.id().toInt())
        } catch (t: Throwable) {
            Log.e(TAG, "createTexture error", t)
            result.error("TEXTURE_ERROR", t.message, null)
        }
    }

    private fun handleSetRenderSurface(call: MethodCall, result: Result) {
        try {
            val texId = call.argument<Number>("textureId")?.toInt()
            val w = call.argument<Number>("width")?.toInt() ?: 720
            val h = call.argument<Number>("height")?.toInt() ?: 1280
            if (texId == null) {
                result.error("ARG_ERROR", "textureId required", null)
                return
            }
            val entry = textureEntry
            if (entry == null) {
                result.success(false)
                return
            }
            val st = entry.surfaceTexture()
            st.setDefaultBufferSize(w, h)
            surface = Surface(st)
            
            if (isSdkInitialized) {
                NosmaiSDK.setRenderSurface(surface!!, w, h)
                try {
                    if (!isSwitchingCamera && pendingMirrorForNextFrame == null) {
                        NosmaiSDK.setMirrorX(isFrontCamera)
                    } else {
                        pendingMirrorForNextFrame = isFrontCamera
                    }
                } catch (_: Throwable) {}
                isSurfaceReady = true
                if (pendingStartProcessing && !isProcessingActive) {
                    try {
                        previewView?.let {
                            NosmaiSDK.startProcessing(it)
                            isProcessingActive = true
                            ensureCameraPermissionThenStart()
                        }
                    } catch (e: Throwable) { Log.e(TAG, "deferred startProcessing error", e) }
                    pendingStartProcessing = false
                }
                result.success(true)
            } else {
                pendingSurfaceWidth = w
                pendingSurfaceHeight = h
                isSurfaceReady = true
                result.success(true)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "setRenderSurface error", t)
            result.success(false)
        }
    }

    // --- Camera / Processing ---
    private var isFrontCamera: Boolean = true
    private var isSwitchingCamera: Boolean = false
    private var lastSwitchAtMs: Long = 0L
    private var isProcessingActive: Boolean = false
    private var suppressPreviewUntilMirrored: Boolean = false
    private var pendingMirrorForNextFrame: Boolean? = null

    private fun handleConfigureCamera(call: MethodCall, result: Result) {
        try {
            val pos = call.argument<String>("position") ?: "front"
            isFrontCamera = (pos == "front")
            Log.d(TAG, "ConfigureCamera: position=$pos, isFrontCamera=$isFrontCamera")
            try { NosmaiSDK.setCameraFacing(isFrontCamera) } catch (_: Throwable) {}
            try { NosmaiSDK.setMirrorX(isFrontCamera) } catch (_: Throwable) {}
            Log.d(TAG, "SetMirrorX called with: $isFrontCamera")
            result.success(null)
        } catch (t: Throwable) {
            Log.e(TAG, "configureCamera error", t)
            result.error("CONFIG_ERROR", t.message, null)
        }
    }

    private fun handleStartProcessing(result: Result) {
        try {
            val now = System.currentTimeMillis()
            if (cleanupInProgress || (now - lastCleanupAtMs) < 700) {
                pendingStartProcessing = true
                val delay = (700 - (now - lastCleanupAtMs)).coerceAtLeast(100)
                Handler(Looper.getMainLooper()).postDelayed({
                    try { attemptDeferredStart() } catch (_: Throwable) {}
                }, delay)
                result.success(null)
                return
            }
            val act = activity
            if (act != null && previewView == null) {
                previewView = NosmaiPreviewView(act)
                val root = act.findViewById<ViewGroup>(android.R.id.content)
                if (previewView?.parent == null) {
                    val lp = ViewGroup.LayoutParams(1, 1)
                    root.addView(previewView, lp)
                    previewView?.alpha = 0f
                }
                try { previewView?.initializePipeline() } catch (_: Throwable) {}
            }
            if (previewView == null) {
                result.error("NO_PREVIEW", "Preview not initialized", null)
                return
            }
            if (!usingPlatformView && (!isSurfaceReady || surface == null || !(surface?.isValid ?: false))) {
                pendingStartProcessing = true
                result.success(null)
                return
            }
            try { previewView?.initializePipeline() } catch (_: Throwable) {}
            NosmaiSDK.startProcessing(previewView!!)
            isProcessingActive = true
            try { NosmaiSDK.setCameraFacing(isFrontCamera) } catch (_: Throwable) {}
            try { NosmaiSDK.setMirrorX(isFrontCamera) } catch (_: Throwable) {}
            
            
            ensureCameraPermissionThenStart()
            try { previewView?.requestRenderUpdate() } catch (_: Throwable) {}
            result.success(null)
        } catch (t: Throwable) {
            Log.e(TAG, "startProcessing error", t)
            result.error("START_ERROR", t.message, null)
        }
    }

    private fun handleStopProcessing(result: Result) {
        try {
            cleanupInProgress = true
            lastCleanupAtMs = System.currentTimeMillis()
            try { camera2Helper?.stopCamera() } catch (_: Throwable) {}
            camera2Helper = null
            NosmaiSDK.stopProcessing()
            isProcessingActive = false
            result.success(null)
            Handler(Looper.getMainLooper()).postDelayed({ cleanupInProgress = false }, 400)
        } catch (t: Throwable) {
            Log.e(TAG, "stopProcessing error", t)
            result.error("STOP_ERROR", t.message, null)
        }
    }

    private fun handleDetachCameraView(result: Result) {
        try {
            try { camera2Helper?.cancelRetry() } catch (_: Throwable) {}
            try { camera2Helper?.stopCamera() } catch (_: Throwable) {}
            camera2Helper = null
            isProcessingActive = false
            pendingStartProcessing = false
            surfaceReboundOnce = false
            result.success(null)
        } catch (t: Throwable) {
            Log.e(TAG, "detachCameraView error", t)
            result.success(null)
        }
    }

    private fun handleSwitchCamera(result: Result) {
        try {
            val now = System.currentTimeMillis()
            if (isSwitchingCamera || (now - lastSwitchAtMs) < 700) {
                result.success(false)
                return
            }
            isSwitchingCamera = true
            suppressPreviewUntilMirrored = true
            runOnMain {
                try {
                    switchOverlayView?.let { ov ->
                        ov.clearAnimation()
                        ov.alpha = 0f
                        ov.visibility = android.view.View.VISIBLE
                        ov.animate().alpha(1f).setDuration(40).start()
                    }
                } catch (_: Throwable) {}
            }
            lastSwitchAtMs = now

            val act = activity
            if (act == null) {
                isSwitchingCamera = false
                result.error("NO_ACTIVITY", "Activity not available", null)
                return
            }

            act.runOnUiThread {
                try {
                    isFrontCamera = !isFrontCamera

                    try { camera2Helper?.stopCamera() } catch (_: Throwable) {}
                    camera2Helper = null

                    surfaceReboundOnce = false

                    try { 
                        NosmaiSDK.setCameraFacing(isFrontCamera)
                        pendingMirrorForNextFrame = isFrontCamera
                    } catch (_: Throwable) {}

                    Handler(Looper.getMainLooper()).postDelayed({
                        try {
                            // Reuse existing helper when possible for faster switch
                            val existing = camera2Helper
                            if (existing == null) {
                                camera2Helper = Camera2Helper(act, isFrontCamera)
                            } else {
                                try { existing.stopCamera() } catch (_: Throwable) {}
                                existing.setFacing(isFrontCamera)
                            }
                            ensureCameraPermissionThenStart()
                            try {
                                if (!isProcessingActive && previewView != null) {
                                    if (isSurfaceReady && surface != null && surface!!.isValid) {
                                        NosmaiSDK.startProcessing(previewView!!)
                                        isProcessingActive = true
                                    } else {
                                        pendingStartProcessing = true
                                    }
                                }
                            } catch (_: Throwable) {}
                            result.success(true)
                        } catch (e: Throwable) {
                            Log.e(TAG, "switchCamera delayed open error", e)
                            result.success(false)
                        } finally {
                            isSwitchingCamera = false
                        }
                    }, 120)
                } catch (t: Throwable) {
                    Log.e(TAG, "switchCamera error", t)
                    result.success(false)
                    isSwitchingCamera = false
                }
            }
        } catch (t: Throwable) {
            isSwitchingCamera = false
            Log.e(TAG, "switchCamera error", t)
            result.success(false)
        }
    }

    private fun handleRemoveAllFilters(result: Result) {
        try {
            NosmaiEffects.removeEffect()
            result.success(null)
        } catch (t: Throwable) {
            Log.e(TAG, "removeAllFilters error", t)
            result.error("REMOVE_FILTERS_ERROR", t.message, null)
        }
    }

    // --- Recording ---
    private var isRecording: Boolean = false
    private var recordingStartMs: Long = 0L
    private var recordingPath: String? = null
    private var audioRecorder: MediaRecorder? = null
    private var audioPath: String? = null
    private val REQ_AUDIO = 2002

    private fun handleStartRecording(result: Result) {
        try {
            val pv = previewView
            if (pv == null) {
                result.success(false)
                return
            }

            // Check audio permission
            val act = activity
            if (act != null && ContextCompat.checkSelfPermission(act, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(act, arrayOf(Manifest.permission.RECORD_AUDIO), REQ_AUDIO)
                result.success(false)
                return
            }

            val outDir = File(context.cacheDir, "NosmaiRecordings")
            if (!outDir.exists()) outDir.mkdirs()
            val timestamp = java.text.SimpleDateFormat("yyyyMMdd_HHmmss", java.util.Locale.US).format(java.util.Date())
            val videoFile = File(outDir, "nosmai_video_$timestamp.mp4")
            val audioFile = File(outDir, "nosmai_audio_$timestamp.m4a")
            audioPath = audioFile.absolutePath

            // Start audio recording with MediaRecorder
            try {
                audioRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    MediaRecorder(context)
                } else {
                    @Suppress("DEPRECATION")
                    MediaRecorder()
                }
                audioRecorder?.apply {
                    setAudioSource(MediaRecorder.AudioSource.MIC)
                    setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                    setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                    setAudioSamplingRate(44100)
                    setAudioEncodingBitRate(128000)
                    setOutputFile(audioFile.absolutePath)
                    prepare()
                    start()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start audio recording", e)
                audioRecorder = null
            }

            // Start video recording with NosmaiSDK
            NosmaiSDK.startRecording(pv, videoFile.absolutePath, object : com.nosmai.effect.api.NosmaiSDK.RecordingCallback {
                override fun onStarted(success: Boolean, error: String?) {
                    if (success) {
                        isRecording = true
                        recordingStartMs = System.currentTimeMillis()
                        recordingPath = videoFile.absolutePath
                        result.success(true)
                    } else {
                        // Stop audio recording if video fails
                        try {
                            audioRecorder?.stop()
                            audioRecorder?.release()
                            audioRecorder = null
                        } catch (_: Throwable) {}
                        result.success(false)
                    }
                }
            })
        } catch (t: Throwable) {
            Log.e(TAG, "startRecording error", t)
            result.success(false)
        }
    }

    private fun handleStopRecording(result: Result) {
        try {
            if (!isRecording) {
                result.success(mapOf(
                    "success" to false,
                    "duration" to 0.0,
                    "fileSize" to 0,
                    "error" to "Not currently recording"
                ))
                return
            }

            // Stop audio recording first
            val audioFilePath = audioPath
            try {
                audioRecorder?.stop()
                audioRecorder?.release()
                audioRecorder = null
            } catch (e: Exception) {
                Log.e(TAG, "Failed to stop audio recording", e)
            }

            val start = recordingStartMs
            val pathAtStop = recordingPath
            com.nosmai.effect.api.NosmaiSDK.stopRecording(object : com.nosmai.effect.api.NosmaiSDK.RecordingCallback {
                override fun onCompleted(outputPath: String?, success: Boolean, error: String?) {
                    isRecording = false
                    val videoPath = outputPath ?: pathAtStop
                    val durationSec = if (start > 0) ((System.currentTimeMillis() - start) / 1000.0) else 0.0

                    if (success && videoPath != null && audioFilePath != null && File(audioFilePath).exists()) {
                        // Merge audio and video
                        Thread {
                            try {
                                val outDir = File(context.cacheDir, "NosmaiRecordings")
                                val timestamp = java.text.SimpleDateFormat("yyyyMMdd_HHmmss", java.util.Locale.US).format(java.util.Date())
                                val mergedFile = File(outDir, "nosmai_final_$timestamp.mp4")

                                val merged = mergeAudioVideo(videoPath, audioFilePath, mergedFile.absolutePath)

                                if (merged) {
                                    // Delete temporary files
                                    try { File(videoPath).delete() } catch (_: Throwable) {}
                                    try { File(audioFilePath).delete() } catch (_: Throwable) {}

                                    val size = try { mergedFile.length().toInt() } catch (_: Throwable) { 0 }
                                    val map = mutableMapOf<String, Any?>(
                                        "success" to true,
                                        "duration" to durationSec,
                                        "fileSize" to size,
                                        "videoPath" to mergedFile.absolutePath
                                    )
                                    Handler(Looper.getMainLooper()).post { result.success(map) }
                                } else {
                                    // Return video without audio if merge fails
                                    val size = try { File(videoPath).length().toInt() } catch (_: Throwable) { 0 }
                                    val map = mutableMapOf<String, Any?>(
                                        "success" to true,
                                        "duration" to durationSec,
                                        "fileSize" to size,
                                        "videoPath" to videoPath
                                    )
                                    Handler(Looper.getMainLooper()).post { result.success(map) }
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Failed to merge audio/video", e)
                                // Return video without audio
                                val size = try { File(videoPath).length().toInt() } catch (_: Throwable) { 0 }
                                val map = mutableMapOf<String, Any?>(
                                    "success" to true,
                                    "duration" to durationSec,
                                    "fileSize" to size,
                                    "videoPath" to videoPath
                                )
                                Handler(Looper.getMainLooper()).post { result.success(map) }
                            }
                        }.start()
                    } else {
                        // No audio or recording failed
                        val size = try { if (videoPath != null) File(videoPath).length().toInt() else 0 } catch (_: Throwable) { 0 }
                        val map = mutableMapOf<String, Any?>(
                            "success" to success,
                            "duration" to durationSec,
                            "fileSize" to size
                        )
                        if (videoPath != null) map["videoPath"] = videoPath
                        if (!success && !error.isNullOrBlank()) map["error"] = error
                        result.success(map)
                    }
                }
            })
        } catch (t: Throwable) {
            Log.e(TAG, "stopRecording error", t)
            isRecording = false
            result.success(mapOf(
                "success" to false,
                "duration" to 0.0,
                "fileSize" to 0,
                "error" to (t.message ?: "Unknown error")
            ))
        }
    }

    private fun getCurrentRecordingDurationSeconds(): Double {
        return if (isRecording && recordingStartMs > 0) {
            (System.currentTimeMillis() - recordingStartMs) / 1000.0
        } else 0.0
    }

    private fun handleApplySkinSmoothing(call: MethodCall, result: Result) {
        Log.d("[FilterTest]", "Apply Smoothing")
        try {
            if (!isSdkInitialized) {
                result.error("FILTER_ERROR", "SDK not initialized. Call initWithLicense first.", null)
                return
            }
            
            val level = call.argument<Number>("level")?.toDouble() ?: 0.0
            val normalized = (level / 10.0).coerceIn(0.0, 1.0)
            
            NosmaiBeauty.applySkinSmoothing(normalized.toFloat())
            result.success(null)
        } catch (t: Throwable) { 
            Log.e(TAG, "SkinSmoothing error: ${t.message}", t)
            result.error("FILTER_ERROR", t.message, null) 
        }
    }

    private fun handleApplySkinWhitening(call: MethodCall, result: Result) {
        try {
            if (!isSdkInitialized) {
                result.error("FILTER_ERROR", "SDK not initialized.", null)
                return
            }
            
            val level = call.argument<Number>("level")?.toDouble() ?: 0.0
            val normalized = (level / 10.0).coerceIn(0.0, 1.0)
            NosmaiBeauty.applySkinWhitening(normalized.toFloat())
            result.success(null)
        } catch (t: Throwable) { 
            Log.e(TAG, "SkinWhitening error: ${t.message}", t)
            result.error("FILTER_ERROR", t.message, null) 
        }
    }

    private fun handleApplyFaceSlimming(call: MethodCall, result: Result) {
        try {
            if (!isSdkInitialized) {
                result.error("FILTER_ERROR", "SDK not initialized.", null)
                return
            }
            
            val level = call.argument<Number>("level")?.toDouble() ?: 0.0
            val normalized = (level / 10.0).coerceIn(0.0, 1.0)
            NosmaiBeauty.applyFaceSlimming(normalized.toFloat())
            result.success(null)
        } catch (t: Throwable) { 
            Log.e(TAG, "FaceSlimming error: ${t.message}", t)
            result.error("FILTER_ERROR", t.message, null) 
        }
    }

    private fun handleApplyEyeEnlargement(call: MethodCall, result: Result) {
        try {
            val level = call.argument<Number>("level")?.toDouble() ?: 0.0
            val normalized = (level / 10.0).coerceIn(0.0, 1.0)
            NosmaiBeauty.applyEyeEnlargement(normalized.toFloat())
            result.success(null)
        } catch (t: Throwable) { result.error("FILTER_ERROR", t.message, null) }
    }

    private fun handleApplyNoseSize(call: MethodCall, result: Result) {
        try {
            val level = call.argument<Number>("level")?.toDouble() ?: 0.0
            val normalized = (level / 100.0).coerceIn(0.0, 1.0)
            NosmaiBeauty.applyNoseSize(normalized.toFloat())
            result.success(null)
        } catch (t: Throwable) { result.error("FILTER_ERROR", t.message, null) }
    }

    private fun handleApplyBrightness(call: MethodCall, result: Result) {
        try {
            val brightness = call.argument<Number>("brightness")?.toDouble() ?: 0.0
            val clamped = brightness.coerceIn(-1.0, 1.0)
            NosmaiBeauty.applyBrightness(clamped.toFloat())
            result.success(null)
        } catch (t: Throwable) { result.error("FILTER_ERROR", t.message, null) }
    }

    private fun handleApplyContrast(call: MethodCall, result: Result) {
        try {
            val contrast = call.argument<Number>("contrast")?.toDouble() ?: 1.0
            val clamped = contrast.coerceIn(0.0, 2.0)
            NosmaiBeauty.applyContrast(clamped.toFloat())
            result.success(null)
        } catch (t: Throwable) { result.error("FILTER_ERROR", t.message, null) }
    }

    private fun handleApplyHue(call: MethodCall, result: Result) {
        try {
            val hue = call.argument<Number>("hueAngle")?.toDouble() ?: 0.0
            NosmaiBeauty.applyHue(hue.toFloat())
            result.success(null)
        } catch (t: Throwable) { result.error("FILTER_ERROR", t.message, null) }
    }

    private fun handleApplyRGBFilter(call: MethodCall, result: Result) {
        try {
            if (!isSdkInitialized) {
                result.error("FILTER_ERROR", "SDK not initialized.", null)
                return
            }
            
            val red = call.argument<Number>("red")?.toFloat() ?: 1.0f
            val green = call.argument<Number>("green")?.toFloat() ?: 1.0f
            val blue = call.argument<Number>("blue")?.toFloat() ?: 1.0f
            
            NosmaiBeauty.applyRGB(red, green, blue)
            Log.d(TAG, "Applied RGB filter: R=$red, G=$green, B=$blue")
            
            result.success(null)
        } catch (t: Throwable) {
            Log.e(TAG, "RGB filter error: ${t.message}", t)
            result.error("FILTER_ERROR", t.message, null)
        }
    }

    private fun handleApplyLipstick(call: MethodCall, result: Result) {
        try {
            if (!isSdkInitialized) {
                result.error("FILTER_ERROR", "SDK not initialized.", null)
                return
            }
            
            val intensity = call.argument<Number>("intensity")?.toDouble() ?: 0.0
            val normalized = (intensity / 100.0).coerceIn(0.0, 1.0)
            
            NosmaiBeauty.applyLipstick(normalized.toFloat())
            Log.d(TAG, "Applied lipstick: $normalized")
            
            result.success(null)
        } catch (t: Throwable) {
            Log.e(TAG, "Lipstick error: ${t.message}", t)
            result.error("FILTER_ERROR", t.message, null)
        }
    }

    private fun handleApplyBlusher(call: MethodCall, result: Result) {
        try {
            if (!isSdkInitialized) {
                result.error("FILTER_ERROR", "SDK not initialized.", null)
                return
            }
            
            val intensity = call.argument<Number>("intensity")?.toDouble() ?: 0.0
            val normalized = (intensity / 100.0).coerceIn(0.0, 1.0)
            
            NosmaiBeauty.applyBlusher(normalized.toFloat())
            Log.d(TAG, "Applied blusher: $normalized")
            
            result.success(null)
        } catch (t: Throwable) {
            Log.e(TAG, "Blusher error: ${t.message}", t)
            result.error("FILTER_ERROR", t.message, null)
        }
    }

    private fun handleApplyMakeupBlendLevel(call: MethodCall, result: Result) {
        try {
            if (!isSdkInitialized) {
                result.error("FILTER_ERROR", "SDK not initialized.", null)
                return
            }
            
            val filterName = call.argument<String>("filterName") ?: ""
            val level = call.argument<Number>("level")?.toDouble() ?: 0.0
            
            when (filterName.lowercase()) {
                "lipstickfilter", "lipstick" -> {
                    val normalized = (level / 100.0).coerceIn(0.0, 1.0)
                    NosmaiBeauty.applyLipstick(normalized.toFloat())
                    Log.d(TAG, "Applied lipstick: $normalized")
                }
                "blusherfilter", "blusher" -> {
                    val normalized = (level / 100.0).coerceIn(0.0, 1.0)
                    NosmaiBeauty.applyBlusher(normalized.toFloat())
                    Log.d(TAG, "Applied blusher: $normalized")
                }
                "skinsmoothing", "smoothing" -> {
                    val normalized = (level / 100.0).coerceIn(0.0, 1.0)
                    NosmaiBeauty.applySkinSmoothing(normalized.toFloat())
                    Log.d(TAG, "Applied skin smoothing: $normalized")
                }
                "skinwhitening", "whitening" -> {
                    val normalized = (level / 100.0).coerceIn(0.0, 1.0)
                    NosmaiBeauty.applySkinWhitening(normalized.toFloat())
                    Log.d(TAG, "Applied skin whitening: $normalized")
                }
                else -> {
                    Log.w(TAG, "Unknown makeup filter: $filterName")
                    result.error("FILTER_ERROR", "Unsupported makeup filter: $filterName", null)
                    return
                }
            }
            
            result.success(null)
        } catch (t: Throwable) {
            Log.e(TAG, "MakeupBlendLevel error: ${t.message}", t)
            result.error("FILTER_ERROR", t.message, null)
        }
    }

    private fun handleRemoveBuiltInBeautyFilters(result: Result) {
        try {
            NosmaiBeauty.removeAllBeautyFilters()
            result.success(null)
        } catch (t: Throwable) { result.error("FILTER_ERROR", t.message, null) }
    }

    private fun handleIsCloudFilterEnabled(result: Result) {
        try {
            result.success(NosmaiCloud.isEnabled())
        } catch (t: Throwable) { result.success(false) }
    }

    private fun mapCategoryToFilterType(cat: String?): String {
        val c = (cat ?: "").lowercase()
        return when (c) {
            "fx-and-filters", "filter" -> "filter"
            "special-effects", "beauty-effects", "effect" -> "effect"
            else -> "effect"
        }
    }

    private fun handleGetCloudFilters(result: Result) {
        try {
            val list = NosmaiCloud.list()
            val out = ArrayList<Map<String, Any?>>()
            for (it in list) {
                val id = it.id
                val name = it.name
                val displayName = toTitleCase(if (name.isNotBlank()) name else id)
                val type = "cloud"
                val downloaded = it.isDownloaded
                val localPath = it.localPath
                val filterType = mapCategoryToFilterType(it.category)
                val fileSize = try { if (downloaded && localPath.isNotBlank()) File(localPath).length().toInt() else 0 } catch (_: Throwable) { 0 }

                val m = HashMap<String, Any?>()
                m["id"] = id
                m["name"] = name
                m["displayName"] = displayName
                m["type"] = type
                m["filterType"] = filterType
                m["isDownloaded"] = downloaded
                m["fileSize"] = fileSize
                m["isFree"] = true
                
                if (downloaded && localPath.isNotBlank()) {
                    m["path"] = localPath
                    m["localPath"] = localPath
                    try {
                        val bmp = com.nosmai.effect.NosmaiFilterManager.loadPreviewImageForFilter(localPath)
                        if (bmp != null) {
                            m["previewImageBase64"] = bitmapToBase64(bmp)
                        }
                    } catch (_: Throwable) {}
                }
                
                if (it.thumbnailUrl.isNotBlank()) {
                    m["previewUrl"] = it.thumbnailUrl  
                    m["thumbnailUrl"] = it.thumbnailUrl
                }
                
                out.add(m)
            }
            result.success(out)
        } catch (t: Throwable) {
            result.error("CLOUD_FILTERS_ERROR", t.message, null)
        }
    }

    private fun handleDownloadCloudFilter(call: MethodCall, result: Result) {
        val filterId = call.argument<String>("filterId")
        if (filterId.isNullOrBlank()) { result.error("ARG_ERROR", "filterId required", null); return }
        try {
            val latch = java.util.concurrent.CountDownLatch(1)
            var ok = false
            var path: String? = null
            var err: String? = null
            NosmaiCloud.download(filterId, object : NosmaiCloud.DownloadCallback {
                override fun onComplete(id: String, success: Boolean, localPath: String?, error: String?) {
                    ok = success
                    path = localPath
                    err = error
                    latch.countDown()
                }
            })
            latch.await()
            val map = HashMap<String, Any?>()
            map["success"] = ok
            if (ok && !path.isNullOrBlank()) map["path"] = path
            if (!ok && !err.isNullOrBlank()) map["error"] = err
            result.success(map)
        } catch (t: Throwable) {
            result.success(mapOf("success" to false, "error" to (t.message ?: "Unknown error")))
        }
    }

    private fun handleGetFilters(result: Result) {
        try {
            val grouped = com.nosmai.effect.NosmaiEffects.getFilters()
            val out = ArrayList<Map<String, Any?>>()
            if (grouped != null) {
                for (entry in grouped.entries) {
                    val list = entry.value as? List<*> ?: continue
                    for (item in list) {
                        val m = item as? Map<*, *> ?: continue
                        val name = (m["name"] as? String)?.trim().orEmpty()
                        if (name.isBlank()) continue
                        val id = ((m["filterId"] as? String)?.takeIf { it.isNotBlank() } ?: name)
                        val displayName = ((m["displayName"] as? String)?.takeIf { it.isNotBlank() } ?: toTitleCase(name))
                        val type = (m["type"] as? String)?.lowercase() ?: "local"
                        val path = ((m["localPath"] as? String)?.takeIf { it.isNotBlank() } ?: (m["path"] as? String)).orEmpty()
                        val fileSize = (m["fileSize"] as? Number)?.toInt() ?: 0
                        val filterType = (m["filterType"] as? String)?.lowercase() ?: mapCategoryToFilterType(m["category"] as? String)
                        val downloaded = (m["isDownloaded"] as? Boolean) ?: (type == "local")
                        val previewB64 = m["previewBase64"] as? String
                        val thumbUrl = m["thumbnailUrl"] as? String

                        val outMap = HashMap<String, Any?>()
                        outMap["id"] = id
                        outMap["name"] = name
                        outMap["displayName"] = displayName
                        outMap["type"] = type
                        outMap["filterType"] = filterType
                        outMap["isDownloaded"] = downloaded
                        outMap["fileSize"] = fileSize
                        if (path.isNotBlank()) outMap["path"] = path
                        
                        if (!previewB64.isNullOrBlank()) outMap["previewImageBase64"] = previewB64
                        
                        if (!thumbUrl.isNullOrBlank()) {
                            outMap["previewUrl"] = thumbUrl
                            outMap["thumbnailUrl"] = thumbUrl
                        }
                        
                        out.add(outMap)
                    }
                }
            }
            result.success(out)
        } catch (t: Throwable) { result.error("GET_FILTERS_ERROR", t.message, null) }
    }

    private fun handleClearRenderSurface(result: Result) {
        try {
            try { NosmaiSDK.clearRenderSurface() } catch (_: Throwable) {}
            
            surface?.release()
            surface = null
            
            surfaceReboundOnce = false
            isSurfaceReady = false
            pendingStartProcessing = false
            cleanupInProgress = true
            lastCleanupAtMs = System.currentTimeMillis()
            Handler(Looper.getMainLooper()).postDelayed({ cleanupInProgress = false }, 700)
            
            result.success(true)
        } catch (t: Throwable) {
            Log.e(TAG, "clearRenderSurface error", t)
            result.success(false)
        }
    }

    // --- Photo Capture and Gallery Functions ---
    private fun handleCapturePhoto(result: Result) {
        try {
            if (usingPlatformView) {
                val pvLocal = previewView
                if (pvLocal == null) {
                    result.success(mapOf("success" to false, "error" to "Preview not ready")); return
                }
                val tv = findTextureView(pvLocal)
                if (tv != null) {
                    try {
                        val bmp = tv.bitmap
                        if (bmp != null) {
                            Thread {
                                try {
                                    val baos = ByteArrayOutputStream()
                                    bmp.compress(Bitmap.CompressFormat.JPEG, 85, baos)
                                    val data = baos.toByteArray()
                                    val map = hashMapOf<String, Any?>(
                                        "success" to true,
                                        "width" to bmp.width,
                                        "height" to bmp.height,
                                        "imageData" to data
                                    )
                                    Handler(Looper.getMainLooper()).post { result.success(map) }
                                } catch (e: Throwable) {
                                    Handler(Looper.getMainLooper()).post { result.success(mapOf("success" to false, "error" to e.message)) }
                                }
                            }.start()
                            return
                        }
                    } catch (e: Throwable) { Log.w(TAG, "TextureView capture failed", e) }
                }
                val sv = findSurfaceView(pvLocal)
                if (sv != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    try {
                        val w = if (sv.width > 0) sv.width else (pendingSurfaceWidth ?: 720)
                        val h = if (sv.height > 0) sv.height else (pendingSurfaceHeight ?: 1280)
                        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                        android.view.PixelCopy.request(sv, bmp, android.view.PixelCopy.OnPixelCopyFinishedListener { copyResult ->
                            if (copyResult == android.view.PixelCopy.SUCCESS) {
                                Thread {
                                    try {
                                        val baos = ByteArrayOutputStream()
                                        bmp.compress(Bitmap.CompressFormat.JPEG, 85, baos)
                                        val data = baos.toByteArray()
                                        val map = hashMapOf<String, Any?>(
                                            "success" to true,
                                            "width" to bmp.width,
                                            "height" to bmp.height,
                                            "imageData" to data
                                        )
                                        Handler(Looper.getMainLooper()).post { result.success(map) }
                                    } catch (e: Throwable) {
                                        Handler(Looper.getMainLooper()).post { result.success(mapOf("success" to false, "error" to e.message)) }
                                    }
                                }.start()
                            } else {
                                val fw = w; val fh = h
                                captureUsingOpenGL(fw, fh, result)
                            }
                        }, Handler(Looper.getMainLooper()))
                        return
                    } catch (e: Throwable) { Log.w(TAG, "SurfaceView PixelCopy failed", e) }
                }
                val w = pendingSurfaceWidth ?: pvLocal.width.takeIf { it > 0 } ?: 720
                val h = pendingSurfaceHeight ?: pvLocal.height.takeIf { it > 0 } ?: 1280
                captureUsingOpenGL(w, h, result)
                return
            }

            val surf = surface
            val entry = textureEntry
            if (surf == null || entry == null) {
                result.success(mapOf("success" to false, "error" to "Surface not initialized for capture"))
                return
            }
            val width = pendingSurfaceWidth ?: 720
            val height = pendingSurfaceHeight ?: 1280
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                try {
                    android.view.PixelCopy.request(surf, bitmap, { copyResult ->
                        if (copyResult == android.view.PixelCopy.SUCCESS) {
                            Thread {
                                try {
                                    val baos = ByteArrayOutputStream()
                                    bitmap.compress(Bitmap.CompressFormat.JPEG, 80, baos)
                                    val imageData = baos.toByteArray()
                                    val resultMap = HashMap<String, Any?>()
                                    resultMap["success"] = true
                                    resultMap["width"] = bitmap.width
                                    resultMap["height"] = bitmap.height
                                    resultMap["imageData"] = imageData
                                    Handler(Looper.getMainLooper()).post { result.success(resultMap) }
                                } catch (e: Throwable) {
                                    Handler(Looper.getMainLooper()).post { result.success(mapOf("success" to false, "error" to "Failed to process image: ${e.message}")) }
                                }
                            }.start()
                        } else {
                            captureUsingOpenGL(width, height, result)
                        }
                    }, Handler(Looper.getMainLooper()))
                } catch (e: Throwable) {
                    Log.e(TAG, "PixelCopy error", e)
                    captureUsingOpenGL(width, height, result)
                }
            } else {
                captureUsingOpenGL(width, height, result)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "capturePhoto error", t)
            result.success(mapOf(
                "success" to false,
                "error" to "Failed to capture photo: ${t.message}"
            ))
        }
    }
    
    private fun captureUsingOpenGL(width: Int, height: Int, result: Result) {
        try {
            val buffer = java.nio.ByteBuffer.allocateDirect(width * height * 4)
            buffer.order(java.nio.ByteOrder.nativeOrder())
            
            android.opengl.GLES20.glReadPixels(0, 0, width, height, 
                android.opengl.GLES20.GL_RGBA, 
                android.opengl.GLES20.GL_UNSIGNED_BYTE, 
                buffer)
            
            buffer.rewind()
            
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            bitmap.copyPixelsFromBuffer(buffer)
            
            val matrix = android.graphics.Matrix()
            matrix.postScale(1f, -1f, width / 2f, height / 2f)
            val flippedBitmap = Bitmap.createBitmap(bitmap, 0, 0, width, height, matrix, true)
            
            Thread {
                try {
                    val baos = ByteArrayOutputStream()
                    flippedBitmap.compress(Bitmap.CompressFormat.JPEG, 80, baos)
                    val imageData = baos.toByteArray()
                    
                    val resultMap = HashMap<String, Any?>()
                    resultMap["success"] = true
                    resultMap["width"] = flippedBitmap.width
                    resultMap["height"] = flippedBitmap.height
                    resultMap["imageData"] = imageData
                    
                    Handler(Looper.getMainLooper()).post {
                        result.success(resultMap)
                    }
                } catch (e: Throwable) {
                    Handler(Looper.getMainLooper()).post {
                        result.success(mapOf(
                            "success" to false,
                            "error" to "Failed to process captured image: ${e.message}"
                        ))
                    }
                }
            }.start()
        } catch (t: Throwable) {
            Log.e(TAG, "OpenGL capture error", t)
            result.success(mapOf(
                "success" to false,
                "error" to "Failed to capture using OpenGL: ${t.message}"
            ))
        }
    }

    private fun findTextureView(root: android.view.View): android.view.TextureView? {
        if (root is android.view.TextureView) return root
        if (root is android.view.ViewGroup) {
            for (i in 0 until root.childCount) {
                val child = root.getChildAt(i)
                val found = findTextureView(child)
                if (found != null) return found
            }
        }
        return null
    }

    private fun findSurfaceView(root: android.view.View): android.view.SurfaceView? {
        if (root is android.view.SurfaceView) return root
        if (root is android.view.ViewGroup) {
            for (i in 0 until root.childCount) {
                val child = root.getChildAt(i)
                val found = findSurfaceView(child)
                if (found != null) return found
            }
        }
        return null
    }

    private fun handleSaveImageToGallery(call: MethodCall, result: Result) {
        try {
            val imageData = call.argument<ByteArray>("imageData")
            val imageName = call.argument<String>("name") ?: "nosmai_photo_${System.currentTimeMillis()}"
            
            if (imageData == null) {
                result.error("INVALID_ARGUMENTS", "Image data is required", null)
                return
            }
            
            val bitmap = android.graphics.BitmapFactory.decodeByteArray(imageData, 0, imageData.size)
            if (bitmap == null) {
                result.error("INVALID_IMAGE", "Could not create image from data", null)
                return
            }
            
            val saved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                saveImageToGalleryQ(bitmap, imageName)
            } else {
                saveImageToGalleryLegacy(bitmap, imageName)
            }
            
            if (saved) {
                result.success(mapOf(
                    "isSuccess" to true,
                    "message" to "Image saved to gallery"
                ))
            } else {
                result.error("SAVE_FAILED", "Failed to save image to gallery", null)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "saveImageToGallery error", t)
            result.error("SAVE_ERROR", "Error saving image: ${t.message}", null)
        }
    }

    private fun handleSaveVideoToGallery(call: MethodCall, result: Result) {
        try {
            val videoPath = call.argument<String>("videoPath")
            val videoName = call.argument<String>("name") ?: "nosmai_video_${System.currentTimeMillis()}"
            
            if (videoPath == null) {
                result.error("INVALID_ARGUMENTS", "Video path is required", null)
                return
            }
            
            val videoFile = File(videoPath)
            if (!videoFile.exists()) {
                result.error("FILE_NOT_FOUND", "Video file not found", null)
                return
            }
            
            val saved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                saveVideoToGalleryQ(videoFile, videoName)
            } else {
                saveVideoToGalleryLegacy(videoFile, videoName)
            }
            
            if (saved) {
                result.success(mapOf(
                    "isSuccess" to true,
                    "message" to "Video saved to gallery"
                ))
            } else {
                result.error("SAVE_FAILED", "Failed to save video to gallery", null)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "saveVideoToGallery error", t)
            result.error("SAVE_ERROR", "Error saving video: ${t.message}", null)
        }
    }

    private fun saveImageToGalleryQ(bitmap: Bitmap, imageName: String): Boolean {
        val resolver = context.contentResolver
        val contentValues = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "$imageName.jpg")
            put(MediaStore.MediaColumns.MIME_TYPE, "image/jpeg")
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Nosmai")
        }
        
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, contentValues)
        return if (uri != null) {
            try {
                resolver.openOutputStream(uri)?.use { outputStream ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 90, outputStream)
                }
                true
            } catch (e: IOException) {
                Log.e(TAG, "Failed to save image", e)
                false
            }
        } else {
            false
        }
    }
    
    private fun saveImageToGalleryLegacy(bitmap: Bitmap, imageName: String): Boolean {
        val picturesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
        val nosmaiDir = File(picturesDir, "Nosmai")
        if (!nosmaiDir.exists()) {
            nosmaiDir.mkdirs()
        }
        
        val imageFile = File(nosmaiDir, "$imageName.jpg")
        return try {
            FileOutputStream(imageFile).use { outputStream ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 90, outputStream)
            }
            
            val mediaScanIntent = android.content.Intent(android.content.Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
            mediaScanIntent.data = android.net.Uri.fromFile(imageFile)
            context.sendBroadcast(mediaScanIntent)
            
            true
        } catch (e: IOException) {
            Log.e(TAG, "Failed to save image", e)
            false
        }
    }
    
    private fun saveVideoToGalleryQ(videoFile: File, videoName: String): Boolean {
        val resolver = context.contentResolver
        val contentValues = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "$videoName.mp4")
            put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/Nosmai")
        }
        
        val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, contentValues)
        return if (uri != null) {
            try {
                resolver.openOutputStream(uri)?.use { outputStream ->
                    videoFile.inputStream().use { inputStream ->
                        inputStream.copyTo(outputStream)
                    }
                }
                true
            } catch (e: IOException) {
                Log.e(TAG, "Failed to save video", e)
                false
            }
        } else {
            false
        }
    }
    
    private fun saveVideoToGalleryLegacy(videoFile: File, videoName: String): Boolean {
        val moviesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
        val nosmaiDir = File(moviesDir, "Nosmai")
        if (!nosmaiDir.exists()) {
            nosmaiDir.mkdirs()
        }
        
        val destFile = File(nosmaiDir, "$videoName.mp4")
        return try {
            videoFile.copyTo(destFile, overwrite = true)
            
            val mediaScanIntent = android.content.Intent(android.content.Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
            mediaScanIntent.data = android.net.Uri.fromFile(destFile)
            context.sendBroadcast(mediaScanIntent)
            
            true
        } catch (e: IOException) {
            Log.e(TAG, "Failed to save video", e)
            false
        }
    }

    // --- SDK Cleanup and Management ---
    private fun handleCleanup(result: Result) {
        try {
            if (isSdkInitialized) {
                try {
                    cleanupInProgress = true
                    lastCleanupAtMs = System.currentTimeMillis()
                    if (isProcessingActive) {
                        NosmaiSDK.stopProcessing()
                        isProcessingActive = false
                    }
                    
                    camera2Helper?.stopCamera()
                    camera2Helper = null
                    
                    NosmaiEffects.removeEffect()
                    NosmaiBeauty.removeAllBeautyFilters()
                    
                    NosmaiSDK.clearRenderSurface()
                    
                    surfaceReboundOnce = false
                    
                    if (isRecording) {
                        try {
                            com.nosmai.effect.api.NosmaiSDK.stopRecording(object : com.nosmai.effect.api.NosmaiSDK.RecordingCallback {
                                override fun onCompleted(outputPath: String?, success: Boolean, error: String?) {
                                }
                            })
                            isRecording = false
                        } catch (_: Throwable) {}
                    }
                } catch (e: Throwable) {
                    Log.w(TAG, "Cleanup warning", e)
                }
            }
            
            
            result.success(null)
            Handler(Looper.getMainLooper()).postDelayed({ cleanupInProgress = false }, 700)
        } catch (t: Throwable) {
            Log.e(TAG, "Cleanup error", t)
            result.error("CLEANUP_ERROR", t.message, null)
        }
    }

    private fun attemptDeferredStart() {
        if (!pendingStartProcessing || isProcessingActive || cleanupInProgress) return
        val pv = previewView ?: return
        // PlatformView does not depend on Texture/Surface readiness
        if (usingPlatformView) {
            try {
                try { pv.initializePipeline() } catch (_: Throwable) {}
                NosmaiSDK.startProcessing(pv)
                isProcessingActive = true
                // Ensure camera facing and mirror are correct after resume
                try { NosmaiSDK.setCameraFacing(isFrontCamera) } catch (_: Throwable) {}
                try { NosmaiSDK.setMirrorX(isFrontCamera) } catch (_: Throwable) {}
                ensureCameraPermissionThenStart()
                try { pv.requestRenderUpdate() } catch (_: Throwable) {}
            } catch (e: Throwable) {
                Log.e(TAG, "attemptDeferredStart (platformView) error", e)
            } finally {
                pendingStartProcessing = false
            }
            return
        }
        // Texture-based path requires a valid surface
        if (isSurfaceReady && surface?.isValid == true) {
            try {
                NosmaiSDK.startProcessing(pv)
                isProcessingActive = true
                ensureCameraPermissionThenStart()
            } catch (e: Throwable) {
                Log.e(TAG, "attemptDeferredStart (texture) error", e)
            } finally {
                pendingStartProcessing = false
            }
        }
    }
    
    private fun handleClearFilterCache(result: Result) {
        try {
            clearFilterCache()
            result.success(null)
        } catch (t: Throwable) {
            Log.e(TAG, "Clear filter cache error", t)
            result.error("CLEAR_CACHE_ERROR", t.message, null)
        }
    }
    
    private fun clearFilterCache() {
        try {
            val cacheDir = File(context.cacheDir, CACHE_DIR_NAME)
            if (cacheDir.exists() && cacheDir.isDirectory) {
                cacheDir.listFiles()?.forEach { file ->
                    if (file.name.endsWith(".nosmai")) {
                        file.delete()
                    }
                }
            }
            
            val cloudCacheDir = File(context.filesDir, "cloud_filters")
            if (cloudCacheDir.exists() && cloudCacheDir.isDirectory) {
                cloudCacheDir.listFiles()?.forEach { file ->
                    file.delete()
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to clear filter cache", e)
        }
    }
    
    private fun handleReinitializePreview(result: Result) {
        try {
            // For PlatformView preview, simply ensure processing is active again
            if (usingPlatformView) {
                try {
                    val pv = previewView
                    // Rebuild preview view to recover from GL/surface loss on BG/FG
                    runOnMain {
                        try {
                            val container = platformContainer
                            if (container != null) {
                                try {
                                    // Remove old previewView only (keep overlay if present)
                                    previewView?.let { old -> container.removeView(old) }
                                } catch (_: Throwable) {}
                                // Create and insert a fresh preview view at bottom
                                val ctx = container.context
                                val newPv = NosmaiPreviewView(ctx)
                                previewView = newPv
                                container.addView(
                                    newPv,
                                    0,
                                    android.widget.FrameLayout.LayoutParams(
                                        android.widget.FrameLayout.LayoutParams.MATCH_PARENT,
                                        android.widget.FrameLayout.LayoutParams.MATCH_PARENT
                                    )
                                )
                                try { newPv.initializePipeline() } catch (_: Throwable) {}
                            }
                        } catch (_: Throwable) {}
                    }

                    if (!cleanupInProgress) {
                        val latest = previewView
                        if (latest != null) {
                            if (!isProcessingActive) {
                                NosmaiSDK.startProcessing(latest)
                                isProcessingActive = true
                            }
                            // Re-assert camera facing and mirror after GL rebuild
                            try { NosmaiSDK.setCameraFacing(isFrontCamera) } catch (_: Throwable) {}
                            try { NosmaiSDK.setMirrorX(isFrontCamera) } catch (_: Throwable) {}
                            ensureCameraPermissionThenStart()
                            try { latest.requestRenderUpdate() } catch (_: Throwable) {}
                        }
                    } else {
                        // Defer start until cleanup window passes
                        pendingStartProcessing = true
                        Handler(Looper.getMainLooper()).postDelayed({
                            try { attemptDeferredStart() } catch (_: Throwable) {}
                        }, 350)
                    }
                } catch (_: Throwable) {}
                result.success(null)
                return
            }

            if (textureEntry == null || surface == null) {
                result.success(null)
                return
            }
            
            try {
                NosmaiSDK.clearRenderSurface()
            } catch (_: Throwable) {}
            
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    val entry = textureEntry
                    val surf = surface
                    if (entry != null && surf != null && !surf.isValid) {
                        val st = entry.surfaceTexture()
                        val w = pendingSurfaceWidth ?: 720
                        val h = pendingSurfaceHeight ?: 1280
                        st.setDefaultBufferSize(w, h)
                        surface = Surface(st)
                    }
                    
                    surface?.let { s ->
                        if (s.isValid) {
                            val w = pendingSurfaceWidth ?: 720
                            val h = pendingSurfaceHeight ?: 1280
                            NosmaiSDK.setRenderSurface(s, w, h)
                            if (!isSwitchingCamera && pendingMirrorForNextFrame == null) {
                                NosmaiSDK.setMirrorX(isFrontCamera)
                            } else {
                                pendingMirrorForNextFrame = isFrontCamera
                            }
                            surfaceReboundOnce = false
                            isSurfaceReady = true
                            if (pendingStartProcessing && !isProcessingActive && previewView != null) {
                                try {
                                    NosmaiSDK.startProcessing(previewView!!)
                                    isProcessingActive = true
                                    ensureCameraPermissionThenStart()
                                } catch (_: Throwable) {}
                                pendingStartProcessing = false
                            }
                        }
                    }
                    result.success(null)
                } catch (e: Throwable) {
                    Log.e(TAG, "Failed to reinitialize preview", e)
                    result.success(null)
                }
            }, 100)
        } catch (t: Throwable) {
            Log.e(TAG, "Reinitialize preview error", t)
            result.success(null)
        }
    }

    // --- Helpers ---
    private fun readAssetText(assetPath: String): String? {
        return try {
            context.assets.open(assetPath).use { ins ->
                ins.bufferedReader(Charsets.UTF_8).readText()
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun ensureAssetCached(assetPath: String): File? {
        return try {
            val cacheDir = File(context.cacheDir, CACHE_DIR_NAME)
            if (!cacheDir.exists()) cacheDir.mkdirs()

            val fileName = File(assetPath).name
            val outFile = File(cacheDir, fileName)

            if (!outFile.exists() || outFile.length() == 0L) {
                openAnyAsset(assetPath).use { ins ->
                    FileOutputStream(outFile).use { fos ->
                        ins.copyTo(fos)
                    }
                }
            }
            outFile
        } catch (e: Exception) {
            Log.w(TAG, "Failed to cache asset: $assetPath", e)
            null
        }
    }

    private fun openAnyAsset(assetPath: String): InputStream {
        return try {
            context.assets.open(assetPath)
        } catch (_: Exception) {
            val candidate = if (assetPath.startsWith("flutter_assets/")) assetPath else "flutter_assets/$assetPath"
            context.assets.open(candidate)
        }
    }

    private fun toTitleCase(name: String): String {
        val cleaned = name.replace('_', ' ').replace('-', ' ')
        return cleaned.split(" ")
            .filter { it.isNotBlank() }
            .joinToString(" ") { it.replaceFirstChar { c -> c.titlecase() } }
    }

    private fun extractManifestFieldsFromNosmai(filterName: String): Quad<String?, String?, String?, Boolean> {
        val candidates = listOf(
            "flutter_assets/assets/filters/$filterName.nosmai",
            "assets/filters/$filterName.nosmai",
            "filters/$filterName.nosmai"
        )
        var ftype: String? = null
        var display: String? = null
        var desc: String? = null
        var hasPrev = false
        for (p in candidates) {
            try {
                val cls = Class.forName("com.nosmai.effect.internal.NosmaiFilter")
                val m = cls.getMethod("nativeExtractManifestFromAssets", Context::class.java, String::class.java)
                val jsonStr = m.invoke(null, context, p) as? String
                if (!jsonStr.isNullOrBlank()) {
                    val json = JSONObject(jsonStr)
                    val t = (json.optString("filterType", json.optString("type", ""))).lowercase()
                    if (t == "filter" || t == "effect") ftype = t
                    display = json.optString("displayName", display)
                    desc = json.optString("description", desc)
                    if (json.has("preview")) hasPrev = true
                    break
                }
            } catch (_: Throwable) { }
        }
        return Quad(ftype, display, desc, hasPrev)
    }

    private fun tryExtractPreviewBase64(filterName: String): String? {
        val candidates = listOf(
            "flutter_assets/assets/filters/$filterName.nosmai",
            "assets/filters/$filterName.nosmai",
            "filters/$filterName.nosmai"
        )
        for (p in candidates) {
            try {
                val cls = Class.forName("com.nosmai.effect.internal.NosmaiFilter")
                val m = cls.getMethod("nativeExtractPreviewFromAssets", Context::class.java, String::class.java)
                val bmp = m.invoke(null, context, p) as? Bitmap
                if (bmp != null) {
                    return bitmapToBase64(bmp)
                }
            } catch (_: Throwable) { }
        }
        return null
    }

    data class Quad<A, B, C, D>(val first: A, val second: B, val third: C, val fourth: D)

    private fun tryLoadPreviewBase64(file: File?): String? {
        if (file == null || !file.exists()) return null
        return try {
            null
        } catch (_: Throwable) { null }
    }

    private fun tryGetFilterType(file: File?): String? {
        return null
    }

    private fun bitmapToBase64(bmp: Bitmap): String {
        val baos = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, 70, baos)
        val data = baos.toByteArray()
        return Base64.encodeToString(data, Base64.NO_WRAP)
    }

    private fun resolveEffectToFile(effectPathArg: String): File? {
        val arg = effectPathArg.trim()

        val direct = File(arg)
        if (direct.exists()) return direct

        val assetCandidates = mutableListOf<String>()
        if (arg.startsWith(FILTERS_PREFIX)) {
            assetCandidates.add("flutter_assets/$arg")
            assetCandidates.add(arg) 
        } else if (arg.startsWith("filters/")) {
            assetCandidates.add("flutter_assets/$arg")
            assetCandidates.add(arg)
        } else {
            val name = if (arg.endsWith(".nosmai")) arg.substringBeforeLast(".nosmai") else arg
            assetCandidates.add("flutter_assets/${FILTERS_PREFIX}${name}.nosmai")
            assetCandidates.add("${FILTERS_PREFIX}${name}.nosmai")
            assetCandidates.add("flutter_assets/filters/${name}.nosmai")
            assetCandidates.add("filters/${name}.nosmai")
        }

        for (asset in assetCandidates) {
            try {
                context.assets.open(asset).use { _ ->
                    val cached = ensureAssetCached(asset)
                    if (cached != null && cached.exists()) return cached
                }
            } catch (_: Exception) {
            }
        }

        val manifestJson = readAssetText(ASSET_MANIFEST_PATH)
        if (manifestJson != null) {
            val manifest = JSONObject(manifestJson)
            val keys = manifest.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                if (key.startsWith(FILTERS_PREFIX) && key.endsWith(".nosmai")) {
                    val name = File(key).nameWithoutExtension
                    if (name.equals(arg, ignoreCase = true)) {
                        val cached = ensureAssetCached("flutter_assets/$key") ?: ensureAssetCached(key)
                        if (cached != null && cached.exists()) return cached
                    }
                }
            }
        }

        return null
    }

    // ActivityAware
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        activityBinding?.addRequestPermissionsResultListener(this)
        // If init was requested before activity was available, complete it now
        val key = pendingLicenseKey
        if (key != null && !isSdkInitialized) {
            try { initializeSdk(binding.activity, key) } catch (_: Throwable) {}
            pendingLicenseKey = null
        }
    }
    override fun onDetachedFromActivityForConfigChanges() { activity = null; activityBinding = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity; activityBinding = binding }
    override fun onDetachedFromActivity() { activity = null; activityBinding = null }

    private fun ensureCameraPermissionThenStart() {
        val act = activity ?: return
        if (ContextCompat.checkSelfPermission(act, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            if (isProcessingActive && (usingPlatformView || (isSurfaceReady && !cleanupInProgress))) {
                startCamera()
            }
        } else {
            activityBinding?.addRequestPermissionsResultListener(this)
            ActivityCompat.requestPermissions(act, arrayOf(Manifest.permission.CAMERA), REQ_CAMERA)
        }
    }

    private fun startCamera() {
        val act = activity ?: return
        if (camera2Helper == null) camera2Helper = Camera2Helper(act, isFrontCamera)
        val helper = camera2Helper ?: return
        val pv = previewView ?: return
        
        val w = pendingSurfaceWidth
        val h = pendingSurfaceHeight
        if (w != null && h != null) {
            helper.setTargetDimensions(w, h)
        }

        pv.setCameraOrientation(helper.isFrontCamera, helper.sensorOrientation)

        helper.setFrameCallback(object : Camera2Helper.FrameCallback {
            override fun onFrameAvailable(
                y: java.nio.ByteBuffer?, u: java.nio.ByteBuffer?, v: java.nio.ByteBuffer?,
                width: Int, height: Int,
                yStride: Int, uStride: Int, vStride: Int,
                uPixelStride: Int, vPixelStride: Int
            ) {
                if (y == null || u == null || v == null) return

                // If a mirror update is pending (e.g., after switch), apply it exactly when the new feed starts
                pendingMirrorForNextFrame?.let { mirror ->
                    try { NosmaiSDK.setMirrorX(mirror) } catch (_: Throwable) {}
                    pendingMirrorForNextFrame = null
                    // Mirror is set; allow preview to resume
                    suppressPreviewUntilMirrored = false
                    // Smooth overlay fade-out now that the new feed is correctly mirrored (must run on UI thread)
                    runOnMain {
                        try {
                            switchOverlayView?.let { ov ->
                                ov.clearAnimation()
                                ov.animate().alpha(0f).setDuration(80).withEndAction {
                                    ov.visibility = android.view.View.GONE
                                }.start()
                            }
                        } catch (_: Throwable) {}
                    }
                }

                if (usingPlatformView) {
                    if (suppressPreviewUntilMirrored) {
                        // Drop frame to avoid transient flip during switch
                        return
                    }
                    pv.processYuvFrame(
                        y, u, v,
                        width, height,
                        yStride, uStride, vStride,
                        uPixelStride, vPixelStride,
                        calculateFrameRotation(helper.sensorOrientation, helper.isFrontCamera)
                    )
                    pv.requestRenderUpdate()
                    return
                }

                val s = surface
                if (s == null || !s.isValid) return
                if (!surfaceReboundOnce) {
                    try {
                        textureEntry?.surfaceTexture()?.setDefaultBufferSize(width, height)
                        NosmaiSDK.setRenderSurface(s, width, height)
                        // Apply mirror only if not already deferred; otherwise it will be applied above on first frame
                        if (pendingMirrorForNextFrame == null) {
                            NosmaiSDK.setMirrorX(isFrontCamera)
                            Log.d(TAG, "Frame processing: setMirrorX with isFrontCamera=$isFrontCamera")
                        }
                        surfaceReboundOnce = true
                    } catch (_: Throwable) {}
                }

                if (suppressPreviewUntilMirrored) {
                    // Drop frame to avoid transient flip during switch
                    return
                }

                pv.processYuvFrame(
                    y, u, v,
                    width, height,
                    yStride, uStride, vStride,
                    uPixelStride, vPixelStride,
                    calculateFrameRotation(helper.sensorOrientation, helper.isFrontCamera)
                )
                pv.requestRenderUpdate()
            }
        })
        helper.startCamera()
    }

    private fun calculateFrameRotation(sensorOrientation: Int, front: Boolean): Int {
        return if (front) { if (sensorOrientation == 270) 1 else 6 } else { if (sensorOrientation == 90) 2 else 1 }
    }

    private fun mergeAudioVideo(videoPath: String, audioPath: String, outputPath: String): Boolean {
        try {
            val videoExtractor = MediaExtractor()
            videoExtractor.setDataSource(videoPath)

            val audioExtractor = MediaExtractor()
            audioExtractor.setDataSource(audioPath)

            val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

            // Add video track
            var videoTrackIndex = -1
            var videoFormat: MediaFormat? = null
            for (i in 0 until videoExtractor.trackCount) {
                val format = videoExtractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME)
                if (mime != null && mime.startsWith("video/")) {
                    videoExtractor.selectTrack(i)
                    videoTrackIndex = muxer.addTrack(format)
                    videoFormat = format
                    break
                }
            }

            // Add audio track
            var audioTrackIndex = -1
            var audioFormat: MediaFormat? = null
            for (i in 0 until audioExtractor.trackCount) {
                val format = audioExtractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME)
                if (mime != null && mime.startsWith("audio/")) {
                    audioExtractor.selectTrack(i)
                    audioTrackIndex = muxer.addTrack(format)
                    audioFormat = format
                    break
                }
            }

            if (videoTrackIndex == -1) {
                Log.e(TAG, "No video track found")
                return false
            }

            muxer.start()

            // Write video data
            val videoBuf = java.nio.ByteBuffer.allocate(1024 * 1024)
            val videoBufferInfo = MediaCodec.BufferInfo()

            while (true) {
                val sampleSize = videoExtractor.readSampleData(videoBuf, 0)
                if (sampleSize < 0) break

                videoBufferInfo.offset = 0
                videoBufferInfo.size = sampleSize
                videoBufferInfo.presentationTimeUs = videoExtractor.sampleTime
                videoBufferInfo.flags = videoExtractor.sampleFlags

                muxer.writeSampleData(videoTrackIndex, videoBuf, videoBufferInfo)
                videoExtractor.advance()
            }

            // Write audio data if available
            if (audioTrackIndex != -1) {
                val audioBuf = java.nio.ByteBuffer.allocate(1024 * 1024)
                val audioBufferInfo = MediaCodec.BufferInfo()

                while (true) {
                    val sampleSize = audioExtractor.readSampleData(audioBuf, 0)
                    if (sampleSize < 0) break

                    audioBufferInfo.offset = 0
                    audioBufferInfo.size = sampleSize
                    audioBufferInfo.presentationTimeUs = audioExtractor.sampleTime
                    audioBufferInfo.flags = audioExtractor.sampleFlags

                    muxer.writeSampleData(audioTrackIndex, audioBuf, audioBufferInfo)
                    audioExtractor.advance()
                }
            }

            // Clean up
            muxer.stop()
            muxer.release()
            videoExtractor.release()
            audioExtractor.release()

            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to merge audio/video", e)
            return false
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        when (requestCode) {
            REQ_CAMERA -> {
                if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    if (isProcessingActive && (usingPlatformView || (isSurfaceReady && !cleanupInProgress))) {
                        startCamera()
                    }
                } else {
                    Log.e(TAG, "Camera permission denied")
                }
                return true
            }
            REQ_AUDIO -> {
                if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    Log.i(TAG, "Audio permission granted")
                } else {
                    Log.e(TAG, "Audio permission denied")
                }
                return true
            }
        }
        return false
    }
}
