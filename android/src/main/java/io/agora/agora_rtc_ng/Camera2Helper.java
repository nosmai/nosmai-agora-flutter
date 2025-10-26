package io.agora.agora_rtc_ng;

import android.Manifest;
import android.annotation.SuppressLint;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.ImageFormat;
import android.graphics.SurfaceTexture;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.params.StreamConfigurationMap;
import android.util.Range;
import android.media.Image;
import android.media.ImageReader;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Log;
import android.util.Size;
import android.view.Surface;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.app.ActivityCompat;

import java.nio.ByteBuffer;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;

/**
 * Camera2Helper - Camera2 API wrapper for Nosmai-Agora integration
 *
 * Features:
 * - YUV_420_888 frame capture (ImageReader)
 * - 30 FPS @ 720p optimization
 * - Front/back camera support
 * - Background thread for camera operations
 * - Auto-exposure and auto-focus
 */
public class Camera2Helper {
    private static final String TAG = "Camera2Helper";
    public static final int CAMERA_FACING = CameraCharacteristics.LENS_FACING_FRONT;

    private int mCurrentCameraFacing = CAMERA_FACING;

    private Context mContext;
    private CameraDevice mCameraDevice;
    private CameraCaptureSession mCaptureSession;
    private Surface mPreviewSurface; // Optional OES preview surface
    private ImageReader mImageReader;
    private Size mPreviewSize;
    private HandlerThread mBackgroundThread;
    private Handler mBackgroundHandler;
    private Semaphore mCameraOpenCloseLock = new Semaphore(1);
    private int mSensorOrientation;
    private FrameCallback mFrameCallback;
    private CameraCharacteristics mCameraCharacteristics;

    private boolean mIsCameraOpened = false;
    private boolean mFirstFrameLogged = false; // Flag for one-time frame arrival log

    // Smart buffer reuse for current session
    private byte[] mReuseBuffer = null;
    private int mLastBufferSize = 0;

    /**
     * Frame callback interface - delivers YUV planes directly
     */
    public interface FrameCallback {
        void onFrameAvailable(ByteBuffer y, ByteBuffer u, ByteBuffer v,
                              int width, int height,
                              int yStride, int uStride, int vStride,
                              int uPixelStride, int vPixelStride);
    }

    public Camera2Helper(Context context) {
        mContext = context;
    }

    public Camera2Helper(Context context, boolean isFrontCamera) {
        mContext = context;
        mCurrentCameraFacing = isFrontCamera ?
                CameraCharacteristics.LENS_FACING_FRONT :
                CameraCharacteristics.LENS_FACING_BACK;
    }

    public void setFrameCallback(FrameCallback callback) {
        mFrameCallback = callback;
    }

    public void startCamera() {
        Log.i(TAG, "📸 startCamera() called");
        mFirstFrameLogged = false; // Reset flag for new camera session
        startBackgroundThread();
        Log.i(TAG, "✅ Background thread started");
        openCamera();
        Log.i(TAG, "✅ openCamera() initiated (async)");
    }

    public void stopCamera() {
        try {
            // 🎯 CRITICAL FIX: Don't clear mFrameCallback here!
            // It needs to persist across camera flips so frames continue flowing
            // The callback will be properly cleared when setFrameCallback(null) is called
            // or when the camera is permanently released

            // OLD BUG: mFrameCallback = null; ❌ This caused freeze after flip!

            closeCamera();
            stopBackgroundThread();
            Log.i(TAG, "✅ Camera stopped (callback preserved)");
        } catch (Exception e) {
            Log.e(TAG, "Error during camera stop: " + e.getMessage());
        }
    }

    private void startBackgroundThread() {
        mBackgroundThread = new HandlerThread("CameraBackground");
        mBackgroundThread.start();
        mBackgroundHandler = new Handler(mBackgroundThread.getLooper());
    }

    private void stopBackgroundThread() {
        if (mBackgroundThread != null) {
            mBackgroundThread.quitSafely();
            try {
                mBackgroundThread.join();
                mBackgroundThread = null;
                mBackgroundHandler = null;
            } catch (InterruptedException e) {
            }
        }
    }

    @SuppressLint("MissingPermission")
    private void openCamera() {
        Log.i(TAG, "🔓 openCamera() starting...");

        if (ActivityCompat.checkSelfPermission(mContext, Manifest.permission.CAMERA)
                != PackageManager.PERMISSION_GRANTED) {
            Log.e(TAG, "❌ No camera permission");
            return;
        }
        Log.i(TAG, "✅ Camera permission granted");

        CameraManager manager = (CameraManager) mContext.getSystemService(Context.CAMERA_SERVICE);
        try {
            String cameraId = getCameraId(manager);
            if (cameraId == null) {
                Log.e(TAG, "❌ Camera ID is null!");
                return;
            }
            Log.i(TAG, "✅ Camera ID: " + cameraId);

            // Get camera characteristics
            mCameraCharacteristics = manager.getCameraCharacteristics(cameraId);
            StreamConfigurationMap map =
                    mCameraCharacteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
            if (map == null) {
                Log.e(TAG, "❌ StreamConfigurationMap is null!");
                return;
            }

            // Get sensor orientation
            mSensorOrientation = mCameraCharacteristics.get(CameraCharacteristics.SENSOR_ORIENTATION);
            mPreviewSize = chooseOptimalSize(map.getOutputSizes(SurfaceTexture.class), 1280, 720);
            Log.i(TAG, "✅ Preview size: " + mPreviewSize.getWidth() + "x" + mPreviewSize.getHeight());

            mImageReader = ImageReader.newInstance(
                    mPreviewSize.getWidth(), mPreviewSize.getHeight(),
                    ImageFormat.YUV_420_888, 3);
            mImageReader.setOnImageAvailableListener(mOnImageAvailableListener, mBackgroundHandler);
            Log.i(TAG, "✅ ImageReader created");

            Log.i(TAG, "🔒 Trying to acquire camera lock...");
            if (!mCameraOpenCloseLock.tryAcquire(2500, TimeUnit.MILLISECONDS)) {
                Log.e(TAG, "❌ TIMEOUT waiting for camera lock!");
                throw new RuntimeException("Time out waiting to lock camera opening.");
            }
            Log.i(TAG, "✅ Camera lock acquired");

            Log.i(TAG, "📸 Opening camera device (async)...");
            manager.openCamera(cameraId, mStateCallback, mBackgroundHandler);
            Log.i(TAG, "✅ openCamera() call dispatched, waiting for callback...");

        } catch (CameraAccessException e) {
            Log.e(TAG, "❌ CameraAccessException: " + e.getMessage(), e);
        } catch (InterruptedException e) {
            Log.e(TAG, "❌ InterruptedException: " + e.getMessage(), e);
        } catch (Exception e) {
            Log.e(TAG, "❌ Unexpected exception: " + e.getMessage(), e);
        }
    }

    private String getCameraId(CameraManager manager) {
        try {
            for (String cameraId : manager.getCameraIdList()) {
                CameraCharacteristics characteristics = manager.getCameraCharacteristics(cameraId);
                Integer facing = characteristics.get(CameraCharacteristics.LENS_FACING);
                if (facing != null && facing == mCurrentCameraFacing) {
                    return cameraId;
                }
            }
            if (manager.getCameraIdList().length > 0) {
                String fallbackId = manager.getCameraIdList()[0];
                return fallbackId;
            }
        } catch (CameraAccessException e) {
            Log.e(TAG, "Failed to get camera ID", e);
        }
        return null;
    }

    private Size chooseOptimalSize(Size[] choices, int width, int height) {
        List<Size> bigEnough = Arrays.asList(choices);

        Collections.sort(bigEnough, new Comparator<Size>() {
            @Override
            public int compare(Size lhs, Size rhs) {
                return Long.signum((long) rhs.getWidth() * rhs.getHeight()
                        - (long) lhs.getWidth() * lhs.getHeight());
            }
        });

        for (Size option : bigEnough) {
            if (option.getWidth() <= width && option.getHeight() <= height) {
                return option;
            }
        }

        return bigEnough.get(bigEnough.size() - 1);
    }

    private final CameraDevice.StateCallback mStateCallback = new CameraDevice.StateCallback() {
        @Override
        public void onOpened(@NonNull CameraDevice cameraDevice) {
            Log.i(TAG, "🎉 Camera device OPENED! ID: " + cameraDevice.getId());
            mCameraOpenCloseLock.release();
            Log.i(TAG, "🔓 Camera lock released");
            mCameraDevice = cameraDevice;
            Log.i(TAG, "📸 Creating capture session...");
            createCaptureSession();
            mIsCameraOpened = true;
            Log.i(TAG, "✅ mIsCameraOpened = true");
        }

        @Override
        public void onDisconnected(@NonNull CameraDevice cameraDevice) {
            Log.w(TAG, "⚠️ Camera disconnected! ID: " + cameraDevice.getId());
            mCameraOpenCloseLock.release();
            cameraDevice.close();
            mCameraDevice = null;
            if (mCaptureSession != null) {
                mCaptureSession.close();
                mCaptureSession = null;
            }
            mIsCameraOpened = false;
        }

        @Override
        public void onError(@NonNull CameraDevice cameraDevice, int error) {
            Log.e(TAG, "❌ Camera ERROR! ID: " + cameraDevice.getId() + ", Error code: " + error);
            mCameraOpenCloseLock.release();
            cameraDevice.close();
            mCameraDevice = null;
            if (mCaptureSession != null) {
                mCaptureSession.close();
                mCaptureSession = null;
            }
            mIsCameraOpened = false;
        }
    };

    private void createCaptureSession() {
        Log.i(TAG, "🎬 createCaptureSession() called");
        try {
            if (mCameraDevice == null) {
                Log.e(TAG, "❌ mCameraDevice is null!");
                return;
            }
            if (mImageReader == null) {
                Log.e(TAG, "❌ mImageReader is null!");
                return;
            }
            Log.i(TAG, "✅ Camera device and ImageReader ready");

            // Build targets (always include YUV reader, optionally include OES preview surface)
            java.util.ArrayList<Surface> targets = new java.util.ArrayList<>();
            Surface yuvSurface = mImageReader.getSurface();
            targets.add(yuvSurface);
            if (mPreviewSurface != null) targets.add(mPreviewSurface);
            Log.i(TAG, "✅ Targets created: " + targets.size());

            mPreviewRequestBuilder = mCameraDevice.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
            mPreviewRequestBuilder.addTarget(yuvSurface);
            if (mPreviewSurface != null) mPreviewRequestBuilder.addTarget(mPreviewSurface);
            Log.i(TAG, "✅ Capture request builder created");

            Log.i(TAG, "📸 Creating capture session (async)...");
            mCameraDevice.createCaptureSession(
                    targets, new CameraCaptureSession.StateCallback() {
                        @Override
                        public void onConfigured(@NonNull CameraCaptureSession cameraCaptureSession) {
                            Log.i(TAG, "🎉 Capture session CONFIGURED!");
                            if (mCameraDevice == null) {
                                Log.w(TAG, "⚠️ Camera device null in onConfigured, skipping");
                                return;
                            }

                            mCaptureSession = cameraCaptureSession;
                            try {
                                // Get best supported FPS range for optimal performance
                                Range<Integer> fpsRange = getBestFpsRange();
                                mPreviewRequestBuilder.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, fpsRange);
                                Log.i(TAG, "✅ FPS range set: " + fpsRange);

                                // Set auto-exposure and auto-focus for stability
                                mPreviewRequestBuilder.set(CaptureRequest.CONTROL_AE_MODE,
                                        CaptureRequest.CONTROL_AE_MODE_ON);
                                mPreviewRequestBuilder.set(CaptureRequest.CONTROL_AF_MODE,
                                        CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);

                                CaptureRequest request = mPreviewRequestBuilder.build();
                                Log.i(TAG, "📸 Starting repeating request...");
                                mCaptureSession.setRepeatingRequest(request, null, mBackgroundHandler);
                                Log.i(TAG, "🎉 CAPTURE SESSION ACTIVE! Frames should start flowing...");

                            } catch (CameraAccessException e) {
                                Log.e(TAG, "❌ Failed to set up capture request", e);
                            }
                        }

                        @Override
                        public void onConfigureFailed(@NonNull CameraCaptureSession cameraCaptureSession) {
                            Log.e(TAG, "❌ CAPTURE SESSION CONFIGURATION FAILED!");
                        }
                    }, mBackgroundHandler);
            Log.i(TAG, "✅ createCaptureSession() dispatched, waiting for callback...");

        } catch (CameraAccessException e) {
            Log.e(TAG, "❌ CameraAccessException in createCaptureSession", e);
        } catch (Exception e) {
            Log.e(TAG, "❌ Unexpected exception in createCaptureSession", e);
        }
    }

    private void closeCamera() {
        try {
            mCameraOpenCloseLock.acquire();
            if (mCaptureSession != null) {
                try {
                    mCaptureSession.stopRepeating();
                    Thread.sleep(100);
                } catch (Exception e) {
                    Log.w(TAG, "Failed to stop repeating request: " + e.getMessage());
                }
            }

            if (mImageReader != null) {
                try {
                    mImageReader.setOnImageAvailableListener(null, null);
                } catch (Exception e) {
                    Log.w(TAG, "Failed to clear ImageReader listener: " + e.getMessage());
                }
            }

            if (mCaptureSession != null) {
                try {
                    Log.d(TAG, "Closing capture session...");
                    mCaptureSession.close();
                    mCaptureSession = null;

                    Thread.sleep(50);
                } catch (Exception e) {
                    Log.w(TAG, "Error closing capture session: " + e.getMessage());
                    mCaptureSession = null;
                }
            }

            if (mCameraDevice != null) {
                try {
                    Log.d(TAG, "Closing camera device...");
                    mCameraDevice.close();
                    mCameraDevice = null;

                    // 🎯 Wait for device to fully release
                    Thread.sleep(100);
                } catch (Exception e) {
                    Log.w(TAG, "Error closing camera device: " + e.getMessage());
                    mCameraDevice = null;
                }
            }

            // Finally close ImageReader
            if (mImageReader != null) {
                try {
                    mImageReader.close();
                    mImageReader = null;
                } catch (Exception e) {
                    Log.w(TAG, "Error closing ImageReader: " + e.getMessage());
                    mImageReader = null;
                }
            }

            // Clear preview surface reference
            mPreviewSurface = null;

            // Update camera state
            mIsCameraOpened = false;

            // Cleanup reuse buffer
            mReuseBuffer = null;
            mLastBufferSize = 0;


        } catch (InterruptedException e) {
            Log.e(TAG, "Interrupted while trying to lock camera closing", e);
        } finally {
            mCameraOpenCloseLock.release();
        }
    }

    /**
     * Optionally set a GL OES preview Surface (from SurfaceTexture). Call before startCamera().
     */
    public void setPreviewSurface(@Nullable android.view.Surface surface) {
        this.mPreviewSurface = surface;
    }

    /**
     * Reconfigure capture session with a new preview surface (safe to call at runtime).
     */
    public void reconfigurePreviewSurface(@Nullable android.view.Surface surface) {
        this.mPreviewSurface = surface;
        if (isCameraOpened()) {
            // Rebuild the capture session with the updated targets
            createCaptureSession();
        }
    }

    /**
     * ImageReader callback - delivers YUV frames to registered callback
     */
    private final ImageReader.OnImageAvailableListener mOnImageAvailableListener =
            new ImageReader.OnImageAvailableListener() {
                @Override
                public void onImageAvailable(ImageReader reader) {
                    Image image = null;
                    try {
                        // 🎯 SAFETY CHECK: Don't process frames if camera is not opened
                        // This prevents processing during shutdown
                        if (!mIsCameraOpened || mCameraDevice == null) {
                            return;
                        }

                        image = reader.acquireLatestImage();
                        if (image == null) {
                            return;
                        }

                        // 🎯 SAFETY CHECK: Callback must be registered
                        // If null, we're shutting down - close image and return
                        if (mFrameCallback == null) {
                            Log.w(TAG, "⚠️ Frame received but mFrameCallback is NULL! Dropping frame.");
                            image.close();
                            return;
                        }

                        final Image.Plane[] planes = image.getPlanes();

                        // 🎯 Log first frame arrival (one-time per camera open)
                        if (!mFirstFrameLogged) {
                            Log.i(TAG, "📸 FIRST FRAME RECEIVED! Size: " + image.getWidth() + "x" + image.getHeight());
                            mFirstFrameLogged = true;
                        }

                        // Deliver YUV planes to callback
                        mFrameCallback.onFrameAvailable(
                                planes[0].getBuffer(), // Y plane
                                planes[1].getBuffer(), // U plane
                                planes[2].getBuffer(), // V plane
                                image.getWidth(),
                                image.getHeight(),
                                planes[0].getRowStride(), // Y stride
                                planes[1].getRowStride(), // U stride
                                planes[2].getRowStride(), // V stride
                                planes[1].getPixelStride(), // U pixel stride
                                planes[2].getPixelStride()  // V pixel stride
                        );

                    } catch (final Exception e) {
                        Log.e(TAG, "Error in onImageAvailable: ", e);
                    } finally {
                        if (image != null) {
                            image.close();
                        }
                    }
                }
            };

    public boolean isCameraOpened() {
        return mIsCameraOpened && mCameraDevice != null && mCaptureSession != null;
    }

    /**
     * Check if camera is in a valid state
     */
    public boolean isValidState() {
        return isCameraOpened();
    }

    public Size getPreviewSize() {
        return mPreviewSize;
    }

    public int getPreviewWidth() {
        return mPreviewSize != null ? mPreviewSize.getWidth() : 0;
    }

    public int getPreviewHeight() {
        return mPreviewSize != null ? mPreviewSize.getHeight() : 0;
    }

    public int getSensorOrientation() {
        return mSensorOrientation;
    }

    public boolean isFrontCamera() {
        return mCurrentCameraFacing == CameraCharacteristics.LENS_FACING_FRONT;
    }

    // Camera controls
    private boolean mFlashEnabled = false;
    private CaptureRequest.Builder mPreviewRequestBuilder;

    /**
     * Set flash enabled/disabled (only works for back camera)
     */
    public void setFlashEnabled(boolean enabled) {
        mFlashEnabled = enabled;
        updateFlashMode();
    }

    /**
     * Update flash mode in capture request
     */
    private void updateFlashMode() {
        if (mPreviewRequestBuilder != null && mCaptureSession != null) {
            try {
                if (mFlashEnabled && !isFrontCamera()) {
                    mPreviewRequestBuilder.set(CaptureRequest.FLASH_MODE,
                            CaptureRequest.FLASH_MODE_TORCH);
                } else {
                    mPreviewRequestBuilder.set(CaptureRequest.FLASH_MODE,
                            CaptureRequest.FLASH_MODE_OFF);
                }
                mCaptureSession.setRepeatingRequest(mPreviewRequestBuilder.build(),
                        null, mBackgroundHandler);
            } catch (CameraAccessException e) {
                Log.e(TAG, "Failed to update flash mode", e);
            }
        }
    }

    /**
     * Switch camera (requires restart)
     */
    public void switchCamera() {

        // Switch facing
        mCurrentCameraFacing = (mCurrentCameraFacing == CameraCharacteristics.LENS_FACING_FRONT)
                ? CameraCharacteristics.LENS_FACING_BACK
                : CameraCharacteristics.LENS_FACING_FRONT;
        stopCamera();
        startCamera();
    }

    /**
     * Set camera facing (front/back)
     * Use this before calling startCamera() to control which camera opens
     */
    public void setFacing(int facing) {
        mCurrentCameraFacing = facing;
    }

    /**
     * Set camera to front facing
     */
    public void setFrontFacing() {
        mCurrentCameraFacing = CameraCharacteristics.LENS_FACING_FRONT;
    }

    /**
     * Set camera to back facing
     */
    public void setBackFacing() {
        mCurrentCameraFacing = CameraCharacteristics.LENS_FACING_BACK;
    }

    /**
     * Get the best FPS range supported by device
     * Priority: 30 FPS > 25 FPS > highest available
     */
    private Range<Integer> getBestFpsRange() {
        if (mCameraCharacteristics == null) {
            return new Range<>(15, 30);
        }

        try {
            // Get all supported FPS ranges
            Range<Integer>[] fpsRanges = mCameraCharacteristics.get(
                    CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES);
            if (fpsRanges == null || fpsRanges.length == 0) {
                return new Range<>(15, 30);
            }

            // Priority 1: Try to find 30 FPS fixed
            for (Range<Integer> range : fpsRanges) {
                if (range.getLower() >= 30 && range.getUpper() >= 30) {
                    return new Range<>(30, 30);
                }
            }

            // Priority 2: Try to find range that includes 30 FPS
            for (Range<Integer> range : fpsRanges) {
                if (range.getLower() <= 30 && range.getUpper() >= 30) {
                    return range;
                }
            }

            // Priority 3: Find highest available FPS
            Range<Integer> bestRange = fpsRanges[0];
            for (Range<Integer> range : fpsRanges) {
                if (range.getUpper() > bestRange.getUpper()) {
                    bestRange = range;
                }
            }

            return bestRange;

        } catch (Exception e) {
            Log.e(TAG, "Error getting FPS ranges: " + e.getMessage());
            return new Range<>(15, 30);
        }
    }
}
