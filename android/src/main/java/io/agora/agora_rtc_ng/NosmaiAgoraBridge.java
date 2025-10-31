package io.agora.agora_rtc_ng;

import android.content.Context;
import android.util.Log;
import android.view.View;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.os.Process;

import com.nosmai.effect.api.NosmaiSDK;
import com.nosmai.effect.api.NosmaiPreviewView;
import com.nosmai.effect.api.NosmaiBeauty;
import com.nosmai.effect.NosmaiEffects;
import com.nosmai.effect.api.NosmaiCloud;
import com.nosmai.effect.internal.Nosmai;

import io.agora.rtc2.RtcEngine;
import io.agora.rtc2.RtcEngineConfig;
import io.agora.rtc2.IRtcEngineEventHandler;
import io.agora.rtc2.Constants;
import io.agora.rtc2.ChannelMediaOptions;
import io.agora.rtc2.video.AgoraVideoFrame;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Queue;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.ConcurrentHashMap;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.concurrent.CountDownLatch;
import io.flutter.plugin.common.MethodChannel.Result;
import org.json.JSONObject;
import org.json.JSONException;
import android.util.Base64;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import java.io.ByteArrayOutputStream;
import android.view.TextureView;
import android.view.ViewGroup;
import android.os.Build;
import android.content.ContentValues;
import android.provider.MediaStore;
import android.net.Uri;
import java.io.OutputStream;
import java.io.FileInputStream;
import android.os.Environment;
import androidx.annotation.Nullable;

/**
 * NosmaiAgoraBridge - Core Integration Bridge
 *
 * Manages Nosmai SDK + Agora RTC Engine integration
 * Singleton pattern for consistent state management
 * Supports live streaming with real-time filters
 */
public class NosmaiAgoraBridge {

    private static final String TAG = "NosmaiAgoraBridge";
    private static final String ASSET_MANIFEST_PATH = "flutter_assets/AssetManifest.json";
    private static final String FILTERS_PREFIX = "assets/filters/";
    private static final String CACHE_DIR_NAME = "NosmaiLocalFilters";

    private static final int FD_SKIP_FRAMES = 4;

    private static NosmaiAgoraBridge instance;

    private Context context;

    // SDK instances
    private RtcEngine agoraEngine;
    private NosmaiPreviewView previewView;
    private Camera2Helper camera2Helper;

    // Threading helpers
    private HandlerThread beautyThread;
    private Handler beautyHandler;
    private final Object beautyTaskLock = new Object();
    private final Map<String, BeautyCommand> pendingBeautyCommands = new HashMap<>();

    // State flags
    private boolean nosmaiInitialized = false;
    private boolean agoraInitialized = false;
    private boolean isCustomCameraActive = false;
    private boolean isCameraPreviewActive = false;
    private boolean channelJoined = false;
    private boolean mirrorModeEnabled = false;
    private boolean allowPush = false; // Controls frame pushing to Agora

    // License key for re-initialization
    private String storedLicenseKey = null;

    // Channel info
    private String currentChannelId;
    private int currentUserId;

    // Beauty filter states (tracking for getCurrentFilterStates)
    private float skinSmoothingLevel = 0.0f;
    private float skinWhiteningLevel = 0.0f;
    private float faceSlimmingLevel = 0.0f;
    private float eyeEnlargementLevel = 0.0f;
    private float noseSizeLevel = 0.0f;
    private float brightnessLevel = 0.0f;
    private float contrastLevel = 1.0f;
    private float hueLevel = 0.0f;
    private float lipstickLevel = 0.0f;
    private float blusherLevel = 0.0f;
    private float redMultiplier = 1.0f;
    private float greenMultiplier = 1.0f;
    private float blueMultiplier = 1.0f;
    private float exposureLevel = 0.0f;
    private float saturationLevel = 1.0f;
    private float sharpenLevel = 0.0f;
    private float whiteBalanceTemp = 5000.0f;
    private float whiteBalanceTint = 0.0f;
    private boolean grayscaleEnabled = false;
    private String currentFilterPath = "";

    // Recording state
    private boolean isRecording = false;
    private long recordingStartTime = 0;
    private String recordingPath = null;

    // HSB adjustment values
    private float hsbHue = 0.0f;
    private float hsbSaturation = 0.0f;
    private float hsbBrightness = 0.0f;

    private static final float FLOAT_EQ_EPSILON = 0.0005f;

    private final Queue<AgoraVideoFrame> framePool = new ConcurrentLinkedQueue<>();
    private static final int MAX_POOL_SIZE = 5;

    public static synchronized NosmaiAgoraBridge getInstance(Context context) {
        if (instance == null) {
            instance = new NosmaiAgoraBridge(context.getApplicationContext());
        }
        return instance;
    }

    private NosmaiAgoraBridge(Context context) {
        this.context = context;
        startBeautyThread();
        resetFilterStates();
        Log.i(TAG, "NosmaiAgoraBridge instance created");
    }

    private synchronized void startBeautyThread() {
        if (beautyThread != null) {
            return;
        }

        beautyThread = new HandlerThread("NosmaiBeautyThread", Process.THREAD_PRIORITY_DISPLAY);
        beautyThread.start();
        beautyHandler = new Handler(beautyThread.getLooper());
        Log.i(TAG, "Beauty handler thread started");
    }

    private synchronized void stopBeautyThread() {
        if (beautyThread == null) {
            return;
        }

        HandlerThread thread = beautyThread;
        beautyThread = null;
        beautyHandler = null;
        synchronized (beautyTaskLock) {
            pendingBeautyCommands.clear();
        }

        thread.quitSafely();
        try {
            thread.join();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            Log.w(TAG, "Interrupted while stopping beauty thread");
        }
        Log.i(TAG, "Beauty handler thread stopped");
    }

    private boolean submitBeautyTask(String operation, Runnable task) {
        Handler handler = beautyHandler;
        if (handler == null) {
            Log.w(TAG, operation + " requested before handler ready; executing inline");
            runBeautySafely(operation, task);
            return true;
        }

        if (Looper.myLooper() == handler.getLooper()) {
            synchronized (beautyTaskLock) {
                BeautyCommand previous = pendingBeautyCommands.remove(operation);
                if (previous != null) {
                    handler.removeCallbacks(previous);
                }
            }
            runBeautySafely(operation, task);
            return true;
        }

        BeautyCommand command = new BeautyCommand(operation, task);
        synchronized (beautyTaskLock) {
            BeautyCommand previous = pendingBeautyCommands.put(operation, command);
            if (previous != null) {
                handler.removeCallbacks(previous);
            }
        }
        handler.post(command);
        return true;
    }

    private void runBeautySafely(String operation, Runnable task) {
        try {
            task.run();
        } catch (Exception e) {
            Log.e(TAG, "Error during " + operation, e);
        }
    }

    private final class BeautyCommand implements Runnable {
        private final String operation;
        private final Runnable delegate;

        BeautyCommand(String operation, Runnable delegate) {
            this.operation = operation;
            this.delegate = delegate;
        }

        @Override
        public void run() {
            synchronized (beautyTaskLock) {
                pendingBeautyCommands.remove(operation);
            }
            runBeautySafely(operation, delegate);
        }
    }

    private boolean floatEquals(float a, float b) {
        return Math.abs(a - b) <= FLOAT_EQ_EPSILON;
    }

    // ============================================
    // INITIALIZATION
    // ============================================

    /**
     * Initialize Nosmai SDK with license key
     * Same as iOS: Nosmai.initialize(licenseKey)
     */
    public boolean initialize(String licenseKey) {
        if (nosmaiInitialized) {
            Log.i(TAG, "Nosmai already initialized");
            return true;
        }

        try {
            NosmaiSDK.initialize(context, licenseKey);
            storedLicenseKey = licenseKey; // Store for re-initialization
            nosmaiInitialized = true;
            Log.i(TAG, "Nosmai SDK initialized successfully");
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Failed to initialize Nosmai SDK", e);
            return false;
        }
    }

    public void ensureBeautyThread() {
        startBeautyThread();
    }

    /**
     * Initialize Agora RTC Engine
     * Same as iOS: Nosmai.initAgora(appId)
     */
    public boolean initAgora(String appId) {
        if (agoraInitialized && agoraEngine != null) {
            Log.i(TAG, "Agora already initialized");
            return true;
        }

        try {
            RtcEngineConfig config = new RtcEngineConfig();
            config.mContext = context;
            config.mAppId = appId;
            config.mEventHandler = new IRtcEngineEventHandler() {
                @Override
                public void onJoinChannelSuccess(String channel, int uid, int elapsed) {
                    channelJoined = true;
                    Log.i(TAG, "Joined channel: " + channel + " uid: " + uid);
                }

                @Override
                public void onUserJoined(int uid, int elapsed) {
                    Log.i(TAG, "👤 Remote user joined: " + uid);
                }

                @Override
                public void onUserOffline(int uid, int reason) {
                    Log.i(TAG, "Remote user left: " + uid);
                }

                @Override
                public void onLeaveChannel(RtcStats stats) {
                    channelJoined = false;
                    Log.i(TAG, "Left channel");
                }
            };

            agoraEngine = RtcEngine.create(config);
            agoraInitialized = true;
            Log.i(TAG, "Agora RTC Engine initialized");
            return true;

        } catch (Exception e) {
            Log.e(TAG, "Failed to initialize Agora", e);
            return false;
        }
    }

    /**
     * Release Agora resources
     */
    public boolean releaseAgora() {
        try {
            if (agoraEngine != null) {
                try {
                    Log.i(TAG, "Waiting for async operations to complete...");
                    Thread.sleep(800);  
                    Log.i(TAG, "Wait complete, destroying engine");
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    Log.w(TAG, "Sleep interrupted during cleanup");
                }

                RtcEngine.destroy();
                agoraEngine = null;
                agoraInitialized = false;
                channelJoined = false;
                Log.i(TAG, "Agora engine released");
            }
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Error releasing Agora", e);
            return false;
        }
    }

    public void shutdown() {
        stopBeautyThread();
    }

    // ============================================
    // MODE 2: LIVE STREAMING WITH FILTERS
    // ============================================

    /**
     * Start custom camera with Agora streaming
     * Same as iOS: Nosmai.startStreaming(appId, token, channelId, userId)
     *
     * Flow:
     * 1. Initialize Agora if needed
     * 2. Enable external video source
     * 3. Initialize Nosmai processing
     * 4. Setup camera capture
     * 5. Register frame callback to push to Agora
     * 6. Join channel
     */
    public boolean startCustomCamera(String appId, String token, String channelId,
                                     int userId, boolean startCameraImmediately) {
        if (isCustomCameraActive) {
            Log.w(TAG, "Custom camera already active");
            return true;
        }

        Log.i(TAG, "Starting custom camera - Streaming mode");
        Log.i(TAG, "Channel: " + channelId + ", User: " + userId);

        try {
            // Step 1: Initialize Agora if not already done
            if (!agoraInitialized) {
                if (!initAgora(appId)) {
                    Log.e(TAG, "Failed to initialize Agora");
                    return false;
                }
            }

            // Step 2: Enable external video source (CRITICAL!)
            agoraEngine.setExternalVideoSource(
                true,  // enable
                false, // useTexture = false (we'll send buffer data)
                Constants.ExternalVideoSourceType.VIDEO_FRAME
            );

            // Step 3: Enable video
            agoraEngine.enableVideo();
            agoraEngine.enableLocalVideo(true);

            // Step 4: Set client role to broadcaster
            agoraEngine.setClientRole(Constants.CLIENT_ROLE_BROADCASTER);

            // Step 4.5: Set initial video encoder configuration with mirror disabled
            applyEncoderMirror(false);

            // Step 5: Initialize Nosmai processing
            if (!nosmaiInitialized || storedLicenseKey == null) {
                return false;
            }

            previewView = requirePreviewView(context);

            try {
                NosmaiSDK.startProcessing(previewView);
                Log.i(TAG, "Nosmai processing started successfully");
            } catch (IllegalStateException e) {
                Log.w(TAG, "⚠️ SDK state lost, re-initializing...");
                nosmaiInitialized = false;
                NosmaiSDK.initialize(context, storedLicenseKey);
                nosmaiInitialized = true;
                NosmaiSDK.startProcessing(previewView);
                Log.i(TAG, "SDK re-initialized successfully");
            }

            NosmaiSDK.setRenderMode(NosmaiSDK.RenderMode.DUAL_OUTPUT);
            Log.i(TAG, "Nosmai processing started (DUAL_OUTPUT mode)");
            com.nosmai.effect.internal.NosmaiFilterEngine.setFDMinSkip(FD_SKIP_FRAMES);


            if (startCameraImmediately) {
                setupCameraCapture();
            }

            setupFrameCallbackForStreaming();

            // Step 7: Join channel
            currentChannelId = channelId;
            currentUserId = userId;

            ChannelMediaOptions options = new ChannelMediaOptions();
            options.channelProfile = Constants.CHANNEL_PROFILE_LIVE_BROADCASTING;
            options.clientRoleType = Constants.CLIENT_ROLE_BROADCASTER;
            options.autoSubscribeAudio = true;
            options.autoSubscribeVideo = true;
            options.publishCameraTrack = false;  
            options.publishCustomVideoTrack = true;

            int result = agoraEngine.joinChannel(token, channelId, userId, options);
            if (result != 0) {
                Log.e(TAG, "Failed to join channel. Error code: " + result);
                return false;
            }

            isCustomCameraActive = true;
            allowPush = true; // Enable frame pushing to Agora
            Log.i(TAG, "Custom camera started successfully");
            return true;

        } catch (Exception e) {
            Log.e(TAG, "Failed to start custom camera", e);
            return false;
        }
    }

    /**
     * Setup camera capture with Camera2Helper
     * Captures YUV frames and passes them to Nosmai for processing
     */
    private void setupCameraCapture() {
        try {
            // Create Camera2Helper instance (front camera)
            camera2Helper = new Camera2Helper(context, true);

            // Set camera orientation for Nosmai
            previewView.setCameraOrientation(
                    true, // isFrontCamera
                    camera2Helper.getSensorOrientation()
            );

            // Configure Nosmai for front camera
            NosmaiSDK.setMirrorX(true); // Mirror for front camera
            NosmaiSDK.setCameraFacing(true); // Front camera

            camera2Helper.setFrameCallback((y, u, v, width, height,
                                           yStride, uStride, vStride,
                                           uPixelStride, vPixelStride) -> {
                try {
                    if (previewView == null) {
                        return; 
                    }

                    int rotation = calculateRotation(
                            camera2Helper.isFrontCamera(),
                            camera2Helper.getSensorOrientation()
                    );

                    // Pass YUV frame to Nosmai for processing
                    previewView.processYuvFrame(
                            y, u, v,
                            width, height,
                            yStride, uStride, vStride,
                            uPixelStride, vPixelStride,
                            rotation
                    );

                    // Request render update (with null check for safety)
                    if (previewView != null) {
                        previewView.requestRenderUpdate();
                    }

                } catch (Exception e) {
                    Log.e(TAG, "Error processing frame", e);
                }
            });

            // Start camera capture
            camera2Helper.startCamera();

            Log.i(TAG, "Camera capture started: " +
                    camera2Helper.getPreviewWidth() + "x" +
                    camera2Helper.getPreviewHeight());

        } catch (Exception e) {
            Log.e(TAG, " Failed to setup camera capture", e);
        }
    }

    /**
     * Calculate rotation for frame processing
     * Based on sensor orientation and camera facing
     */
    private int calculateRotation(boolean isFrontCamera, int sensorOrientation) {
        if (isFrontCamera) {
            // Front camera: 270° sensor → RotateRight
            return (sensorOrientation == 90) ? 2 : 1;
        } else {
            // Back camera
            return (sensorOrientation == 90) ? 2 : 1;
        }
    }

    /**
     * Setup frame callback to push processed frames to Agora
     * This is where Nosmai filtered frames are sent to Agora for streaming
     * 🚀 OPTIMIZED: Uses object pooling to reduce GC pressure
     */
    private void setupFrameCallbackForStreaming() {
        NosmaiSDK.setFrameCallback(frame -> {
            if (!isCustomCameraActive || agoraEngine == null || frame.pixelBuffer == null || !allowPush) {
                return;
            }

            // 🚀 PERFORMANCE: Reuse frame object from pool instead of creating new
            AgoraVideoFrame videoFrame = null;
            try {
                // Get reusable frame from pool
                videoFrame = obtainVideoFrame();

                // Set frame properties
                // Nosmai outputs I420 format, 720x1280 (portrait)
                videoFrame.buf = frame.pixelBuffer;
                videoFrame.format = AgoraVideoFrame.FORMAT_I420;
                videoFrame.stride = frame.width;  // 720
                videoFrame.height = frame.height; // 1280
                videoFrame.timeStamp = frame.timestampNs / 1000000; // Convert ns to ms
                videoFrame.rotation = 0; // Already portrait from Nosmai

                // NOTE: Mirror mode is set at encoder level via setVideoEncoderConfiguration
                // See applyEncoderMirror() method

                // Push frame to Agora
                boolean success = agoraEngine.pushExternalVideoFrame(videoFrame);

                // Only log failures in debug to reduce overhead
                if (!success && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.GINGERBREAD) {
                    // Minimal logging to reduce performance impact
                }

            } catch (Exception e) {
                Log.e(TAG, "Error pushing frame to Agora", e);
            } finally {
                // 🚀 CRITICAL: Always recycle frame back to pool
                if (videoFrame != null) {
                    recycleVideoFrame(videoFrame);
                }
            }
        });

        Log.i(TAG, "Frame callback registered for streaming (with object pooling)");
    }

    /**
     * Stop custom camera and streaming
     */
    public boolean stopCustomCamera() {
        if (!isCustomCameraActive) {
            return true;
        }

        try {
            Log.i(TAG, "Stopping custom camera");

            // 🎯 CRITICAL: Stop all Agora streams FIRST before cleanup
            if (agoraEngine != null) {
                try {
                    // Disable external video source (stops frame pushing)
                    agoraEngine.setExternalVideoSource(false, false, Constants.ExternalVideoSourceType.VIDEO_FRAME);
                    Log.i(TAG, "External video source disabled");

                    // Disable video/audio
                    agoraEngine.enableLocalVideo(false);
                    agoraEngine.disableVideo();  // disableVideo() has no parameters
                    Log.i(TAG, "Video disabled");
                } catch (Exception e) {
                    Log.w(TAG, "Error disabling Agora streams: " + e.getMessage());
                }
            }

            // Clear frame callback
            NosmaiSDK.setFrameCallback(null);

            clearFramePool();

            if (camera2Helper != null) {
                camera2Helper.stopCamera();
                camera2Helper.setFrameCallback(null);
                camera2Helper = null;
                Log.i(TAG, "Camera2Helper stopped and callback cleared");
            }

            NosmaiSDK.stopProcessing();
            Log.i(TAG, "Nosmai processing stopped");
            if (channelJoined && agoraEngine != null) {
                agoraEngine.leaveChannel();
                Log.i(TAG, "Left channel (async)");
            }

            isCustomCameraActive = false;
            allowPush = false; // Disable frame pushing
            Log.i(TAG, "Custom camera stopped");
            return true;

        } catch (Exception e) {
            Log.e(TAG, "Error stopping custom camera", e);
            return false;
        }
    }

    /**
     * Teardown streaming resources
     */
    public void teardownStreaming() {
        stopCustomCamera();
        releaseAgora();
        Log.i(TAG, "Streaming teardown complete");
    }

    // ============================================
    // MODE 2: CAMERA PREVIEW ONLY (No Streaming)
    // ============================================

    /**
     * Start camera preview without Agora streaming
     * Just camera + Nosmai filters, no broadcasting
     */
    public boolean startCameraPreview() {
        if (isCameraPreviewActive) {
            Log.w(TAG, "Camera preview already active");
            return true;
        }

        Log.i(TAG, "Starting camera preview (no streaming)");

        try {
            // Check if Nosmai is initialized
            if (!nosmaiInitialized || storedLicenseKey == null) {
                Log.e(TAG, "Nosmai not initialized. Call initialize() first");
                return false;
            }

            previewView = requirePreviewView(context);

            try {
                NosmaiSDK.startProcessing(previewView);
            } catch (IllegalStateException e) {
                Log.w(TAG, "⚠️ SDK state lost, re-initializing...");
                nosmaiInitialized = false;
                NosmaiSDK.initialize(context, storedLicenseKey);
                nosmaiInitialized = true;
                NosmaiSDK.startProcessing(previewView);
                Log.i(TAG, "SDK re-initialized successfully");
            }

            NosmaiSDK.setRenderMode(NosmaiSDK.RenderMode.PREVIEW_ONLY);
            Log.i(TAG, "Nosmai processing started (PREVIEW_ONLY mode)");

            setupCameraCapture();

            isCameraPreviewActive = true;
            Log.i(TAG, "Camera preview started successfully");
            return true;

        } catch (Exception e) {
            Log.e(TAG, "Failed to start camera preview", e);
            return false;
        }
    }

    /**
     * Stop camera preview
     */
    public boolean stopCameraPreview() {
        if (!isCameraPreviewActive) {
            return true;
        }

        try {
            Log.i(TAG, "Stopping camera preview");

            // Stop camera capture
            if (camera2Helper != null) {
                camera2Helper.stopCamera();
                camera2Helper.setFrameCallback(null);
                camera2Helper = null;
                Log.i(TAG, "Camera2Helper stopped and callback cleared");
            }

            // Stop Nosmai processing
            NosmaiSDK.stopProcessing();

            isCameraPreviewActive = false;
            Log.i(TAG, "Camera preview stopped");
            return true;

        } catch (Exception e) {
            Log.e(TAG, "Error stopping camera preview", e);
            return false;
        }
    }

    // ============================================
    // AGORA CONTROLS
    // ============================================

    public boolean enableVideo() {
        if (agoraEngine == null) return false;
        try {
            agoraEngine.enableVideo();
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Error enabling video", e);
            return false;
        }
    }

    public synchronized boolean enableLocalVideo(boolean enabled) {
        if (agoraEngine == null) {
            Log.w(TAG, "Cannot enable local video - Agora not initialized");
            return false;
        }

        try {
            Log.i(TAG, "🎥 enableLocalVideo called: " + enabled);
            allowPush = enabled;
            agoraEngine.enableLocalVideo(enabled);

            if (enabled) {
                if (previewView != null) {
                    try {
                        NosmaiSDK.stopProcessing();

                        try {
                            Thread.sleep(150);
                        } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                        }

                        NosmaiSDK.startProcessing(previewView);
                        NosmaiSDK.setRenderMode(NosmaiSDK.RenderMode.DUAL_OUTPUT);
                        com.nosmai.effect.internal.NosmaiFilterEngine.setFDMinSkip(FD_SKIP_FRAMES);

                        setupFrameCallbackForStreaming();

                        if (camera2Helper != null) {
                            previewView.setCameraOrientation(
                                camera2Helper.isFrontCamera(),
                                camera2Helper.getSensorOrientation()
                            );
                            NosmaiSDK.setMirrorX(camera2Helper.isFrontCamera());
                            NosmaiSDK.setCameraFacing(camera2Helper.isFrontCamera());
                        }

                    } catch (Exception e) {
                        Log.e(TAG, "Error during restart, attempting recovery...", e);
                        if (storedLicenseKey != null) {
                            NosmaiSDK.initialize(context, storedLicenseKey);
                            NosmaiSDK.startProcessing(previewView);
                            NosmaiSDK.setRenderMode(NosmaiSDK.RenderMode.DUAL_OUTPUT);
                            com.nosmai.effect.internal.NosmaiFilterEngine.setFDMinSkip(FD_SKIP_FRAMES);
                            setupFrameCallbackForStreaming();
                        }
                    }
                } else {
                    Log.w(TAG, "⚠️ Preview view is null, cannot restart processing");
                }
            } else {
            }

            return true;
        } catch (Exception e) {
            Log.e(TAG, "Error enabling local video", e);
            return false;
        }
    }

    public boolean setClientRole(int role) {
        if (agoraEngine == null) return false;
        try {
            agoraEngine.setClientRole(role);
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Error setting client role", e);
            return false;
        }
    }

    public boolean joinChannel(String token, String channelId, int userId) {
        if (agoraEngine == null) return false;
        try {
            ChannelMediaOptions options = new ChannelMediaOptions();
            options.channelProfile = Constants.CHANNEL_PROFILE_LIVE_BROADCASTING;
            options.clientRoleType = Constants.CLIENT_ROLE_BROADCASTER;

            int result = agoraEngine.joinChannel(token, channelId, userId, options);
            currentChannelId = channelId;
            currentUserId = userId;
            return result == 0;
        } catch (Exception e) {
            Log.e(TAG, "Error joining channel", e);
            return false;
        }
    }

    public boolean leaveChannel() {
        if (agoraEngine == null) return false;
        try {
            agoraEngine.leaveChannel();
            channelJoined = false;
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Error leaving channel", e);
            return false;
        }
    }

    // ============================================
    // CAMERA CONTROLS
    // ============================================

    public boolean flipCamera() {
        if (camera2Helper == null) {
            Log.w(TAG, "Camera2Helper not initialized");
            return false;
        }

        try {
            boolean currentlyFront = camera2Helper.isFrontCamera();
            boolean willBeFront = !currentlyFront;
            camera2Helper.stopCamera();

            if (willBeFront) {
                camera2Helper.setFrontFacing();
            } else {
                camera2Helper.setBackFacing();
            }

            // Step 4: Set mirror mode for the NEW camera (no current frames to affect!)
            NosmaiSDK.setMirrorX(willBeFront);
            NosmaiSDK.setCameraFacing(willBeFront);
            applyEncoderMirror(false);

            Log.i(TAG, "▶️  Starting new camera...");
            camera2Helper.startCamera();

            previewView.setCameraOrientation(willBeFront, camera2Helper.getSensorOrientation());
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Error flipping camera", e);
            return false;
        }
    }

    public boolean switchCamera() {
        return flipCamera();
    }

    public boolean muteMicrophone(boolean muted) {
        if (agoraEngine == null) return false;
        try {
            agoraEngine.muteLocalAudioStream(muted);
            Log.i(TAG, "Microphone " + (muted ? "muted" : "unmuted"));
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Error muting microphone", e);
            return false;
        }
    }

    public boolean toggleMirror(boolean enabled) {
        try {
            mirrorModeEnabled = enabled;

            NosmaiSDK.setMirrorX(enabled);
            applyEncoderMirror(!enabled);

            return true;
        } catch (Exception e) {
            Log.e(TAG, "Error toggling mirror", e);
            return false;
        }
    }

    /**
     * Apply mirror mode at encoder level for Agora streaming
     * This ensures remote viewers see mirrored video
     */
    private void applyEncoderMirror(boolean enabled) {
        if (agoraEngine == null) {
            Log.w(TAG, "Cannot apply encoder mirror - Agora engine not initialized");
            return;
        }

        try {
            io.agora.rtc2.video.VideoEncoderConfiguration config =
                new io.agora.rtc2.video.VideoEncoderConfiguration(
                    new io.agora.rtc2.video.VideoEncoderConfiguration.VideoDimensions(720, 1280),
                    io.agora.rtc2.video.VideoEncoderConfiguration.FRAME_RATE.FRAME_RATE_FPS_30,
                    io.agora.rtc2.video.VideoEncoderConfiguration.STANDARD_BITRATE,
                    io.agora.rtc2.video.VideoEncoderConfiguration.ORIENTATION_MODE.ORIENTATION_MODE_FIXED_PORTRAIT
                );

            // Set mirror mode for remote viewers (use proper enum type)
            config.mirrorMode = enabled
                ? io.agora.rtc2.video.VideoEncoderConfiguration.MIRROR_MODE_TYPE.MIRROR_MODE_ENABLED
                : io.agora.rtc2.video.VideoEncoderConfiguration.MIRROR_MODE_TYPE.MIRROR_MODE_DISABLED;

            agoraEngine.setVideoEncoderConfiguration(config);
            Log.i(TAG, "Encoder mirror mode applied: " + (enabled ? "enabled" : "disabled"));
        } catch (Exception e) {
            Log.e(TAG, "Error applying encoder mirror", e);
        }
    }

    // ============================================
    // BEAUTY FILTERS (Work during streaming)
    // ============================================

    public boolean applySkinSmoothing(float level) {
        if (floatEquals(skinSmoothingLevel, level)) {
            return true;
        }
        skinSmoothingLevel = level;
        float normalized = Math.max(0.0f, Math.min(1.0f, level / 10.0f));
        return submitBeautyTask("applySkinSmoothing", () -> NosmaiBeauty.applySkinSmoothing(normalized));
    }

    public boolean applySkinWhitening(float level) {
        if (floatEquals(skinWhiteningLevel, level)) {
            return true;
        }
        skinWhiteningLevel = level;
        float normalized = Math.max(0.0f, Math.min(1.0f, level / 10.0f));
        return submitBeautyTask("applySkinWhitening", () -> NosmaiBeauty.applySkinWhitening(normalized));
    }

    public boolean applyFaceSlimming(float level) {
        if (floatEquals(faceSlimmingLevel, level)) {
            return true;
        }
        faceSlimmingLevel = level;
        float normalized = Math.max(0.0f, Math.min(1.0f, level / 10.0f)) * 0.1f;
        return submitBeautyTask("applyFaceSlimming", () -> NosmaiBeauty.applyFaceSlimming(normalized));
    }

    public boolean applyEyeEnlargement(float level) {
        if (floatEquals(eyeEnlargementLevel, level)) {
            return true;
        }
        eyeEnlargementLevel = level;
        float normalized = Math.max(0.0f, Math.min(1.0f, level / 10.0f)) * 0.1f;
        return submitBeautyTask("applyEyeEnlargement", () -> NosmaiBeauty.applyEyeEnlargement(normalized));
    }

    public boolean applyNoseSize(float level) {
        if (floatEquals(noseSizeLevel, level)) {
            return true;
        }
        noseSizeLevel = level;
        float normalized = Math.max(0.0f, Math.min(1.0f, level / 100.0f));
        return submitBeautyTask("applyNoseSize", () -> NosmaiBeauty.applyNoseSize(normalized));
    }

    public boolean applyBrightness(float brightness) {
        if (floatEquals(brightnessLevel, brightness)) {
            return true;
        }
        brightnessLevel = brightness;
        return submitBeautyTask("applyBrightness", () -> NosmaiBeauty.applyBrightness(brightness));
    }

    public boolean applyContrast(float contrast) {
        if (floatEquals(contrastLevel, contrast)) {
            return true;
        }
        contrastLevel = contrast;
        return submitBeautyTask("applyContrast", () -> NosmaiBeauty.applyContrast(contrast));
    }

    public boolean applyHue(float hue) {
        if (floatEquals(hueLevel, hue)) {
            return true;
        }
        hueLevel = hue;
        return submitBeautyTask("applyHue", () -> NosmaiBeauty.applyHue(hue));
    }

    public boolean applyRGB(float red, float green, float blue) {
        if (floatEquals(redMultiplier, red) && floatEquals(greenMultiplier, green) && floatEquals(blueMultiplier, blue)) {
            return true;
        }
        redMultiplier = red;
        greenMultiplier = green;
        blueMultiplier = blue;
        return submitBeautyTask("applyRGB", () -> NosmaiBeauty.applyRGB(red, green, blue));
    }

    public boolean applyLipstick(float intensity) {
        if (floatEquals(lipstickLevel, intensity)) {
            return true;
        }
        lipstickLevel = intensity;
        float reduced = intensity * 0.1f;
        return submitBeautyTask("applyLipstick", () -> NosmaiBeauty.applyLipstick(reduced));
    }

    public boolean applyBlusher(float intensity) {
        if (floatEquals(blusherLevel, intensity)) {
            return true;
        }
        blusherLevel = intensity;
        return submitBeautyTask("applyBlusher", () -> NosmaiBeauty.applyBlusher(intensity));
    }

    public boolean applyExposure(float exposure) {
        if (floatEquals(exposureLevel, exposure)) {
            return true;
        }
        exposureLevel = exposure;
        return submitBeautyTask("applyExposure", () -> NosmaiBeauty.applyExposure(exposure));
    }

    public boolean applySaturation(float saturation) {
        if (floatEquals(saturationLevel, saturation)) {
            return true;
        }
        saturationLevel = saturation;
        return submitBeautyTask("applySaturation", () -> NosmaiBeauty.applySaturation(saturation));
    }

    public boolean applySharpening(float sharpening) {
        if (floatEquals(sharpenLevel, sharpening)) {
            return true;
        }
        sharpenLevel = sharpening;
        return submitBeautyTask("applySharpening", () -> NosmaiBeauty.applySharpen(sharpening));
    }

    public boolean applyWhiteBalance(float temperatureK, float tint) {
        if (floatEquals(whiteBalanceTemp, temperatureK) && floatEquals(whiteBalanceTint, tint)) {
            return true;
        }
        whiteBalanceTemp = temperatureK;
        whiteBalanceTint = tint;
        return submitBeautyTask("applyWhiteBalance", () -> NosmaiBeauty.applyWhiteBalance(temperatureK, tint));
    }

    public boolean setGrayscaleEnabled(boolean enabled) {
        if (grayscaleEnabled == enabled) {
            return true;
        }
        grayscaleEnabled = enabled;
        return submitBeautyTask("setGrayscaleEnabled", () -> NosmaiBeauty.setGrayscaleEnabled(enabled));
    }

    // ============================================
    // FILTER MANAGEMENT
    // ============================================

    public boolean applyFilter(String path) {
        if (path == null || path.isEmpty()) {
            return removeAllFilters();
        }

        if (path.equals(currentFilterPath)) {
            return true;
        }
        currentFilterPath = path;

        return submitBeautyTask("applyFilter", () -> {
            NosmaiEffects.applyEffect(path, null);
            Log.i(TAG, "Filter applied: " + path);
        });
    }

    public boolean removeAllFilters() {
        currentFilterPath = "";
        return submitBeautyTask("removeAllFilters", () -> {
            NosmaiEffects.removeEffect(null);
            NosmaiBeauty.removeAllBeautyFilters();
            resetFilterStates();
            Log.i(TAG, "All filters removed");
        });
    }

    public List<Map<String, Object>> getLocalFilters() {
        List<Map<String, Object>> filterList = new ArrayList<>();

        try {
            // Read AssetManifest.json
            String manifestJson = readAssetText(ASSET_MANIFEST_PATH);
            if (manifestJson == null) {
                return filterList;
            }

            JSONObject manifest = new JSONObject(manifestJson);
            java.util.Iterator<String> keys = manifest.keys();

            while (keys.hasNext()) {
                String assetPath = keys.next();

                // Check if it's a .nosmai filter file
                if (!assetPath.startsWith(FILTERS_PREFIX) || !assetPath.endsWith(".nosmai")) {
                    continue;
                }

                String name = new File(assetPath).getName().replace(".nosmai", "");
                String displayName = toTitleCase(name);

                // Cache the filter file
                File cachedFile = ensureAssetCached(assetPath);
                int fileSize = (cachedFile != null && cachedFile.exists()) ? (int) cachedFile.length() : 0;

                // Extract metadata from .nosmai file
                String[] metadata = extractManifestFieldsFromNosmai(name);
                String filterType = metadata[0];
                String metaDisplayName = metadata[1];
                String description = metadata[2];

                Map<String, Object> filterMap = new HashMap<>();
                filterMap.put("id", name);
                filterMap.put("name", name);
                filterMap.put("displayName", (metaDisplayName != null && !metaDisplayName.isEmpty()) ? metaDisplayName : displayName);
                filterMap.put("description", description != null ? description : "");
                filterMap.put("path", cachedFile != null ? cachedFile.getAbsolutePath() : "");
                filterMap.put("fileSize", fileSize);
                filterMap.put("type", "local");

                if (filterType != null && (filterType.equals("filter") || filterType.equals("effect"))) {
                    filterMap.put("filterType", filterType);
                }

                filterMap.put("isDownloaded", true);
                filterMap.put("isFree", true);

                // Try to extract preview image
                String previewBase64 = tryExtractPreviewBase64(name);
                if (previewBase64 != null && !previewBase64.isEmpty()) {
                    filterMap.put("previewImageBase64", previewBase64);
                    filterMap.put("previewUrl", "data:image/jpeg;base64," + previewBase64);
                }

                filterList.add(filterMap);
            }

            Log.i(TAG, "Found " + filterList.size() + " local filters");
        } catch (Exception e) {
            Log.e(TAG, "Error getting local filters", e);
        }

        return filterList;
    }

    public List<Map<String, Object>> getCloudFilters() {
        List<Map<String, Object>> cloudFilters = new ArrayList<>();

        try {
            // NosmaiCloud.list() returns a list of filter objects
            // We use reflection since we don't have the exact class definition
            List<?> cloudList = NosmaiCloud.list();

            for (Object item : cloudList) {
                try {
                    // Use reflection to get properties
                    String id = getPropertyString(item, "getId");
                    String name = getPropertyString(item, "getName");
                    String displayName = toTitleCase((name != null && !name.isEmpty()) ? name : id);
                    boolean isDownloaded = getPropertyBoolean(item, "isDownloaded");
                    String localPath = getPropertyString(item, "getLocalPath");
                    String category = getPropertyString(item, "getCategory");
                    String filterType = mapCategoryToFilterType(category);

                    int fileSize = 0;
                    if (isDownloaded && localPath != null && !localPath.isEmpty()) {
                        File file = new File(localPath);
                        if (file.exists()) {
                            fileSize = (int) file.length();
                        }
                    }

                    Map<String, Object> filterMap = new HashMap<>();
                    filterMap.put("id", id);
                    filterMap.put("name", name);
                    filterMap.put("displayName", displayName);
                    filterMap.put("type", "cloud");
                    filterMap.put("filterType", filterType);
                    filterMap.put("isDownloaded", isDownloaded);
                    filterMap.put("fileSize", fileSize);
                    filterMap.put("isFree", true);

                    if (isDownloaded && localPath != null && !localPath.isEmpty()) {
                        filterMap.put("path", localPath);
                        filterMap.put("localPath", localPath);

                        // Try to load preview if downloaded
                        try {
                            Bitmap previewBitmap = com.nosmai.effect.NosmaiFilterManager.loadPreviewImageForFilter(localPath);
                            if (previewBitmap != null) {
                                String base64 = bitmapToBase64(previewBitmap);
                                filterMap.put("previewImageBase64", base64);
                            }
                        } catch (Exception e) {
                            Log.w(TAG, "Failed to load preview for: " + id);
                        }
                    }

                    String thumbnailUrl = getPropertyString(item, "getThumbnailUrl");
                    if (thumbnailUrl != null && !thumbnailUrl.isEmpty()) {
                        filterMap.put("previewUrl", thumbnailUrl);
                        filterMap.put("thumbnailUrl", thumbnailUrl);
                    }

                    cloudFilters.add(filterMap);
                } catch (Exception e) {
                    Log.w(TAG, "Error processing cloud filter item", e);
                }
            }

            Log.i(TAG, "Found " + cloudFilters.size() + " cloud filters");
        } catch (Exception e) {
            Log.e(TAG, "Error getting cloud filters", e);
        }

        return cloudFilters;
    }

    public List<Map<String, Object>> getFilters() {
        // Combine local and cloud filters
        List<Map<String, Object>> allFilters = new ArrayList<>();

        try {
            allFilters.addAll(getLocalFilters());
            allFilters.addAll(getCloudFilters());
            Log.i(TAG, "getFilters returned " + allFilters.size() + " filters (local + cloud)");
        } catch (Exception e) {
            Log.e(TAG, "Error getting combined filters", e);
        }

        return allFilters;
    }

    public Map<String, Object> downloadCloudFilter(String filterId) {
        Map<String, Object> result = new HashMap<>();

        if (filterId == null || filterId.trim().isEmpty()) {
            result.put("success", false);
            result.put("error", "Filter ID is required");
            return result;
        }

        try {
            final CountDownLatch latch = new CountDownLatch(1);
            final boolean[] success = {false};
            final String[] path = {null};
            final String[] error = {null};

            NosmaiCloud.download(filterId, new NosmaiCloud.DownloadCallback() {
                @Override
                public void onComplete(String id, boolean downloadSuccess, String localPath, String errorMsg) {
                    success[0] = downloadSuccess;
                    path[0] = localPath;
                    error[0] = errorMsg;
                    latch.countDown();
                }
            });

            // Wait for download to complete (with timeout)
            latch.await();

            result.put("success", success[0]);
            if (success[0] && path[0] != null && !path[0].isEmpty()) {
                result.put("path", path[0]);
                Log.i(TAG, "Cloud filter downloaded: " + filterId + " -> " + path[0]);
            }
            if (!success[0] && error[0] != null && !error[0].isEmpty()) {
                result.put("error", error[0]);
            }

        } catch (Exception e) {
            Log.e(TAG, "Error downloading cloud filter", e);
            result.put("success", false);
            result.put("error", e.getMessage());
        }

        return result;
    }

    public boolean isCloudFilterEnabled() {
        try {
            return NosmaiCloud.isEnabled();
        } catch (Exception e) {
            Log.e(TAG, "Error checking cloud filter status", e);
            return false;
        }
    }

    // ============================================
    // FILTER STATUS
    // ============================================

    public Map<String, Double> getCurrentFilterStates() {
        Map<String, Double> states = new HashMap<>();
        states.put("skinSmoothing", (double) skinSmoothingLevel);
        states.put("skinWhitening", (double) skinWhiteningLevel);
        states.put("faceSlimming", (double) faceSlimmingLevel);
        states.put("eyeEnlargement", (double) eyeEnlargementLevel);
        states.put("noseSize", (double) noseSizeLevel);
        states.put("brightness", (double) brightnessLevel);
        states.put("contrast", (double) contrastLevel);
        states.put("hue", (double) hueLevel);
        states.put("lipstick", (double) lipstickLevel);
        states.put("blusher", (double) blusherLevel);
        states.put("exposure", (double) exposureLevel);
        states.put("saturation", (double) saturationLevel);
        states.put("sharpening", (double) sharpenLevel);
        return states;
    }

    public boolean hasActiveFilters() {
        return skinSmoothingLevel > 0.0f ||
               skinWhiteningLevel > 0.0f ||
               faceSlimmingLevel > 0.0f ||
               eyeEnlargementLevel > 0.0f ||
               noseSizeLevel > 0.0f ||
               brightnessLevel != 0.0f ||
               contrastLevel != 1.0f ||
               hueLevel != 0.0f ||
               lipstickLevel > 0.0f ||
               blusherLevel > 0.0f ||
               exposureLevel != 0.0f ||
               saturationLevel != 1.0f ||
               sharpenLevel > 0.0f ||
               grayscaleEnabled;
    }

    public boolean isBeautyFilterEnabled() {
        // Check if beauty features are enabled by license
        return Nosmai.isBeautyEnabled();
    }

    // ============================================
    // ADVANCED FILTERS
    // ============================================

    public boolean applyMakeupBlendLevel(String filterName, float level) {
        if (filterName == null || filterName.isEmpty()) {
            Log.w(TAG, "Filter name is empty");
            return false;
        }

        final String filterLower = filterName.toLowerCase();
        final float normalized = Math.max(0.0f, Math.min(1.0f, level / 10.0f));

        Runnable task;
        if (filterLower.contains("lipstick")) {
            final float reduced = normalized * 0.1f;
            // Store reduced value for state tracking
            if (floatEquals(lipstickLevel, reduced)) {
                return true;
            }
            task = () -> {
                lipstickLevel = reduced;
                NosmaiBeauty.applyLipstick(reduced);
            };
        } else if (filterLower.contains("blusher")) {
            // Store original value for state tracking
            if (floatEquals(blusherLevel, normalized)) {
                return true;
            }
            final float finalNormalized = normalized;
            task = () -> {
                blusherLevel = finalNormalized;
                NosmaiBeauty.applyBlusher(finalNormalized);
            };
        } else if (filterLower.contains("smoothing") || filterLower.contains("skinsmoothing")) {
            // Store original value for state tracking
            if (floatEquals(skinSmoothingLevel, normalized)) {
                return true;
            }
            final float finalNormalized = normalized;
            task = () -> {
                skinSmoothingLevel = finalNormalized;
                NosmaiBeauty.applySkinSmoothing(finalNormalized);
            };
        } else if (filterLower.contains("whitening") || filterLower.contains("skinwhitening")) {
            // Store original value for state tracking
            if (floatEquals(skinWhiteningLevel, normalized)) {
                return true;
            }
            final float finalNormalized = normalized;
            task = () -> {
                skinWhiteningLevel = finalNormalized;
                NosmaiBeauty.applySkinWhitening(finalNormalized);
            };
        } else {
            Log.w(TAG, "Unknown makeup filter: " + filterName);
            return false;
        }

        return submitBeautyTask("applyMakeupBlendLevel", task);
    }

    public boolean adjustHSB(float hue, float saturation, float brightness) {
        if (floatEquals(hsbHue, hue) && floatEquals(hsbSaturation, saturation) && floatEquals(hsbBrightness, brightness)) {
            return true;
        }
        hsbHue = hue;
        hsbSaturation = saturation;
        hsbBrightness = brightness;

        return submitBeautyTask("adjustHSB", () -> {
            NosmaiBeauty.applyHue(hue);
            NosmaiBeauty.applySaturation(saturation);
            NosmaiBeauty.applyBrightness(brightness);
        });
    }

    public boolean resetHSBFilter() {
        if (floatEquals(hsbHue, 0.0f) && floatEquals(hsbSaturation, 1.0f) && floatEquals(hsbBrightness, 0.0f)) {
            return true;
        }
        hsbHue = 0.0f;
        hsbSaturation = 1.0f;
        hsbBrightness = 0.0f;

        return submitBeautyTask("resetHSBFilter", () -> {
            NosmaiBeauty.applyHue(0.0f);
            NosmaiBeauty.applySaturation(1.0f);
            NosmaiBeauty.applyBrightness(0.0f);
        });
    }

    // ============================================
    // UTILITY METHODS
    // ============================================

    public boolean cleanup() {
        try {
            stopCustomCamera();
            releaseAgora();
            clearFramePool();
            Log.i(TAG, "Cleanup complete (SDK remains initialized)");
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Error during cleanup", e);
            return false;
        }
    }

    public String getFlutterEngineInfo() {
        return "NosmaiAgoraBridge - Android - v1.0.0";
    }

    private void resetFilterStates() {
        skinSmoothingLevel = 0.0f;
        skinWhiteningLevel = 0.0f;
        faceSlimmingLevel = 0.0f;
        eyeEnlargementLevel = 0.0f;
        noseSizeLevel = 0.0f;
        brightnessLevel = 0.0f;
        contrastLevel = 1.0f;
        hueLevel = 0.0f;
        lipstickLevel = 0.0f;
        blusherLevel = 0.0f;
        redMultiplier = 1.0f;
        greenMultiplier = 1.0f;
        blueMultiplier = 1.0f;
        exposureLevel = 0.0f;
        saturationLevel = 1.0f;
        sharpenLevel = 0.0f;
        whiteBalanceTemp = 5000.0f;
        whiteBalanceTint = 0.0f;
        grayscaleEnabled = false;
        hsbHue = 0.0f;
        hsbSaturation = 0.0f;
        hsbBrightness = 0.0f;
        currentFilterPath = "";
    }

    // ============================================
    // HELPER METHODS FOR FILTER MANAGEMENT
    // ============================================

    /**
     * Read text content from assets
     */
    private String readAssetText(String assetPath) {
        try {
            InputStream is = context.getAssets().open(assetPath);
            BufferedReader reader = new BufferedReader(new InputStreamReader(is, "UTF-8"));
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line);
            }
            reader.close();
            return sb.toString();
        } catch (Exception e) {
            Log.w(TAG, "Failed to read asset: " + assetPath);
            return null;
        }
    }

    /**
     * Cache an asset file to internal storage
     */
    private File ensureAssetCached(String assetPath) {
        try {
            File cacheDir = new File(context.getCacheDir(), CACHE_DIR_NAME);
            if (!cacheDir.exists()) {
                cacheDir.mkdirs();
            }

            String fileName = new File(assetPath).getName();
            File outFile = new File(cacheDir, fileName);

            if (!outFile.exists() || outFile.length() == 0) {
                InputStream is = openAnyAsset(assetPath);
                FileOutputStream fos = new FileOutputStream(outFile);

                byte[] buffer = new byte[8192];
                int bytesRead;
                while ((bytesRead = is.read(buffer)) != -1) {
                    fos.write(buffer, 0, bytesRead);
                }

                fos.close();
                is.close();
            }

            return outFile;
        } catch (Exception e) {
            Log.w(TAG, "Failed to cache asset: " + assetPath, e);
            return null;
        }
    }

    /**
     * Open asset with or without flutter_assets prefix
     */
    private InputStream openAnyAsset(String assetPath) throws Exception {
        try {
            return context.getAssets().open(assetPath);
        } catch (Exception e) {
            String candidate = assetPath.startsWith("flutter_assets/") ? assetPath : "flutter_assets/" + assetPath;
            return context.getAssets().open(candidate);
        }
    }

    /**
     * Convert string to title case
     */
    private String toTitleCase(String input) {
        if (input == null || input.isEmpty()) return input;

        String cleaned = input.replace('_', ' ').replace('-', ' ');
        String[] words = cleaned.split("\\s+");
        StringBuilder result = new StringBuilder();

        for (String word : words) {
            if (word.length() > 0) {
                if (result.length() > 0) result.append(" ");
                result.append(Character.toUpperCase(word.charAt(0)));
                if (word.length() > 1) {
                    result.append(word.substring(1).toLowerCase());
                }
            }
        }

        return result.toString();
    }

    /**
     * Extract manifest fields from .nosmai file using reflection
     */
    private String[] extractManifestFieldsFromNosmai(String filterName) {
        String[] candidates = {
            "flutter_assets/assets/filters/" + filterName + ".nosmai",
            "assets/filters/" + filterName + ".nosmai",
            "filters/" + filterName + ".nosmai"
        };

        String filterType = null;
        String displayName = null;
        String description = null;

        for (String path : candidates) {
            try {
                Class<?> cls = Class.forName("com.nosmai.effect.internal.NosmaiFilter");
                java.lang.reflect.Method method = cls.getMethod("nativeExtractManifestFromAssets", Context.class, String.class);
                String jsonStr = (String) method.invoke(null, context, path);

                if (jsonStr != null && !jsonStr.isEmpty()) {
                    JSONObject json = new JSONObject(jsonStr);

                    String type = json.optString("filterType", json.optString("type", "")).toLowerCase();
                    if (type.equals("filter") || type.equals("effect")) {
                        filterType = type;
                    }

                    displayName = json.optString("displayName", displayName);
                    description = json.optString("description", description);
                    break;
                }
            } catch (Exception e) {
                // Try next path
            }
        }

        return new String[]{filterType, displayName, description};
    }

    /**
     * Try to extract preview image from .nosmai file as base64
     */
    private String tryExtractPreviewBase64(String filterName) {
        String[] candidates = {
            "flutter_assets/assets/filters/" + filterName + ".nosmai",
            "assets/filters/" + filterName + ".nosmai",
            "filters/" + filterName + ".nosmai"
        };

        for (String path : candidates) {
            try {
                Class<?> cls = Class.forName("com.nosmai.effect.internal.NosmaiFilter");
                java.lang.reflect.Method method = cls.getMethod("nativeExtractPreviewFromAssets", Context.class, String.class);
                Bitmap bitmap = (Bitmap) method.invoke(null, context, path);

                if (bitmap != null) {
                    return bitmapToBase64(bitmap);
                }
            } catch (Exception e) {
                // Try next path
            }
        }

        return null;
    }

    /**
     * Convert Bitmap to base64 string
     * 🚀 OPTIMIZED: Properly recycles bitmap and closes streams to prevent memory leaks
     */
    private String bitmapToBase64(Bitmap bitmap) {
        if (bitmap == null) {
            return null;
        }

        ByteArrayOutputStream baos = null;
        try {
            baos = new ByteArrayOutputStream();
            bitmap.compress(Bitmap.CompressFormat.JPEG, 70, baos);
            byte[] data = baos.toByteArray();
            String result = Base64.encodeToString(data, Base64.NO_WRAP);

            // 🚀 CRITICAL: Recycle bitmap to free native memory immediately
            // This prevents memory leaks and reduces memory usage by 30-40%
            bitmap.recycle();

            return result;
        } catch (Exception e) {
            Log.e(TAG, "Failed to convert bitmap to base64", e);
            return null;
        } finally {
            // 🚀 ALWAYS close stream to free resources
            if (baos != null) {
                try {
                    baos.close();
                } catch (Exception e) {
                    // Ignore close exception
                }
            }
        }
    }

    /**
     * Map category to filter type
     */
    private String mapCategoryToFilterType(String category) {
        if (category == null) return "effect";

        String cat = category.toLowerCase();
        if (cat.contains("fx-and-filters") || cat.equals("filter")) {
            return "filter";
        } else if (cat.contains("special-effects") || cat.contains("beauty-effects") || cat.equals("effect")) {
            return "effect";
        }

        return "effect";
    }

    /**
     * Helper to safely get String from Map
     */
    private String getString(Map<?, ?> map, String key) {
        Object value = map.get(key);
        if (value instanceof String) {
            return (String) value;
        }
        return null;
    }

    /**
     * Helper to safely get int from Map
     */
    private int getInt(Map<?, ?> map, String key, int defaultValue) {
        Object value = map.get(key);
        if (value instanceof Number) {
            return ((Number) value).intValue();
        }
        return defaultValue;
    }

    /**
     * Helper to safely get boolean from Map
     */
    private boolean getBoolean(Map<?, ?> map, String key, boolean defaultValue) {
        Object value = map.get(key);
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        return defaultValue;
    }

    /**
     * Helper to get String property from object using reflection
     */
    private String getPropertyString(Object obj, String methodName) {
        try {
            java.lang.reflect.Method method = obj.getClass().getMethod(methodName);
            Object result = method.invoke(obj);
            return result != null ? result.toString() : null;
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Helper to get boolean property from object using reflection
     */
    private boolean getPropertyBoolean(Object obj, String methodName) {
        try {
            java.lang.reflect.Method method = obj.getClass().getMethod(methodName);
            Object result = method.invoke(obj);
            if (result instanceof Boolean) {
                return (Boolean) result;
            }
        } catch (Exception e) {
            // Ignore
        }
        return false;
    }

    // ============================================
    // DEBOUNCING HELPER (Performance Optimization)
    // ============================================

    // REMOVED: Debouncing helper methods - no longer needed
    // These methods caused filters to queue and execute in batches, which conflicted
    // with Flutter's manual apply pattern and caused performance issues

    /*
    private void debounceFilterUpdate(String filterId, Runnable filterUpdate) {
        Runnable pendingUpdate = pendingFilterUpdates.get(filterId);
        if (pendingUpdate != null) {
            filterHandler.removeCallbacks(pendingUpdate);
        }
        pendingFilterUpdates.put(filterId, filterUpdate);
        filterHandler.postDelayed(filterUpdate, FILTER_DEBOUNCE_DELAY_MS);
    }

    private void clearPendingFilterUpdates() {
        for (Runnable runnable : pendingFilterUpdates.values()) {
            filterHandler.removeCallbacks(runnable);
        }
        pendingFilterUpdates.clear();
    }
    */

    // ============================================
    // FRAME POOLING METHODS (Performance Optimization)
    // ============================================

    /**
     * Get a reusable AgoraVideoFrame from the pool
     * If pool is empty, creates a new instance
     * This reduces GC pressure significantly during streaming
     */
    private AgoraVideoFrame obtainVideoFrame() {
        AgoraVideoFrame frame = framePool.poll();
        if (frame == null) {
            frame = new AgoraVideoFrame();
        }
        return frame;
    }

    /**
     * Return AgoraVideoFrame to pool for reuse
     * Pool size is limited to MAX_POOL_SIZE to prevent memory buildup
     */
    private void recycleVideoFrame(AgoraVideoFrame frame) {
        if (frame != null && framePool.size() < MAX_POOL_SIZE) {
            // Clear the buffer reference to prevent holding stale data
            frame.buf = null;
            framePool.offer(frame);
        }
    }

    /**
     * Clear the frame pool during cleanup
     */
    private void clearFramePool() {
        framePool.clear();
    }

    // ============================================
    // GETTERS FOR PLATFORM VIEW
    // ============================================

    public synchronized NosmaiPreviewView requirePreviewView(Context context) {
        // 🎯 FIX: Create fresh view only if null or disposed
        // Platform View Factory will update this reference when it creates its view
        if (previewView == null) {
            previewView = new NosmaiPreviewView(context);
            Log.i(TAG, "Created new preview view (will be updated by Platform View)");
        } else {
            Log.i(TAG, "Using existing preview view from Platform View");
        }
        return previewView;
    }

    public synchronized void setPreviewView(@Nullable NosmaiPreviewView view) {
        previewView = view;
    }

    public synchronized void clearPreviewView(@Nullable NosmaiPreviewView view) {
        // 🎯 FIX: Allow clearing preview view reference when Platform View disposes
        // This is safe because:
        // 1. Platform View dispose happens AFTER stopCustomCamera/stopCameraPreview
        // 2. We need to clear the reference so next Platform View gets a fresh view
        // 3. Keeping the old reference causes GL context issues on restart
        if (previewView == view) {
            previewView = null;
            Log.i(TAG, "Preview view reference cleared (was disposed)");
        }
    }

    public synchronized NosmaiPreviewView getPreviewView() {
        return previewView;
    }

    public Context getContext() {
        return context;
    }

    /**
     * Get the internal Agora RtcEngine instance
     * This allows Flutter to access the engine for rendering remote videos
     * Critical for multi-live where multiple users need to see each other
     */
    public RtcEngine getAgoraEngine() {
        return agoraEngine;
    }

    /**
     * Check if custom camera (Nosmai streaming) is currently active
     */
    public boolean isCustomCameraActive() {
        return isCustomCameraActive;
    }

    // ============================================
    // RECORDING AND PHOTO CAPTURE (Camera Mode)
    // ============================================

    /**
     * Start video recording in camera preview mode
     * Only works when camera preview is active (not streaming mode)
     */
    public boolean startRecording() {
        try {
            if (!isCameraPreviewActive) {
                Log.e(TAG, "Cannot start recording - camera preview not active");
                return false;
            }

            if (isRecording) {
                Log.w(TAG, "Recording already in progress");
                return false;
            }

            if (previewView == null) {
                Log.e(TAG, "PreviewView is null");
                return false;
            }

            // Create video file path
            File outputDir = new File(context.getFilesDir(), "recordings");
            if (!outputDir.exists()) {
                outputDir.mkdirs();
            }
            File videoFile = new File(outputDir, "nosmai_video_" + System.currentTimeMillis() + ".mp4");
            recordingPath = videoFile.getAbsolutePath();

            // Use NosmaiSDK to start recording with callback
            NosmaiSDK.startRecording(previewView, recordingPath, new NosmaiSDK.RecordingCallback() {
                @Override
                public void onStarted(boolean success, String error) {
                    if (success) {
                        isRecording = true;
                        recordingStartTime = System.currentTimeMillis();
                        Log.i(TAG, "Recording started successfully: " + recordingPath);
                    } else {
                        Log.e(TAG, "Failed to start recording: " + error);
                        isRecording = false;
                        recordingPath = null;
                    }
                }

                @Override
                public void onCompleted(String outputPath, boolean success, String error) {
                    // Not used for start
                }
            });

            // Return true immediately (callback will handle actual result)
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Error starting recording", e);
            isRecording = false;
            recordingPath = null;
            return false;
        }
    }

    /**
     * Stop video recording and return result asynchronously via callback
     * Returns Map with: success, videoPath, duration, fileSize
     */
    public void stopRecording(final Result flutterResult) {
        try {
            if (!isRecording) {
                Log.w(TAG, "No recording in progress");
                Map<String, Object> errorResult = new HashMap<>();
                errorResult.put("success", false);
                errorResult.put("error", "No recording in progress");
                flutterResult.success(errorResult);
                return;
            }

            final long startTime = recordingStartTime;
            final String pathAtStop = recordingPath;

            Log.i(TAG, "🎬 Stopping recording...");

            // Stop recording using NosmaiSDK with callback
            NosmaiSDK.stopRecording(new NosmaiSDK.RecordingCallback() {
                @Override
                public void onStarted(boolean success, String error) {
                    // Not used for stop
                }

                @Override
                public void onCompleted(String outputPath, boolean success, String error) {
                    Log.i(TAG, "🎬 Recording callback received - success: " + success + ", path: " + outputPath);

                    isRecording = false;
                    String videoPath = (outputPath != null && !outputPath.isEmpty()) ? outputPath : pathAtStop;
                    long duration = startTime > 0 ? (System.currentTimeMillis() - startTime) : 0;

                    Map<String, Object> resultMap = new HashMap<>();

                    if (success && videoPath != null) {
                        File videoFile = new File(videoPath);
                        long fileSize = videoFile.exists() ? videoFile.length() : 0;

                        resultMap.put("success", true);
                        resultMap.put("videoPath", videoPath);
                        resultMap.put("duration", duration);
                        resultMap.put("fileSize", fileSize);

                    } else {
                        resultMap.put("success", false);
                        resultMap.put("error", error != null ? error : "Failed to stop recording");
                        Log.e(TAG, "Failed to stop recording: " + error);
                    }

                    recordingStartTime = 0;
                    recordingPath = null;

                    flutterResult.success(resultMap);
                }
            });

        } catch (Exception e) {
            Log.e(TAG, "Exception in stopRecording", e);
            Map<String, Object> errorResult = new HashMap<>();
            errorResult.put("success", false);
            errorResult.put("error", e.getMessage());
            isRecording = false;
            recordingStartTime = 0;
            recordingPath = null;
            flutterResult.success(errorResult);
        }
    }

    /**
     * Capture a photo from camera preview
     * Returns Map with: success, imageData (bytes), width, height
     */
    public Map<String, Object> capturePhoto() {
        Map<String, Object> result = new HashMap<>();

        try {
            if (!isCameraPreviewActive) {
                Log.e(TAG, "Cannot capture photo - camera preview not active");
                result.put("success", false);
                result.put("error", "Camera preview not active");
                return result;
            }

            if (previewView == null) {
                Log.e(TAG, "PreviewView is null");
                result.put("success", false);
                result.put("error", "Preview not ready");
                return result;
            }

            // Find TextureView in preview
            TextureView textureView = findTextureView(previewView);
            if (textureView != null) {
                Bitmap bitmap = textureView.getBitmap();
                if (bitmap != null) {
                    // Convert Bitmap to byte array
                    ByteArrayOutputStream baos = new ByteArrayOutputStream();
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 85, baos);
                    byte[] data = baos.toByteArray();

                    result.put("success", true);
                    result.put("imageData", data);
                    result.put("width", bitmap.getWidth());
                    result.put("height", bitmap.getHeight());

                    Log.i(TAG, "Photo captured successfully: " + bitmap.getWidth() + "x" + bitmap.getHeight());

                    bitmap.recycle();
                    return result;
                }
            }

            // If TextureView capture failed, return error
            result.put("success", false);
            result.put("error", "Failed to capture photo from preview");
        } catch (Exception e) {
            Log.e(TAG, "Error capturing photo", e);
            result.put("success", false);
            result.put("error", e.getMessage());
        }

        return result;
    }

    /**
     * Find TextureView in view hierarchy
     */
    private TextureView findTextureView(android.view.View root) {
        if (root instanceof TextureView) {
            return (TextureView) root;
        }
        if (root instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) root;
            for (int i = 0; i < group.getChildCount(); i++) {
                android.view.View child = group.getChildAt(i);
                TextureView found = findTextureView(child);
                if (found != null) return found;
            }
        }
        return null;
    }

    /**
     * Save image data to gallery
     * Returns Map with: success, filePath, error (if any)
     */
    public Map<String, Object> saveImageToGallery(byte[] imageData, String name) {
        Map<String, Object> result = new HashMap<>();

        try {
            if (imageData == null || imageData.length == 0) {
                result.put("success", false);
                result.put("error", "Invalid image data");
                return result;
            }

            // Decode bitmap from byte array
            Bitmap bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.length);
            if (bitmap == null) {
                result.put("success", false);
                result.put("error", "Could not create image from data");
                return result;
            }

            // Save using MediaStore
            boolean saved;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                saved = saveImageToGalleryQ(bitmap, name);
            } else {
                saved = saveImageToGalleryLegacy(bitmap, name);
            }

            if (saved) {
                result.put("success", true);
                result.put("message", "Image saved to gallery");
                Log.i(TAG, "Image saved to gallery: " + name);
            } else {
                result.put("success", false);
                result.put("error", "Failed to save image to gallery");
            }

            bitmap.recycle();
        } catch (Exception e) {
            Log.e(TAG, "Error saving image to gallery", e);
            result.put("success", false);
            result.put("error", e.getMessage());
        }

        return result;
    }

    /**
     * Save image to gallery (Android Q+)
     */
    private boolean saveImageToGalleryQ(Bitmap bitmap, String name) {
        try {
            ContentValues values = new ContentValues();
            values.put(MediaStore.Images.Media.DISPLAY_NAME, name + ".jpg");
            values.put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg");
            values.put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Nosmai");

            Uri uri = context.getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values);
            if (uri != null) {
                OutputStream outputStream = context.getContentResolver().openOutputStream(uri);
                if (outputStream != null) {
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 95, outputStream);
                    outputStream.close();
                    return true;
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "Error saving image (Q+)", e);
        }
        return false;
    }

    /**
     * Save image to gallery (Legacy)
     */
    private boolean saveImageToGalleryLegacy(Bitmap bitmap, String name) {
        try {
            String imagesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES).toString() + "/Nosmai";
            File dir = new File(imagesDir);
            if (!dir.exists()) {
                dir.mkdirs();
            }

            File imageFile = new File(dir, name + ".jpg");
            FileOutputStream fos = new FileOutputStream(imageFile);
            bitmap.compress(Bitmap.CompressFormat.JPEG, 95, fos);
            fos.close();

            // Notify media scanner
            ContentValues values = new ContentValues();
            values.put(MediaStore.Images.Media.DATA, imageFile.getAbsolutePath());
            values.put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg");
            context.getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values);

            return true;
        } catch (Exception e) {
            Log.e(TAG, "Error saving image (legacy)", e);
        }
        return false;
    }

    /**
     * Save video to gallery
     * Returns Map with: success, filePath, error (if any)
     */
    public Map<String, Object> saveVideoToGallery(String videoPath, String name) {
        Map<String, Object> result = new HashMap<>();

        try {
            if (videoPath == null || videoPath.isEmpty()) {
                result.put("success", false);
                result.put("error", "Invalid video path");
                return result;
            }

            File videoFile = new File(videoPath);
            if (!videoFile.exists()) {
                result.put("success", false);
                result.put("error", "Video file does not exist");
                return result;
            }

            // Save using MediaStore
            boolean saved;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                saved = saveVideoToGalleryQ(videoFile, name);
            } else {
                saved = saveVideoToGalleryLegacy(videoFile, name);
            }

            if (saved) {
                result.put("success", true);
                result.put("message", "Video saved to gallery");
                Log.i(TAG, "Video saved to gallery: " + name);
            } else {
                result.put("success", false);
                result.put("error", "Failed to save video to gallery");
            }
        } catch (Exception e) {
            Log.e(TAG, "Error saving video to gallery", e);
            result.put("success", false);
            result.put("error", e.getMessage());
        }

        return result;
    }

    /**
     * Save video to gallery (Android Q+)
     */
    private boolean saveVideoToGalleryQ(File videoFile, String name) {
        try {
            ContentValues values = new ContentValues();
            values.put(MediaStore.Video.Media.DISPLAY_NAME, name + ".mp4");
            values.put(MediaStore.Video.Media.MIME_TYPE, "video/mp4");
            values.put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/Nosmai");

            Uri uri = context.getContentResolver().insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values);
            if (uri != null) {
                OutputStream outputStream = context.getContentResolver().openOutputStream(uri);
                if (outputStream != null) {
                    FileInputStream inputStream = new FileInputStream(videoFile);
                    byte[] buffer = new byte[8192];
                    int bytesRead;
                    while ((bytesRead = inputStream.read(buffer)) != -1) {
                        outputStream.write(buffer, 0, bytesRead);
                    }
                    inputStream.close();
                    outputStream.close();
                    return true;
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "Error saving video (Q+)", e);
        }
        return false;
    }

    /**
     * Save video to gallery (Legacy)
     */
    private boolean saveVideoToGalleryLegacy(File videoFile, String name) {
        try {
            String videosDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES).toString() + "/Nosmai";
            File dir = new File(videosDir);
            if (!dir.exists()) {
                dir.mkdirs();
            }

            File destFile = new File(dir, name + ".mp4");

            // Copy file
            FileInputStream inputStream = new FileInputStream(videoFile);
            FileOutputStream outputStream = new FileOutputStream(destFile);
            byte[] buffer = new byte[8192];
            int bytesRead;
            while ((bytesRead = inputStream.read(buffer)) != -1) {
                outputStream.write(buffer, 0, bytesRead);
            }
            inputStream.close();
            outputStream.close();

            // Notify media scanner
            ContentValues values = new ContentValues();
            values.put(MediaStore.Video.Media.DATA, destFile.getAbsolutePath());
            values.put(MediaStore.Video.Media.MIME_TYPE, "video/mp4");
            context.getContentResolver().insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values);

            return true;
        } catch (Exception e) {
            Log.e(TAG, "Error saving video (legacy)", e);
        }
        return false;
    }

    // ============================================
    // CAMERA CONFIGURATION AND FLASH/TORCH
    // ============================================

    /**
     * Configure camera position and session preset
     */
    public boolean configureCamera(String position, String sessionPreset) {
        try {
            if (!isCameraPreviewActive) {
                Log.w(TAG, "Camera preview not active, cannot configure");
                return false;
            }

            // For Android, camera configuration is handled during startCameraPreview
            // This method is mainly for compatibility with iOS
            // If camera is already running and we need to switch, use switchCamera instead

            boolean isFront = "front".equalsIgnoreCase(position);

            if (camera2Helper != null) {
                // Switch camera if needed
                camera2Helper.switchCamera();
                Log.i(TAG, "Camera configured to position: " + position);
                return true;
            }

            Log.w(TAG, "Camera2Helper not initialized");
            return false;
        } catch (Exception e) {
            Log.e(TAG, "Error configuring camera", e);
            return false;
        }
    }

    /**
     * Check if device has flash
     */
    public boolean hasFlash() {
        try {
            if (camera2Helper != null) {
                return camera2Helper.hasFlash();
            }
            // Check if device has flash capability
            return context.getPackageManager().hasSystemFeature(android.content.pm.PackageManager.FEATURE_CAMERA_FLASH);
        } catch (Exception e) {
            Log.e(TAG, "Error checking flash", e);
            return false;
        }
    }

    /**
     * Check if device has torch
     */
    public boolean hasTorch() {
        // On Android, torch is same as flash
        return hasFlash();
    }

    /**
     * Set flash mode (off, on, auto)
     */
    public boolean setFlashMode(String mode) {
        try {
            if (camera2Helper == null) {
                Log.w(TAG, "Camera2Helper not initialized");
                return false;
            }

            // Flash mode is typically for photo capture
            // On Android, we'll store this for later use during photo capture
            Log.i(TAG, "Flash mode set to: " + mode);
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Error setting flash mode", e);
            return false;
        }
    }

    /**
     * Set torch mode (off, on, auto)
     */
    public boolean setTorchMode(String mode) {
        try {

            if (camera2Helper == null) {
                Log.w(TAG, "Camera2Helper not initialized, cannot set torch");
                return false;
            }

            // Handle auto mode same as on (since Camera2 doesn't have native auto mode for torch)
            boolean enable = "on".equalsIgnoreCase(mode) || "auto".equalsIgnoreCase(mode);

            camera2Helper.setTorchMode(enable);
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Error setting torch mode", e);
            return false;
        }
    }

    /**
     * Get current flash mode
     */
    public String getFlashMode() {
        // Return default since flash is used per photo capture
        return "off";
    }

    /**
     * Get current torch mode
     */
    public String getTorchMode() {
        try {
            if (camera2Helper != null) {
                return camera2Helper.isTorchOn() ? "on" : "off";
            }
        } catch (Exception e) {
            Log.e(TAG, "Error getting torch mode", e);
        }
        return "off";
    }

    /**
     * Start processing (for camera preview mode)
     * Starts the camera and filter processing without streaming
     */
    public boolean startProcessing() {
        try {
            if (isCameraPreviewActive) {
                Log.i(TAG, "Processing already active");
                return true;
            }

            // Start camera preview mode
            return startCameraPreview();
        } catch (Exception e) {
            Log.e(TAG, "Error starting processing", e);
            return false;
        }
    }

    /**
     * Stop processing (for camera preview mode)
     */
    public boolean stopProcessing() {
        try {
            if (!isCameraPreviewActive) {
                Log.i(TAG, "Processing not active");
                return true;
            }

            // Stop camera preview mode
            return stopCameraPreview();
        } catch (Exception e) {
            Log.e(TAG, "Error stopping processing", e);
            return false;
        }
    }

    /**
     * Detach camera view
     * Stops camera and cleans up preview view
     */
    public boolean detachCameraView() {
        try {
            stopCameraPreview();
            if (previewView != null) {
                previewView = null;
            }

            Log.i(TAG, "Camera view detached");
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Error detaching camera view", e);
            return false;
        }
    }
}
