package io.agora.agora_rtc_ng

import android.content.Context
import io.agora.rtc2.RtcEngine
import io.agora.rtc2.RtcEngineConfig
import io.agora.rtc2.IRtcEngineEventHandler
import io.agora.rtc2.video.AgoraVideoFrame
import io.agora.rtc2.video.VideoEncoderConfiguration
import android.view.Surface

// Nosmai SDK (AAR must be added to the app)
import com.nosmai.effect.api.NosmaiSDK
import com.nosmai.effect.api.NosmaiOffscreenSDK
import android.app.Activity
import android.opengl.GLSurfaceView
import android.util.Log
import android.view.ViewGroup
import android.widget.FrameLayout
import kotlin.math.min

object NosmaiAgoraBridge {
    // Singleton Agora instance - shared between Flutter and Native
    private var rtcEngine: RtcEngine? = null
    private var camera2Handler: Camera2Handler? = null
    private var isCustomCameraActive = false
    private var channelJoined = false
    private var currentChannelId: String? = null
    private var currentUserId: Int = 0
    private var isInitialized = false
    private var previewSurface: Surface? = null
    // Nosmai state
    private var nosmaiInitialized = false
    private var nosmaiFrameCount = 0
    private var glSurfaceView: GLSurfaceView? = null
    
    private var rgbaRenderer: RgbaPreviewRenderer? = null
    @Volatile private var previewMirrorX: Boolean = false
    private var previewSurfaceView: android.view.SurfaceView? = null
    private var glContainer: FrameLayout? = null
    @Volatile private var allowPush: Boolean = false
    @Volatile private var isPreviewFlipped = false
    fun getEngine(): RtcEngine? {
        return rtcEngine
    }

    fun initNosmai(context: Context, licenseKey: String): Boolean {
        return try {
            if (nosmaiInitialized) return true
    
            // Initialize Nosmai SDK
            NosmaiOffscreenSDK.setLicenseKey(licenseKey)
            NosmaiOffscreenSDK.initialize(context, object : NosmaiOffscreenSDK.OffscreenEventListener {
                override fun onInitialized() {
                    android.util.Log.i("NosmaiAgora", "NosmaiOffscreenSDK initialized successfully")
                    nosmaiInitialized = true
                    try { NosmaiOffscreenSDK.setMirrorX(false) } catch (_: Throwable) {}
                }
                
                override fun onError(error: String) {
                    android.util.Log.e("NosmaiAgora", "NosmaiOffscreenSDK error: $error")
                }
            })

            // Proactively mark off-screen pipeline active so beauty routes never fall back to on-screen path
            // Use default portrait target (updated later if needed)
            try {
                NosmaiOffscreenSDK.setOffscreenRendering(720, 1280, NosmaiOffscreenSDK.PixelFormat.I420)
            } catch (_: Throwable) {}
            
            true
        } catch (e: Exception) {
            android.util.Log.e("NosmaiAgora", "Failed to initialize Nosmai: ${e.message}")
            false
        }
    }
    
    fun setupYuvPreview(containerView: FrameLayout): Boolean {
        try {
            if (glSurfaceView != null) {
                try { (glSurfaceView?.parent as? ViewGroup)?.removeView(glSurfaceView) } catch (_: Throwable) {}
                try { containerView.removeAllViews() } catch (_: Throwable) {}
                containerView.addView(glSurfaceView, FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                ))
                // Ensure mirror state applied on reattach
                try { rgbaRenderer?.setMirrorX(previewMirrorX) } catch (_: Throwable) {}
                return true
            }

            // Create a GLSurfaceView with YUV preview renderer
            glSurfaceView = GLSurfaceView(containerView.context).apply {
                setEGLContextClientVersion(2)
                setEGLConfigChooser(8, 8, 8, 8, 16, 0)
                rgbaRenderer = RgbaPreviewRenderer()
                setRenderer(rgbaRenderer)
                renderMode = GLSurfaceView.RENDERMODE_WHEN_DIRTY
            }
            // Apply current mirror preference immediately
            try { rgbaRenderer?.setMirrorX(previewMirrorX) } catch (_: Throwable) {}

            containerView.addView(glSurfaceView, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            ))

            return true
        } catch (e: Exception) {
            android.util.Log.e("NosmaiAgora", "Failed to setup GL view: ${e.message}")
            return false
        }
    }

    private fun ensureGLRenderer(activity: Activity) {
        if (glSurfaceView != null) return
        val root = activity.findViewById<ViewGroup>(android.R.id.content)
        val container = FrameLayout(activity)
        container.alpha = 0f
        container.isClickable = false
        container.isFocusable = false
        root.addView(
            container,
            ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        )
        glContainer = container
        setupYuvPreview(container)
    }
    
        

    // Initialize singleton Agora instance - called from Flutter on app start
    fun initAgora(context: Context, appId: String): Boolean {
        // Always release existing engine to ensure clean state for each stream session
        if (rtcEngine != null) {
            android.util.Log.d("NosmaiAgora", "Releasing existing engine for clean restart")
            try {
                rtcEngine?.leaveChannel()
                RtcEngine.destroy()
            } catch (e: Exception) {
                android.util.Log.e("NosmaiAgora", "Error releasing engine: ${e.message}")
            }
            rtcEngine = null
            isInitialized = false
            channelJoined = false
            currentChannelId = null
            currentUserId = 0
            allowPush = false
        }

        return try {
            val config = RtcEngineConfig()
            config.mContext = context.applicationContext
            config.mAppId = appId

            config.mEventHandler = object : IRtcEngineEventHandler() {
                override fun onJoinChannelSuccess(channel: String?, uid: Int, elapsed: Int) {
                    android.util.Log.e("NosmaiAgora", "JOIN_SUCCESS: Native joined channel: $channel, uid=$uid")
                    android.util.Log.i("NosmaiAgora", "SUCCESS: Native Agora in channel with UID=$uid")
                    android.util.Log.e("NosmaiAgora", "JOINED: Native user $uid is now in channel $channel")
                    println("NOSMAI: Successfully joined channel $channel with UID $uid")
                    channelJoined = true
                    currentChannelId = channel
                    currentUserId = uid
                    allowPush = true
                    
                    // Camera will be started by delayed initialization in startCustomCamera
                    // Don't start it here to avoid double initialization
                    android.util.Log.d("NosmaiAgora", "Join successful, camera will be initialized by delayed handler")
                }

                override fun onUserJoined(uid: Int, elapsed: Int) {
                    android.util.Log.e("NosmaiAgora", "USER_JOINED: Remote user joined: $uid")
                }
                
                override fun onLeaveChannel(stats: io.agora.rtc2.IRtcEngineEventHandler.RtcStats?) {
                    android.util.Log.e("NosmaiAgora", "LEFT_CHANNEL: Native left channel")
                    channelJoined = false
                    allowPush = false
                }

                override fun onUserOffline(uid: Int, reason: Int) {
                    android.util.Log.e("NosmaiAgora", "USER_OFFLINE: User left: $uid, reason=$reason")
                }
                
                override fun onError(err: Int) {
                    android.util.Log.e("NosmaiAgora", "AGORA_ERROR: Error code $err")
                    when(err) {
                        3 -> android.util.Log.e("NosmaiAgora", "ERROR: Failed to open channel (token expired or invalid)")
                        17 -> android.util.Log.e("NosmaiAgora", "ERROR: Failed to join channel (rejected by server)")
                        else -> android.util.Log.e("NosmaiAgora", "ERROR: Check Agora error code documentation")
                    }
                }
            }

            rtcEngine = RtcEngine.create(config)
            isInitialized = true
            android.util.Log.d("NosmaiAgora", "Singleton Agora instance created")
            true
        } catch (e: Exception) {
            android.util.Log.e("NosmaiAgora", "Failed to init: ${e.message}")
            false
        }
    }

    fun releaseAgora() {
        rtcEngine?.let {
            RtcEngine.destroy()
            rtcEngine = null
        }
    }


    private fun _updateRendererMirrorState() {
        try {
            val isFront = camera2Handler?.isFrontCamera() ?: true
            
            val shouldMirrorHorizontally = if (isFront) !isPreviewFlipped else isPreviewFlipped
            
            rgbaRenderer?.setMirrorX(shouldMirrorHorizontally)
            rgbaRenderer?.setMirrorY(false) // iski humein zaroorat nahi.
    
            glSurfaceView?.requestRender()
            Log.d("FlipDebug", "Renderer state updated: isFront=$isFront, isFlipped=$isPreviewFlipped, finalMirror=$shouldMirrorHorizontally")
    
        } catch (t: Throwable) {
            Log.e("FlipDebug", "Error in _updateRendererMirrorState: ${t.message}")
        }
    }
    
    
    fun getFlutterEngineInfo(): String {
        return try {
            val info = StringBuilder()
            
            // Check our native engine
            if (rtcEngine != null) {
                info.append("Native Engine: Active\n")
                info.append("Channel Joined: $channelJoined\n")
                info.append("Channel ID: $currentChannelId\n")
                info.append("User ID: $currentUserId\n")
            } else {
                info.append("Native Engine: Not initialized\n")
            }
            
            info.toString()
        } catch (e: Exception) {
            "Error: ${e.message}"
        }
    }
    
    // Methods for Flutter to control native instance
    fun enableVideo(): Boolean {
        return try {
            rtcEngine?.enableVideo()
            true
        } catch (e: Exception) {
            android.util.Log.e("NosmaiAgora", "Failed to enable video: ${e.message}")
            false
        }
    }
    
    private var appContext: Context? = null
    
    fun enableLocalVideo(enabled: Boolean): Boolean {
        return try {
            rtcEngine?.enableLocalVideo(enabled) ?: -1
            
            if (enabled && isCustomCameraActive && camera2Handler == null) {
                android.util.Log.d("NosmaiAgora", "Initializing camera on enableLocalVideo")
                val context = appContext ?: return false
                
                rgbaRenderer?.resetTextureState()
                
                camera2Handler = Camera2Handler(context)
                previewSurface?.let { 
                    camera2Handler?.setPreviewSurface(it) 
                }
                camera2Handler?.startCamera()
                android.util.Log.d("NosmaiAgora", "Camera started on enableLocalVideo")
            } else if (!enabled && camera2Handler != null) {
                // If disabling video, stop the camera
                android.util.Log.d("NosmaiAgora", "Stopping camera on disableLocalVideo")
                camera2Handler?.stopCamera()
                camera2Handler = null
                rgbaRenderer?.resetTextureState()
            }
            
            true
        } catch (e: Exception) {
            android.util.Log.e("NosmaiAgora", "Failed to enable local video: ${e.message}")
            false
        }
    }
    
    fun startPreview(): Boolean {
        return try {
            rtcEngine?.startPreview()
            true
        } catch (e: Exception) {
            android.util.Log.e("NosmaiAgora", "Failed to start preview: ${e.message}")
            false
        }
    }
    
    fun stopPreview(): Boolean {
        return try {
            rtcEngine?.stopPreview()
            true
        } catch (e: Exception) {
            android.util.Log.e("NosmaiAgora", "Failed to stop preview: ${e.message}")
            false
        }
    }
    
    fun setClientRole(role: Int): Boolean {
        return try {
            rtcEngine?.setClientRole(role)
            true
        } catch (e: Exception) {
            android.util.Log.e("NosmaiAgora", "Failed to set client role: ${e.message}")
            false
        }
    }
    
    fun joinChannel(token: String, channelId: String, userId: Int): Boolean {
        return try {
            if (channelJoined && currentChannelId == channelId) {
                android.util.Log.d("NosmaiAgora", "Already in channel: $channelId")
                return true
            }
            
            rtcEngine?.joinChannel(token, channelId, "", userId)
            android.util.Log.d("NosmaiAgora", "Joining channel: $channelId with UID: $userId")
            true
        } catch (e: Exception) {
            android.util.Log.e("NosmaiAgora", "Failed to join channel: ${e.message}")
            false
        }
    }
    
    fun leaveChannel(): Boolean {
        return try {
            rtcEngine?.leaveChannel()
            channelJoined = false
            allowPush = false
            true
        } catch (e: Exception) {
            android.util.Log.e("NosmaiAgora", "Failed to leave channel: ${e.message}")
            false
        }
    }

    // Handler for delayed camera init
    private var cameraInitHandler: android.os.Handler? = null
    private var cameraInitRunnable: Runnable? = null
    
    // Beauty filters instance
    private val beautyFilters = BeautyFilters()
    
    // Apply brightness filter
    fun applyBrightness(brightness: Float): Boolean {
        android.util.Log.d("NosmaiAgora", "Applying brightness: $brightness")
        return beautyFilters.applyBrightness(brightness)
    }

    // Skin smoothing filter
    fun applySkinSmoothing(level: Float): Boolean {
        android.util.Log.d("NosmaiAgora", "Applying skin smoothing: $level")
        return beautyFilters.applySkinSmoothing(level)
    }

    // Skin whitening filter
    fun applySkinWhitening(level: Float): Boolean {
        android.util.Log.d("NosmaiAgora", "Applying skin whitening: $level")
        return beautyFilters.applySkinWhitening(level)
    }

    // Face slimming filter
    fun applyFaceSlimming(level: Float): Boolean {
        android.util.Log.d("NosmaiAgora", "Applying face slimming: $level")
        return beautyFilters.applyFaceSlimming(level)
    }

    // Eye enlargement filter
    fun applyEyeEnlargement(level: Float): Boolean {
        android.util.Log.d("NosmaiAgora", "Applying eye enlargement: $level")
        return beautyFilters.applyEyeEnlargement(level)
    }

    // Nose size filter
    fun applyNoseSize(level: Float): Boolean {
        android.util.Log.d("NosmaiAgora", "Applying nose size: $level")
        return beautyFilters.applyNoseSize(level)
    }

    // Contrast filter
    fun applyContrast(contrast: Float): Boolean {
        android.util.Log.d("NosmaiAgora", "Applying contrast: $contrast")
        return beautyFilters.applyContrast(contrast)
    }

    // Hue filter
    fun applyHue(hue: Float): Boolean {
        android.util.Log.d("NosmaiAgora", "Applying hue: $hue")
        return beautyFilters.applyHue(hue)
    }

    // RGB filter
    fun applyRGB(red: Float, green: Float, blue: Float): Boolean {
        android.util.Log.d("NosmaiAgora", "Applying RGB: R=$red, G=$green, B=$blue")
        return beautyFilters.applyRGB(red, green, blue)
    }

    // Lipstick makeup
    fun applyLipstick(intensity: Float): Boolean {
        android.util.Log.d("NosmaiAgora", "Applying lipstick: $intensity")
        return beautyFilters.applyLipstick(intensity)
    }

    // Blusher makeup
    fun applyBlusher(intensity: Float): Boolean {
        android.util.Log.d("NosmaiAgora", "Applying blusher: $intensity")
        return beautyFilters.applyBlusher(intensity)
    }

    // Remove all filters
    fun removeAllFilters(): Boolean {
        android.util.Log.d("NosmaiAgora", "Removing all filters")
        return beautyFilters.removeAllFilters()
    }

    // Get current filter states
    fun getCurrentFilterStates(): Map<String, Float> {
        return beautyFilters.getCurrentFilterStates()
    }

    // Check if any filter is active
    fun hasActiveFilters(): Boolean {
        return beautyFilters.hasActiveFilters()
    }

    // Apply makeup blend level
    fun applyMakeupBlendLevel(filterName: String, level: Float): Boolean {
        android.util.Log.d("NosmaiAgora", "Applying makeup blend level: $filterName = $level")
        return beautyFilters.applyMakeupBlendLevel(filterName, level)
    }

    // Exposure filter
    fun applyExposure(exposure: Float): Boolean {
        android.util.Log.d("NosmaiAgora", "Applying exposure: $exposure")
        return beautyFilters.applyExposure(exposure)
    }

    // Saturation filter
    fun applySaturation(saturation: Float): Boolean {
        android.util.Log.d("NosmaiAgora", "Applying saturation: $saturation")
        return beautyFilters.applySaturation(saturation)
    }

    // Sharpen filter
    fun applySharpen(sharpen: Float): Boolean {
        android.util.Log.d("NosmaiAgora", "Applying sharpen: $sharpen")
        return beautyFilters.applySharpen(sharpen)
    }

    // White balance filter
    fun applyWhiteBalance(temperatureK: Float, tint: Float): Boolean {
        android.util.Log.d("NosmaiAgora", "Applying white balance: temp=$temperatureK, tint=$tint")
        return beautyFilters.applyWhiteBalance(temperatureK, tint)
    }

    // Grayscale filter
    fun setGrayscaleEnabled(enabled: Boolean): Boolean {
        android.util.Log.d("NosmaiAgora", "Setting grayscale: $enabled")
        return beautyFilters.setGrayscaleEnabled(enabled)
    }
    
    // Switch camera between front and back
    fun switchCamera(): Boolean {
        return try {
            camera2Handler?.switchCamera()
            Thread.sleep(100)
            
            val isFront = camera2Handler?.isFrontCamera() ?: true
            NosmaiOffscreenSDK.setCameraFacing(isFront)
    
            isPreviewFlipped = false
            _updateRendererMirrorState()
            
            true
        } catch (e: Exception) {
            Log.e("FlipDebug", "Error in switchCamera: ${e.message}")
            false
        }
    }
    
    fun enableLocalAudio(enabled: Boolean): Boolean {
        return try {
            // For live streaming, we want to keep audio enabled but control muting
            // enabled = true: unmute audio stream
            // enabled = false: mute audio stream
            rtcEngine?.muteLocalAudioStream(!enabled)
            android.util.Log.d("NosmaiAgora", "enableLocalAudio: $enabled (muted: ${!enabled})")
            true
        } catch (e: Exception) {
            android.util.Log.e("NosmaiAgora", "Failed to enable local audio: ${e.message}")
            false
        }
    }
    
    // Teardown all streaming resources safely (idempotent)
    fun teardownStreaming() {
        android.util.Log.d("NosmaiAgora", "teardownStreaming called")
        
        // Cancel any pending camera initialization
        cameraInitRunnable?.let { 
            cameraInitHandler?.removeCallbacks(it)
            cameraInitRunnable = null
        }
        
        // First stop frame pushing
        try { allowPush = false } catch (_: Throwable) {}
        try { channelJoined = false } catch (_: Throwable) {}
        
        // Stop camera and clear handler
        try { 
            camera2Handler?.stopCamera()
            camera2Handler = null
            // Add delay to ensure camera is fully released
            Thread.sleep(200)
        } catch (e: Throwable) {
            android.util.Log.e("NosmaiAgora", "Error stopping camera: ${e.message}")
        }
        
        // Clear frame listener and cleanup Nosmai SDK (but don't destroy it)
        try { 
            NosmaiOffscreenSDK.setFrameListener(null)
            // Don't call cleanup() here - keep SDK initialized for reuse
            // NosmaiOffscreenSDK.cleanup() 
        } catch (e: Throwable) {
            android.util.Log.e("NosmaiAgora", "Error clearing frame listener: ${e.message}")
        }
        
        // Disable external video source in Agora
        try {
            rtcEngine?.setExternalVideoSource(
                false,
                false,
                io.agora.rtc2.Constants.ExternalVideoSourceType.VIDEO_FRAME
            )
        } catch (e: Throwable) {
            android.util.Log.e("NosmaiAgora", "Error disabling external video: ${e.message}")
        }
        
        // Leave channel and destroy engine to ensure clean state
        try { 
            rtcEngine?.leaveChannel()
            // Add delay to ensure channel leave completes
            Thread.sleep(200)
            
            // Destroy the engine completely to avoid SIGSEGV on next use
            RtcEngine.destroy()
            rtcEngine = null
            isInitialized = false
        } catch (e: Throwable) {
            android.util.Log.e("NosmaiAgora", "Error leaving channel/destroying engine: ${e.message}")
        }
        
        // Clear state variables
        currentChannelId = null
        currentUserId = 0
        isCustomCameraActive = false
        
        android.util.Log.d("NosmaiAgora", "teardownStreaming completed - engine destroyed")
    }
    
    fun startCustomCamera(context: Context, appId: String, token: String, channelId: String, userId: Int = 0, startCameraImmediately: Boolean = true): Boolean {
        return try {
            android.util.Log.d("NosmaiAgora", "startCustomCamera called - channelId: $channelId, userId: $userId, startCameraImmediately: $startCameraImmediately")
            
            // Store context for later use
            appContext = context.applicationContext
            
            // For multi-host scenario: if same channel but different user, need to restart camera
            if (isCustomCameraActive && currentChannelId == channelId) {
                if (currentUserId != userId && userId != 0) {
                    android.util.Log.d("NosmaiAgora", "Same channel but different user (multi-host) - restarting camera for user: $userId")
                    // Stop current camera and restart for new host
                    camera2Handler?.stopCamera()
                    camera2Handler = null
                    Thread.sleep(200) // Small delay to ensure camera is released
                    // Continue to setup camera for new host
                } else {
                    android.util.Log.d("NosmaiAgora", "Already active for same channel and user")
                    return true
                }
            }
            
            // If active with different channel, cleanup first
            if (isCustomCameraActive && currentChannelId != channelId) {
                android.util.Log.d("NosmaiAgora", "Switching channels - cleaning up first")
                teardownStreaming()
                // Add small delay to ensure cleanup completes
                Thread.sleep(100)
            }
            
            // Ensure singleton is initialized
            if (!isInitialized || rtcEngine == null) {
                android.util.Log.e("NosmaiAgora", "Initializing Agora engine")
                if (!initAgora(context, appId)) {
                    android.util.Log.e("NosmaiAgora", "Failed to initialize Agora")
                    return false
                }
            }
            
            android.util.Log.e("NosmaiAgora", "Configuring video settings")
            
            // Configure video (CPU path with RGBA->I420)
            rtcEngine?.enableVideo()
            rtcEngine?.setClientRole(io.agora.rtc2.Constants.CLIENT_ROLE_BROADCASTER)
            rtcEngine?.adjustPlaybackSignalVolume(0)
            rtcEngine?.muteAllRemoteAudioStreams(true)
            android.util.Log.d("NosmaiAgora", "Disabled audio playback for broadcaster to prevent echo")
            // Enable audio for broadcasting
            rtcEngine?.enableAudio()
            
            // Mute all remote audio streams to prevent hearing other participants
            // This only affects local playback, not publishing
            rtcEngine?.muteAllRemoteAudioStreams(true)
            android.util.Log.d("NosmaiAgora", "Enabled audio publishing, muted remote audio playback")
            
            // no-op: legacy renderer removed
            
            

            // Set up external video source for test pattern
            val extSourceResult = rtcEngine?.setExternalVideoSource(
                true, // enable
                false, // useTexture = false (I420 push)
                io.agora.rtc2.Constants.ExternalVideoSourceType.VIDEO_FRAME
            )
            android.util.Log.e("NosmaiAgora", "External video source setup result: $extSourceResult")
            
            // Configure video encoder (720p portrait with rotation metadata)
            val videoConfig = io.agora.rtc2.video.VideoEncoderConfiguration()
            videoConfig.dimensions = io.agora.rtc2.video.VideoEncoderConfiguration.VideoDimensions(720, 1280)
            videoConfig.frameRate = 30
            videoConfig.bitrate = 1800
            val encConfigResult = rtcEngine?.setVideoEncoderConfiguration(videoConfig)
            android.util.Log.e("NosmaiAgora", "Video encoder config result: $encConfigResult")
            
            // Join channel with the SAME user ID to publish as the primary host
            val nativeUserId = userId
            
            android.util.Log.e("NosmaiAgora", "JOINING: channel=$channelId, nativeUserId=$nativeUserId, token=${token.take(20)}...")
            
            val joinResult = rtcEngine?.joinChannel(token, channelId, "", nativeUserId)
            android.util.Log.e("NosmaiAgora", "Join channel result: $joinResult")
            
            if (joinResult != 0) {
                android.util.Log.e("NosmaiAgora", "JOIN_FAILED: Error code $joinResult")
                when(joinResult) {
                    -2 -> android.util.Log.e("NosmaiAgora", "Invalid argument")
                    -3 -> android.util.Log.e("NosmaiAgora", "SDK not ready")
                    -5 -> android.util.Log.e("NosmaiAgora", "Call rejected")
                    -7 -> android.util.Log.e("NosmaiAgora", "SDK not initialized")
                    else -> android.util.Log.e("NosmaiAgora", "Unknown error")
                }
            }
            
            // Setup offscreen I420 output (avoid EGL). Push I420 directly to Agora and feed local preview.
            try {
                // Request RGBA from offscreen for accurate preview and stable colors
                NosmaiOffscreenSDK.setOffscreenRendering(720, 1280, NosmaiOffscreenSDK.PixelFormat.RGBA)
                NosmaiOffscreenSDK.setFrameListener { data, width, height, format, timestampNs ->
                    if (data == null) return@setFrameListener
                    if (format.equals("RGBA", ignoreCase = true)) {
                        // Local: display RGBA directly
                        rgbaRenderer?.submitFrame(data, width, height)
                        try { glSurfaceView?.requestRender() } catch (_: Throwable) {}
                        // Remote: convert to I420 (BT.601 limited) and push
                        if (allowPush && channelJoined) {
                            val i420 = rgbaToI420(data, width, height)
                            pushFrameToNativeAgora(i420, width, height)
                        }
                    } else if (format.equals("I420", ignoreCase = true)) {
                        // Fallback if sink delivered I420 (rare)
                        if (allowPush && channelJoined) pushFrameToNativeAgora(data, width, height)
                        // Convert for RGBA preview path
                        val rgba = i420ToRgba(data, width, height)
                        rgbaRenderer?.submitFrame(rgba, width, height)
                        try { glSurfaceView?.requestRender() } catch (_: Throwable) {}
                    }
                }
            } catch (t: Throwable) {
                android.util.Log.e("NosmaiAgora", "Failed to init offscreen listener: ${t.message}")
            }

            // Store channel info for later use
            currentChannelId = channelId
            currentUserId = userId
            isCustomCameraActive = true
            
            android.util.Log.d("NosmaiAgora", "Updated current state - channelId: $currentChannelId, userId: $currentUserId")
            
            // Initialize camera asynchronously to avoid blocking (only if startCameraImmediately is true)
            if (startCameraImmediately) {
                cameraInitHandler = android.os.Handler(android.os.Looper.getMainLooper())
                cameraInitRunnable = Runnable {
                    try {
                        // Check if still active (not torn down)
                        if (!isCustomCameraActive) {
                            android.util.Log.d("NosmaiAgora", "Camera init cancelled - stream no longer active")
                            return@Runnable
                        }
                        
                        // Check if camera already initialized (prevent double init)
                        if (camera2Handler != null) {
                            android.util.Log.d("NosmaiAgora", "Camera already initialized, skipping")
                            return@Runnable
                        }
                        
                        android.util.Log.d("NosmaiAgora", "Delayed camera initialization starting")
                        
                        android.util.Log.d("NosmaiAgora", "Creating new Camera2Handler")
                        camera2Handler = Camera2Handler(context)


                        previewSurface?.let { 
                            android.util.Log.d("NosmaiAgora", "Setting preview surface")
                            camera2Handler?.setPreviewSurface(it) 
                        }
                        
                        // Start camera
                        camera2Handler?.startCamera()
                        android.util.Log.d("NosmaiAgora", "Camera2 started for offscreen I420 feed")

                        try {
                            isPreviewFlipped = false 
                            _updateRendererMirrorState()
                        } catch (_: Throwable) {}
                        
                        
                                                
                    
                    } catch (e: Exception) {
                        android.util.Log.e("NosmaiAgora", "Failed to start camera: ${e.message}")
                        e.printStackTrace()
                    }
                }
                cameraInitHandler?.postDelayed(cameraInitRunnable!!, 500) // 500ms delay to ensure everything is ready
            } else {
                android.util.Log.d("NosmaiAgora", "Camera initialization skipped - waiting for explicit enable")
            }
            
            android.util.Log.d("NosmaiAgora", "CUSTOM_CAMERA_STARTED: Setup complete, camera will start shortly")
            true
        } catch (e: Exception) {
            android.util.Log.e("NosmaiAgora", "Failed to start: ${e.message}")
            e.printStackTrace()
            false
        }
    }


    fun flipCameraPreview(): Boolean {
        isPreviewFlipped = !isPreviewFlipped 
        _updateRendererMirrorState()
        Log.d("FlipDebug", "Flip button pressed. isPreviewFlipped is now: $isPreviewFlipped")
        return true
    }
    

    
    fun stopCustomCamera(): Boolean {
        return try {
            android.util.Log.d("NosmaiAgora", "stopCustomCamera called")
            
            // Stop Camera2 capture if not already stopped
            if (camera2Handler != null) {
                camera2Handler?.stopCamera()
                camera2Handler = null
            }
            
                // Remove hidden GL container
                try {
                    val cont = glContainer
                    if (cont != null) {
                        val parent = cont.parent as? ViewGroup
                        parent?.removeView(cont)
                    }
                    glSurfaceView = null
                    glContainer = null
                } catch (_: Throwable) {}

            // Leave channel if joined
            if (channelJoined) {
                rtcEngine?.leaveChannel()
                channelJoined = false
            }
            
            // Clear frame listener but don't destroy NosmaiSDK (keep for reuse)
            try {
                NosmaiOffscreenSDK.setFrameListener(null)
                // Don't call cleanup() - keep SDK initialized for reuse
                // NosmaiOffscreenSDK.cleanup()
            } catch (e: Exception) {
                android.util.Log.e("NosmaiAgora", "Error clearing frame listener: ${e.message}")
            }

            // Disable external video source
            rtcEngine?.setExternalVideoSource(
                false,
                false, 
                io.agora.rtc2.Constants.ExternalVideoSourceType.VIDEO_FRAME
            )
            
            // Reset state flags
            isCustomCameraActive = false
            allowPush = false
            currentChannelId = null
            currentUserId = 0
            
            android.util.Log.d("NosmaiAgora", "stopCustomCamera completed")
            true
        } catch (e: Exception) {
            android.util.Log.e("NosmaiAgora", "Failed to stop: ${e.message}")
            false
        }
    }

    // Called from PlatformView to attach preview surface for zero-latency preview
    fun setCameraPreviewSurface(surface: Surface?) {
        previewSurface = surface
        if (camera2Handler == null) {
            android.util.Log.w("NosmaiAgora", "setCameraPreviewSurface: camera2Handler is null (will attach when camera starts)")
            return
        }
        android.util.Log.d("NosmaiAgora", "Attaching preview surface now: ${surface != null}")
        camera2Handler?.attachPreviewSurface(surface)
    }
    
    private var frameCount = 0
    
    private fun pushFrameToNativeAgora(data: ByteArray, width: Int, height: Int) {
        try {
            rtcEngine?.let { engine ->
                val videoFrame = AgoraVideoFrame()
                videoFrame.format = AgoraVideoFrame.FORMAT_I420
                videoFrame.stride = width
                videoFrame.height = height
                videoFrame.buf = data
                videoFrame.timeStamp = System.currentTimeMillis()
                // No rotation needed - Nosmai now correctly rotates based on sensor orientation
                videoFrame.rotation = 0
                
                val result = engine.pushExternalVideoFrame(videoFrame)
                
                // Frame count retained for potential diagnostics; avoid frequent logs
                frameCount++
            }
        } catch (e: Exception) {
            android.util.Log.e("NosmaiAgora", "Error pushing: ${e.message}")
        }
    }

    // RGBA -> I420 conversion (planar YUV) for offscreen RGBA output
    private fun rgbaToI420(rgba: ByteArray, width: Int, height: Int): ByteArray {
        val ySize = width * height
        val uvW = (width + 1) / 2
        val uvH = (height + 1) / 2
        val uvSize = uvW * uvH
        val out = ByteArray(ySize + uvSize * 2)
        var yIndex = 0
        var uIndex = ySize
        var vIndex = ySize + uvSize

        var idx = 0
        // Luma (BT.601 limited)
        for (j in 0 until height) {
            for (i in 0 until width) {
                val r = rgba[idx].toInt() and 0xFF
                val g = rgba[idx + 1].toInt() and 0xFF
                val b = rgba[idx + 2].toInt() and 0xFF
                val y = ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16
                out[yIndex++] = y.coerceIn(16, 235).toByte()
                idx += 4 // skip alpha
            }
        }

        // Chroma subsampling 4:2:0 (BT.601 limited), clamp odd sizes
        for (j in 0 until height step 2) {
            val jn = if (j + 1 < height) j + 1 else j
            for (i in 0 until width step 2) {
                val inx = if (i + 1 < width) i + 1 else i

                val p1 = (j * width + i) * 4
                val p2 = (j * width + inx) * 4
                val p3 = (jn * width + i) * 4
                val p4 = (jn * width + inx) * 4

                val r = ((rgba[p1].toInt() and 0xFF) + (rgba[p2].toInt() and 0xFF) +
                         (rgba[p3].toInt() and 0xFF) + (rgba[p4].toInt() and 0xFF)) / 4
                val g = ((rgba[p1 + 1].toInt() and 0xFF) + (rgba[p2 + 1].toInt() and 0xFF) +
                         (rgba[p3 + 1].toInt() and 0xFF) + (rgba[p4 + 1].toInt() and 0xFF)) / 4
                val b = ((rgba[p1 + 2].toInt() and 0xFF) + (rgba[p2 + 2].toInt() and 0xFF) +
                         (rgba[p3 + 2].toInt() and 0xFF) + (rgba[p4 + 2].toInt() and 0xFF)) / 4

                val u = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                val v = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                out[uIndex++] = u.coerceIn(16, 240).toByte()
                out[vIndex++] = v.coerceIn(16, 240).toByte()
            }
        }
        return out
    }

    // I420 -> RGBA for RGBA preview fallback
    private fun i420ToRgba(i420: ByteArray, width: Int, height: Int): ByteArray {
        val ySize = width * height
        val uvW = (width + 1) / 2
        val uvH = (height + 1) / 2
        val uOff = ySize
        val vOff = ySize + uvW * uvH
        val out = ByteArray(width * height * 4)
        var idx = 0
        for (j in 0 until height) {
            val j2 = j / 2
            for (i in 0 until width) {
                val i2 = i / 2
                val y = (i420[j * width + i].toInt() and 0xFF)
                val u = (i420[uOff + j2 * uvW + i2].toInt() and 0xFF) - 128
                val v = (i420[vOff + j2 * uvW + i2].toInt() and 0xFF) - 128
                // Video-range inverse BT.601
                val yf = 1.164f * (y - 16)
                var r = (yf + 1.596f * v).toInt()
                var g = (yf - 0.392f * u - 0.813f * v).toInt()
                var b = (yf + 2.017f * u).toInt()
                if (r < 0) r = 0 else if (r > 255) r = 255
                if (g < 0) g = 0 else if (g > 255) g = 255
                if (b < 0) b = 0 else if (b > 255) b = 255
                out[idx] = r.toByte(); out[idx+1] = g.toByte(); out[idx+2] = b.toByte(); out[idx+3] = 0xFF.toByte()
                idx += 4
            }
        }
        return out
    }

    // Swap U and V planes in an I420 buffer (to handle YV12 output)
    private fun i420SwapUV(src: ByteArray, width: Int, height: Int): ByteArray {
        val ySize = width * height
        val uvSize = ySize / 4
        // src: [Y][U][V] => dst: [Y][V][U]
        val dst = ByteArray(src.size)
        System.arraycopy(src, 0, dst, 0, ySize)
        // swap chroma planes
        System.arraycopy(src, ySize + uvSize, dst, ySize, uvSize) // V -> U
        System.arraycopy(src, ySize, dst, ySize + uvSize, uvSize) // U -> V
        return dst
    }
    fun clearGLResources() {
        glSurfaceView = null
    }
}
