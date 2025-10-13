package io.agora.agora_rtc_ng

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.hardware.camera2.*
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Size
import androidx.core.app.ActivityCompat
import android.view.Surface
import java.nio.ByteBuffer
import com.nosmai.effect.api.NosmaiOffscreenSDK
import android.view.WindowManager

class Camera2Handler(private val context: Context) {
    companion object {
        private const val TAG = "Camera2Handler"
        private const val CAMERA_WIDTH = 1280
        private const val CAMERA_HEIGHT = 720
    }
    
    
    // Rotate I420 frame 90 degrees clockwise (1280x720 -> 720x1280)
    private fun rotateI420Clockwise90(src: ByteArray, srcWidth: Int, srcHeight: Int): ByteArray {
        val dstWidth = srcHeight
        val dstHeight = srcWidth
        val dst = ByteArray(src.size)
        
        val srcYSize = srcWidth * srcHeight
        val dstYSize = dstWidth * dstHeight
    
        // Rotate Y
        for (j in 0 until srcHeight) {
            for (i in 0 until srcWidth) {
                dst[(srcWidth - 1 - i) * dstWidth + j] = src[j * srcWidth + i]
            }
        }
        
        // Rotate U and V
        val srcUOffset = srcYSize
        val dstUOffset = dstYSize
        for (j in 0 until srcHeight / 2) {
            for (i in 0 until srcWidth / 2) {
                dst[dstUOffset + ((srcWidth / 2 - 1 - i) * (dstWidth / 2) + j)] = src[srcUOffset + j * (srcWidth / 2) + i]
                dst[dstUOffset + dstYSize/4 + ((srcWidth / 2 - 1 - i) * (dstWidth / 2) + j)] = src[srcUOffset + srcYSize/4 + j * (srcWidth / 2) + i]
            }
        }
        
        return dst
    }
    

    private fun transposeI420(src: ByteArray, srcWidth: Int, srcHeight: Int): ByteArray {
        val dstWidth = srcHeight
        val dstHeight = srcWidth
        val dst = ByteArray(src.size)
        
        val srcYSize = srcWidth * srcHeight
        val dstYSize = dstWidth * dstHeight
        val srcUVSize = srcYSize / 4
    
        // Transpose Y plane
        for (j in 0 until srcHeight) {
            for (i in 0 until srcWidth) {
                dst[i * dstWidth + j] = src[j * srcWidth + i]
            }
        }
    
        // Transpose U plane
        val srcUOffset = srcYSize
        val dstUOffset = dstYSize
        for (j in 0 until srcHeight / 2) {
            for (i in 0 until srcWidth / 2) {
                dst[dstUOffset + i * (dstWidth / 2) + j] =
                    src[srcUOffset + j * (srcWidth / 2) + i]
            }
        }
    
        // Transpose V plane
        val srcVOffset = srcYSize + srcUVSize
        val dstVOffset = dstYSize + srcUVSize
        for (j in 0 until srcHeight / 2) {
            for (i in 0 until srcWidth / 2) {
                dst[dstVOffset + i * (dstWidth / 2) + j] =
                    src[srcVOffset + j * (srcWidth / 2) + i]
            }
        }
        
        return dst
    }
    
    
    // Rotate I420 frame 180 degrees
    private fun rotateI420Clockwise180(src: ByteArray, srcWidth: Int, srcHeight: Int): ByteArray {
        val dst = ByteArray(src.size)
        
        val srcYSize = srcWidth * srcHeight
        
        // Rotate Y plane 180 degrees
        for (j in 0 until srcHeight) {
            for (i in 0 until srcWidth) {
                dst[(srcHeight - 1 - j) * srcWidth + (srcWidth - 1 - i)] = src[j * srcWidth + i]
            }
        }
        
        // Rotate U plane 180 degrees
        val srcUOffset = srcYSize
        val dstUOffset = srcYSize
        for (j in 0 until srcHeight / 2) {
            for (i in 0 until srcWidth / 2) {
                dst[dstUOffset + ((srcHeight / 2 - 1 - j) * (srcWidth / 2) + (srcWidth / 2 - 1 - i))] = 
                    src[srcUOffset + (j * (srcWidth / 2) + i)]
            }
        }
        
        // Rotate V plane 180 degrees
        val srcVOffset = srcYSize + srcYSize / 4
        val dstVOffset = srcYSize + srcYSize / 4
        for (j in 0 until srcHeight / 2) {
            for (i in 0 until srcWidth / 2) {
                dst[dstVOffset + ((srcHeight / 2 - 1 - j) * (srcWidth / 2) + (srcWidth / 2 - 1 - i))] = 
                    src[srcVOffset + (j * (srcWidth / 2) + i)]
            }
        }
        
        return dst
    }
    
    // Rotate I420 frame 270 degrees clockwise (1280x720 -> 720x1280)
    private fun rotateI420Clockwise270(src: ByteArray, srcWidth: Int, srcHeight: Int): ByteArray {
        val dstWidth = srcHeight
        val dstHeight = srcWidth
        val dst = ByteArray(src.size)
        
        val srcYSize = srcWidth * srcHeight
        val dstYSize = dstWidth * dstHeight
    
        // Rotate Y
        for (j in 0 until srcHeight) {
            for (i in 0 until srcWidth) {
                dst[i * dstWidth + (dstWidth - 1 - j)] = src[j * srcWidth + i]
            }
        }
        
        // Rotate U and V
        val srcUOffset = srcYSize
        val dstUOffset = dstYSize
        for (j in 0 until srcHeight / 2) {
            for (i in 0 until srcWidth / 2) {
                dst[dstUOffset + (i * (dstWidth/2) + (dstWidth/2-1-j))] = src[srcUOffset + j * (srcWidth/2) + i];
                dst[dstUOffset + dstYSize/4 + (i * (dstWidth/2) + (dstWidth/2-1-j))] = src[srcUOffset + srcYSize/4 + j * (srcWidth/2) + i];
            }
        }
        
        return dst
    }
        private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var previewSurface: Surface? = null
    private var backgroundHandler: Handler? = null
    private var backgroundThread: HandlerThread? = null
    
    private var frameCallback: ((ByteArray, Int, Int) -> Unit)? = null
    private var frameCount = 0
    private var currentIsFront = true
    private var currentSensorOrientation = 90
    private var currentCameraId: String? = null

    fun startCamera() {
        synchronized(this) {
            if (cameraDevice != null) {
                Log.d(TAG, "Camera already opened")
                return
            }
            startBackgroundThread()
            openCamera()
        }
    }

    fun switchCamera() {
        Log.d(TAG, "switchCamera called")
        synchronized(this) {
            // Close current camera
            closeCamera()
            
            // Toggle camera facing
            currentIsFront = !currentIsFront
            
            // Small delay to ensure camera is fully released
            Thread.sleep(200)
            
            // Open new camera
            startBackgroundThread()
            openCameraWithFacing(currentIsFront)
        }
    }

    fun stopCamera() {
        Log.d(TAG, "stopCamera called")
        try {
            closeCamera()
        } catch (e: Exception) {
            Log.e(TAG, "Error closing camera", e)
        }
        try {
            stopBackgroundThread()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping background thread", e)
        }
        Log.d(TAG, "stopCamera completed")
    }

    fun setFrameCallback(callback: (ByteArray, Int, Int) -> Unit) {
        frameCallback = callback
    }

    fun setPreviewSurface(surface: android.view.Surface?) {
        previewSurface = surface
    }

    fun attachPreviewSurface(surface: android.view.Surface?) {
        previewSurface = surface
        // If camera is already running, recreate the capture session to include the new surface
        if (cameraDevice != null) {
            recreateCaptureSession()
        }
    }

    fun isFrontCamera(): Boolean {
        return currentIsFront
    }

    fun getSensorOrientation(): Int {
        return currentSensorOrientation
    }

    private fun startBackgroundThread() {
        backgroundThread = HandlerThread("Camera2Background").apply {
            start()
        }
        backgroundHandler = Handler(backgroundThread!!.looper)
    }

    private fun stopBackgroundThread() {
        backgroundThread?.quitSafely()
        try {
            backgroundThread?.join()
            backgroundThread = null
            backgroundHandler = null
        } catch (e: InterruptedException) {
            e.printStackTrace()
        }
    }

    private fun openCamera() {
        openCameraWithFacing(currentIsFront)
    }

    private fun flipI420Vertically(src: ByteArray, width: Int, height: Int): ByteArray {
        val dst = ByteArray(src.size)
        val ySize = width * height
        val uvSize = ySize / 4
    
        // Flip Y
        for (j in 0 until height) {
            val srcRowOffset = j * width
            val dstRowOffset = (height - 1 - j) * width
            System.arraycopy(src, srcRowOffset, dst, dstRowOffset, width)
        }
    
        // Flip U
        val uSrcBase = ySize
        val uDstBase = ySize
        for (j in 0 until height / 2) {
            val srcRowOffset = uSrcBase + j * (width / 2)
            val dstRowOffset = uDstBase + (height / 2 - 1 - j) * (width / 2)
            System.arraycopy(src, srcRowOffset, dst, dstRowOffset, width / 2)
        }
    
        // Flip V
        val vSrcBase = ySize + uvSize
        val vDstBase = ySize + uvSize
        for (j in 0 until height / 2) {
            val srcRowOffset = vSrcBase + j * (width / 2)
            val dstRowOffset = vDstBase + (height / 2 - 1 - j) * (width / 2)
            System.arraycopy(src, srcRowOffset, dst, dstRowOffset, width / 2)
        }
    
        return dst
    }
    
    

    private fun openCameraWithFacing(useFrontCamera: Boolean) {
        val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        
        try {
            // Find camera with desired facing
            val desiredFacing = if (useFrontCamera) {
                CameraCharacteristics.LENS_FACING_FRONT
            } else {
                CameraCharacteristics.LENS_FACING_BACK
            }
            
            val cameraId = cameraManager.cameraIdList.firstOrNull { id ->
                val characteristics = cameraManager.getCameraCharacteristics(id)
                val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
                facing == desiredFacing
            } ?: cameraManager.cameraIdList[0]
            
            currentCameraId = cameraId
            Log.d(TAG, "Attempting to open camera: $cameraId (${if (useFrontCamera) "front" else "back"})")
            
            if (ActivityCompat.checkSelfPermission(context, Manifest.permission.CAMERA) 
                != PackageManager.PERMISSION_GRANTED) {
                Log.e(TAG, "Camera permission not granted")
                return
            }

            // Setup ImageReader for YUV_420_888 format
            imageReader = ImageReader.newInstance(
                CAMERA_WIDTH, 
                CAMERA_HEIGHT, 
                ImageFormat.YUV_420_888, 
                2
            )

            // Cache facing + sensor orientation
            try {
                val chars = cameraManager.getCameraCharacteristics(cameraId)
                currentIsFront = (chars.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT)
                currentSensorOrientation = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
                Log.d(TAG, "Camera facing=${if (currentIsFront) "FRONT" else "BACK"}, sensorOrientation=$currentSensorOrientation")
                // Inform off-screen FD pipeline about camera facing for correct landmark orientation
                try { NosmaiOffscreenSDK.setCameraFacing(currentIsFront) } catch (_: Throwable) {}
            } catch (_: Throwable) {}
            imageReader?.setOnImageAvailableListener(
    { reader ->
        val image = reader.acquireLatestImage()
        image?.let {
            try {
                // Extract YUV planes
                val yBuffer = it.planes[0].buffer.duplicate()
                val uBuffer = it.planes[1].buffer.duplicate()
                val vBuffer = it.planes[2].buffer.duplicate()
                
                // Reset positions
                yBuffer.position(0)
                uBuffer.position(0)
                vBuffer.position(0)
                
                val yRowStride = it.planes[0].rowStride
                val uRowStride = it.planes[1].rowStride
                val vRowStride = it.planes[2].rowStride
                
                val uPixelStride = it.planes[1].pixelStride
                val vPixelStride = it.planes[2].pixelStride
                
                try {
                    val width = it.width
                    val height = it.height
                    val i420Original = convertImageToYuvBytes(it)
                    
                    val rotatedI420 = when (currentSensorOrientation) {
                        90 -> {
                            rotateI420Clockwise270(i420Original, width, height)
                        }
                        270 -> {
                            val rotated = rotateI420Clockwise270(i420Original, width, height)
                            flipI420Vertically(rotated, height, width)
                        }
                    
                        180 -> {
                            flipI420Vertically(i420Original, width, height)
                        }
                        else -> {
                            i420Original
                        }
                    }
                                                            
                    // After rotation, dimensions are swapped
                    val rotatedWidth = height  // 720
                    val rotatedHeight = width  // 1280
                    val ySize = rotatedWidth * rotatedHeight
                    val uvSize = ySize / 4
                    
                    val yDirect = ByteBuffer.allocateDirect(ySize)
                    val uDirect = ByteBuffer.allocateDirect(uvSize)
                    val vDirect = ByteBuffer.allocateDirect(uvSize)
                    yDirect.put(rotatedI420, 0, ySize).position(0)
                    uDirect.put(rotatedI420, ySize, uvSize).position(0)
                    vDirect.put(rotatedI420, ySize + uvSize, uvSize).position(0)

                    // Send pre-rotated portrait frame to Nosmai with orientation=0
                    // Keep mirror flag for front camera to get selfie effect
                    NosmaiOffscreenSDK.receiveFrame(
                        yDirect, uDirect, vDirect,
                        rotatedWidth, rotatedHeight, // Now 720x1280 (portrait)
                        rotatedWidth, rotatedWidth / 2, rotatedWidth / 2,
                        1, 1,
                        0, // No rotation needed - already rotated to portrait
                        false // Do NOT mirror at source; mirror only local preview
                    )
                } catch (_: Throwable) {}

            } finally {
                it.close()
            }
        }
    },
    backgroundHandler
)




            cameraManager.openCamera(cameraId, stateCallback, backgroundHandler)
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open camera", e)
        }
    }

    private val stateCallback = object : CameraDevice.StateCallback() {
        override fun onOpened(camera: CameraDevice) {
            Log.d(TAG, "Camera opened")
            cameraDevice = camera
            createCaptureSession()
        }

        override fun onDisconnected(camera: CameraDevice) {
            Log.d(TAG, "Camera disconnected")
            cameraDevice?.close()
            cameraDevice = null
        }

        override fun onError(camera: CameraDevice, error: Int) {
            Log.e(TAG, "Camera error: $error")
            cameraDevice?.close()
            cameraDevice = null
        }
    }

    private fun createCaptureSession() {
        try {
            val yuvSurface = imageReader?.surface ?: return
            val targets = mutableListOf(yuvSurface)
            if (previewSurface != null) {
                targets.add(previewSurface!!)
            }

            cameraDevice?.createCaptureSession(
                targets,
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        captureSession = session
                        startPreview()
                    }

                    override fun onConfigureFailed(session: CameraCaptureSession) {
                        Log.e(TAG, "Failed to configure capture session")
                    }
                },
                backgroundHandler
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create capture session", e)
        }
    }

    private fun startPreview() {
        try {
            val captureRequestBuilder = cameraDevice?.createCaptureRequest(
                CameraDevice.TEMPLATE_PREVIEW
            ) ?: return
            // Always add YUV reader for processing
            imageReader?.surface?.let { captureRequestBuilder.addTarget(it) }
            // Optionally add preview surface for zero-latency on-screen preview
            previewSurface?.let { captureRequestBuilder.addTarget(it) }
            
            // Set auto-focus mode
            captureRequestBuilder.set(
                CaptureRequest.CONTROL_AF_MODE,
                CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO
            )
            
            captureSession?.setRepeatingRequest(
                captureRequestBuilder.build(),
                null,
                backgroundHandler
            )
            
            Log.d(TAG, "Camera preview started")
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start preview", e)
        }
    }

    private fun recreateCaptureSession() {
        try {
            captureSession?.close()
            captureSession = null
            createCaptureSession()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to recreate capture session", e)
        }
    }

    private fun closeCamera() {
        Log.d(TAG, "closeCamera called")
        try {
            captureSession?.close()
            captureSession = null
        } catch (e: Exception) {
            Log.e(TAG, "Error closing capture session", e)
        }
        
        try {
            cameraDevice?.close()
            cameraDevice = null
        } catch (e: Exception) {
            Log.e(TAG, "Error closing camera device", e)
        }
        
        try {
            imageReader?.close()
            imageReader = null
        } catch (e: Exception) {
            Log.e(TAG, "Error closing image reader", e)
        }
        
        // Clear preview surface reference
        previewSurface = null
        frameCallback = null
        
        Log.d(TAG, "closeCamera completed")
    }

    private fun convertImageToYuvBytes(image: Image): ByteArray {
        val width = image.width
        val height = image.height

        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]

        val ySize = width * height
        val uvSize = ySize / 4
        val i420 = ByteArray(ySize + uvSize + uvSize) // I420: Y + U + V

        // Copy Y plane respecting row stride
        val yBuffer: ByteBuffer = yPlane.buffer
        val yRowStride = yPlane.rowStride
        if (yRowStride == width) {
            yBuffer.get(i420, 0, ySize)
        } else {
            for (row in 0 until height) {
                yBuffer.position(row * yRowStride)
                yBuffer.get(i420, row * width, width)
            }
        }

        // Copy U and V planes into I420
        val uBuffer: ByteBuffer = uPlane.buffer
        val vBuffer: ByteBuffer = vPlane.buffer
        val uRowStride = uPlane.rowStride
        val vRowStride = vPlane.rowStride
        val uPixelStride = uPlane.pixelStride
        val vPixelStride = vPlane.pixelStride

        // U plane output starts at ySize
        // V plane output starts at ySize + uvSize
        if (uPixelStride == 1 && vPixelStride == 1) {
            // Fast path: contiguous U/V data, but still respect row strides
            for (row in 0 until height / 2) {
                uBuffer.position(row * uRowStride)
                uBuffer.get(i420, ySize + row * (width / 2), width / 2)

                vBuffer.position(row * vRowStride)
                vBuffer.get(i420, ySize + uvSize + row * (width / 2), width / 2)
            }
        } else {
            // Generic path: sample using pixel stride
            var uPos = ySize
            var vPos = ySize + uvSize
            for (row in 0 until height / 2) {
                for (col in 0 until width / 2) {
                    i420[uPos++] = uBuffer.get(row * uRowStride + col * uPixelStride)
                    i420[vPos++] = vBuffer.get(row * vRowStride + col * vPixelStride)
                }
            }
        }

        return i420
    }
}
