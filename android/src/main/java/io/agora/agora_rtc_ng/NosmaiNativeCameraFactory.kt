package io.agora.agora_rtc_ng

import android.content.Context
import android.widget.FrameLayout
import com.nosmai.effect.api.NosmaiPreviewView
import com.nosmai.effect.api.NosmaiSDK
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import android.util.Log
import java.nio.ByteBuffer
import android.app.Activity

class NosmaiNativeCameraFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    companion object {
        @Volatile
        private var isStandaloneSdkInitialized = false
        private var standaloneLicenseKey: String? = null
        @Volatile
        private var currentPreviewView: NosmaiPreviewView? = null
        
        fun setStandaloneLicense(licenseKey: String) {
            standaloneLicenseKey = licenseKey
        }
        
        fun setCurrentPreviewView(previewView: NosmaiPreviewView?) {
            currentPreviewView = previewView
        }
        
        fun getCurrentPreviewView(): NosmaiPreviewView? {
            return currentPreviewView
        }
        
        fun clearCurrentPreviewView(previewView: NosmaiPreviewView?) {
            if (currentPreviewView == previewView) {
                currentPreviewView = null
            }
        }
        
        fun requestRefresh() {
            try {
                currentPreviewView?.requestRenderUpdate()
                Log.d("NosmaiNativeCamera", "🔄 Refresh requested for beauty filter update")
            } catch (e: Exception) {
                Log.w("NosmaiNativeCamera", "Failed to request refresh: ${e.message}")
            }
        }
        
        fun ensureStandaloneSdkInitialized(context: Context): Boolean {
            if (isStandaloneSdkInitialized) return true
            
            val licenseKey = standaloneLicenseKey
            if (licenseKey == null) {
                Log.w("NosmaiNativeCamera", "No license key set for standalone SDK")
                return false
            }
            
            try {
                val activity = context as? Activity ?: run {
                    Log.w("NosmaiNativeCamera", "Context is not an Activity, using application context")
                    // Try to get activity from application context - this is a fallback
                    NosmaiSDK.initialize(context, licenseKey)
                    isStandaloneSdkInitialized = true
                    Log.i("NosmaiNativeCamera", "✅ Standalone SDK initialized with application context")
                    return true
                }
                
                NosmaiSDK.initialize(activity, licenseKey)
                isStandaloneSdkInitialized = true
                Log.i("NosmaiNativeCamera", "✅ Standalone SDK initialized successfully")
                return true
            } catch (e: Exception) {
                Log.e("NosmaiNativeCamera", "Failed to initialize standalone SDK: ${e.message}")
                return false
            }
        }
    }
    
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return NosmaiNativeCameraView(context)
    }
}

class NosmaiNativeCameraView(private val context: Context) : PlatformView {
    private val container = FrameLayout(context)
    private var previewView: NosmaiPreviewView? = null
    private var camera2Helper: Camera2Helper? = null
    private var usingPlatformView: Boolean = true // Key flag from reference implementation

    init {
        initializePreview()
    }
    
    private fun initializePreview() {
        try {
            // CRITICAL: Ensure standalone SDK is initialized before proceeding
            if (!NosmaiNativeCameraFactory.ensureStandaloneSdkInitialized(context)) {
                Log.e("NosmaiNativeCamera", "❌ Cannot proceed - standalone SDK not initialized")
                return
            }
            
            // Create Nosmai preview view (like reference implementation line 96)
            previewView = NosmaiPreviewView(context)
            
            // Set as current preview view for beauty filter refresh
            NosmaiNativeCameraFactory.setCurrentPreviewView(previewView)
            
            // Add to container
            container.addView(
                previewView,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
            )
            
            // CRITICAL: Initialize pipeline to set GLView for rendering (like reference line 299)
            previewView?.initializePipeline()
            Log.i("NosmaiNativeCamera", "✅ Pipeline initialized - GLView set for rendering")
            
            // Start processing with the preview view (like reference line 444)
            NosmaiSDK.startProcessing(previewView!!)
            Log.i("NosmaiNativeCamera", "▶️ NosmaiSDK.startProcessing called")
            
            // Now start the camera capture to feed frames into the preview
            startCameraCapture()
            
            Log.i("NosmaiNativeCamera", "🚀 Processing and camera capture started")
        } catch (e: Exception) {
            Log.e("NosmaiNativeCamera", "Failed to initialize preview: ${e.message}")
        }
    }
    
    private fun startCameraCapture() {
        try {
            // Create Camera2Helper for frame capture (like reference implementation)
            camera2Helper = Camera2Helper(context, true) // Start with front camera
            
            // Set up YUV frame callback exactly like reference implementation (lines 1814-1857)
            camera2Helper?.setFrameCallback { yBuffer, uBuffer, vBuffer, 
                width, height, yStride, uStride, vStride, uPixelStride, vPixelStride ->
                
                if (yBuffer == null || uBuffer == null || vBuffer == null) return@setFrameCallback
                
                // Follow EXACT reference implementation pattern (line 1823)
                if (usingPlatformView) {
                    previewView?.let { pv ->
                        try {
                            // Calculate rotation like reference implementation
                            val helper = camera2Helper
                            val rotation = if (helper != null) {
                                calculateFrameRotation(helper.sensorOrientation, helper.isFrontCamera())
                            } else {
                                0
                            }
                            
                            // Render directly into preview view (reference lines 1825-1832)
                            pv.processYuvFrame(
                                yBuffer, uBuffer, vBuffer,
                                width, height,
                                yStride, uStride, vStride,
                                uPixelStride, vPixelStride,
                                rotation
                            )
                            pv.requestRenderUpdate()
                            return@setFrameCallback // Important: return here like reference line 1833
                        } catch (e: Exception) {
                            Log.e("NosmaiNativeCamera", "Error processing YUV frame: ${e.message}")
                        }
                    }
                }
            }
            
            // Start the camera capture
            camera2Helper?.startCamera()
            
            // Set camera orientation and mirroring after camera is started (when we have actual sensor orientation)
            camera2Helper?.let { helper ->
                val isFront = helper.isFrontCamera()
                val sensorOrientation = helper.sensorOrientation
                
                // Set camera orientation for the preview view
                previewView?.setCameraOrientation(isFront, sensorOrientation)
                
                // Set mirroring for front camera (like reference implementation)
                try {
                    NosmaiSDK.setMirrorX(isFront)
                    Log.i("NosmaiNativeCamera", "Mirror set to: $isFront")
                } catch (e: Exception) {
                    Log.w("NosmaiNativeCamera", "Failed to set mirror: ${e.message}")
                }
                
                Log.i("NosmaiNativeCamera", "Camera setup: front=$isFront, orientation=$sensorOrientation, mirrored=$isFront")
            }
            
            Log.i("NosmaiNativeCamera", "Camera2Helper started - frames should now feed into preview")
            
        } catch (e: Exception) {
            Log.e("NosmaiNativeCamera", "Failed to start camera capture: ${e.message}")
        }
    }
    
    // Calculate frame rotation based on sensor orientation and camera facing (from reference implementation)
    private fun calculateFrameRotation(sensorOrientation: Int, front: Boolean): Int {
        return if (front) { 
            if (sensorOrientation == 270) 1 else 6 
        } else { 
            if (sensorOrientation == 90) 2 else 1 
        }
    }

    override fun getView(): android.view.View = container

    override fun dispose() {
        try {
            Log.i("NosmaiNativeCamera", "Starting dispose - stopping camera and processing")
            
            // Stop camera capture first with immediate cleanup
            camera2Helper?.stopCamera()
            camera2Helper = null
            
            // Stop processing pipeline
            NosmaiSDK.stopProcessing()
            
            // Reset mirror setting for streaming (if it switches back)
            try {
                NosmaiSDK.setMirrorX(false) // Reset to streaming default
            } catch (_: Throwable) {}
            
            // Clean up view
            container.removeAllViews()
            
            // Clear current preview view reference
            NosmaiNativeCameraFactory.clearCurrentPreviewView(previewView)
            previewView = null
            
            Log.i("NosmaiNativeCamera", "Preview and camera disposed, resources should be released for streaming")
        } catch (e: Exception) {
            Log.e("NosmaiNativeCamera", "Error disposing preview: ${e.message}")
        }
    }
}