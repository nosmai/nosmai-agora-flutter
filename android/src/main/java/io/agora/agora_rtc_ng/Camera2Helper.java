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
        startBackgroundThread();
        openCamera();
    }

    public void stopCamera() {
        Log.d(TAG, "Stopping camera...");
        try {
            closeCamera();
            stopBackgroundThread();
            Log.d(TAG, "✅ Camera stopped successfully");
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
                Log.e(TAG, "Interrupted when stopping background thread", e);
            }
        }
    }

    @SuppressLint("MissingPermission")
    private void openCamera() {
        if (ActivityCompat.checkSelfPermission(mContext, Manifest.permission.CAMERA)
                != PackageManager.PERMISSION_GRANTED) {
            Log.e(TAG, "❌ No camera permission");
            return;
        }

        CameraManager manager = (CameraManager) mContext.getSystemService(Context.CAMERA_SERVICE);
        try {
            String cameraId = getCameraId(manager);
            if (cameraId == null) {
                Log.e(TAG, "❌ Failed to find appropriate camera");
                return;
            }

            // Get camera characteristics
            mCameraCharacteristics = manager.getCameraCharacteristics(cameraId);
            StreamConfigurationMap map =
                    mCameraCharacteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
            if (map == null) {
                Log.e(TAG, "❌ Cannot get available preview sizes");
                return;
            }

            // Get sensor orientation
            mSensorOrientation = mCameraCharacteristics.get(CameraCharacteristics.SENSOR_ORIENTATION);
            Log.i(TAG, "📐 Sensor orientation: " + mSensorOrientation);

            mPreviewSize = chooseOptimalSize(map.getOutputSizes(SurfaceTexture.class), 1280, 720);
            Log.i(TAG, "📏 Preview size: " + mPreviewSize.getWidth() + "x" + mPreviewSize.getHeight());

            mImageReader = ImageReader.newInstance(
                    mPreviewSize.getWidth(), mPreviewSize.getHeight(),
                    ImageFormat.YUV_420_888, 3);
            mImageReader.setOnImageAvailableListener(mOnImageAvailableListener, mBackgroundHandler);

            if (!mCameraOpenCloseLock.tryAcquire(2500, TimeUnit.MILLISECONDS)) {
                throw new RuntimeException("Time out waiting to lock camera opening.");
            }

            manager.openCamera(cameraId, mStateCallback, mBackgroundHandler);

        } catch (CameraAccessException e) {
            Log.e(TAG, "❌ Failed to access camera", e);
        } catch (InterruptedException e) {
            Log.e(TAG, "❌ Interrupted while trying to lock camera opening", e);
        }
    }

    private String getCameraId(CameraManager manager) {
        try {
            for (String cameraId : manager.getCameraIdList()) {
                CameraCharacteristics characteristics = manager.getCameraCharacteristics(cameraId);
                Integer facing = characteristics.get(CameraCharacteristics.LENS_FACING);
                if (facing != null && facing == mCurrentCameraFacing) {
                    Log.i(TAG, "✅ Found camera: " + cameraId + " (facing: " +
                            (facing == CameraCharacteristics.LENS_FACING_FRONT ? "front" : "back") + ")");
                    return cameraId;
                }
            }
            if (manager.getCameraIdList().length > 0) {
                String fallbackId = manager.getCameraIdList()[0];
                Log.w(TAG, "⚠️ Requested camera not found, using fallback: " + fallbackId);
                return fallbackId;
            }
        } catch (CameraAccessException e) {
            Log.e(TAG, "❌ Failed to get camera ID", e);
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
            mCameraOpenCloseLock.release();
            mCameraDevice = cameraDevice;
            createCaptureSession();
            mIsCameraOpened = true;
            Log.i(TAG, "✅ Camera opened successfully");
        }

        @Override
        public void onDisconnected(@NonNull CameraDevice cameraDevice) {
            Log.w(TAG, "⚠️ Camera device disconnected - cleaning up resources");
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
            Log.e(TAG, "❌ Camera device error: " + error + " - cleaning up resources");
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
        try {
            if (mCameraDevice == null || mImageReader == null) return;

            // Build targets (always include YUV reader, optionally include OES preview surface)
            java.util.ArrayList<Surface> targets = new java.util.ArrayList<>();
            Surface yuvSurface = mImageReader.getSurface();
            targets.add(yuvSurface);
            if (mPreviewSurface != null) targets.add(mPreviewSurface);

            mPreviewRequestBuilder = mCameraDevice.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
            mPreviewRequestBuilder.addTarget(yuvSurface);
            if (mPreviewSurface != null) mPreviewRequestBuilder.addTarget(mPreviewSurface);

            mCameraDevice.createCaptureSession(
                    targets, new CameraCaptureSession.StateCallback() {
                        @Override
                        public void onConfigured(@NonNull CameraCaptureSession cameraCaptureSession) {
                            if (mCameraDevice == null) return;

                            mCaptureSession = cameraCaptureSession;
                            try {
                                // Get best supported FPS range for optimal performance
                                Range<Integer> fpsRange = getBestFpsRange();
                                Log.i(TAG, "📊 Using FPS range: " + fpsRange);
                                mPreviewRequestBuilder.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, fpsRange);

                                // Set auto-exposure and auto-focus for stability
                                mPreviewRequestBuilder.set(CaptureRequest.CONTROL_AE_MODE,
                                        CaptureRequest.CONTROL_AE_MODE_ON);
                                mPreviewRequestBuilder.set(CaptureRequest.CONTROL_AF_MODE,
                                        CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);

                                CaptureRequest request = mPreviewRequestBuilder.build();
                                mCaptureSession.setRepeatingRequest(request, null, mBackgroundHandler);

                                Log.i(TAG, "✅ Capture session configured successfully");

                            } catch (CameraAccessException e) {
                                Log.e(TAG, "❌ Failed to set up capture request", e);
                            }
                        }

                        @Override
                        public void onConfigureFailed(@NonNull CameraCaptureSession cameraCaptureSession) {
                            Log.e(TAG, "❌ Failed to configure capture session");
                        }
                    }, mBackgroundHandler);

        } catch (CameraAccessException e) {
            Log.e(TAG, "❌ Failed to create capture session", e);
        }
    }

    private void closeCamera() {
        try {
            mCameraOpenCloseLock.acquire();

            if (mCaptureSession != null) {
                mCaptureSession.close();
                mCaptureSession = null;
            }

            if (mCameraDevice != null) {
                mCameraDevice.close();
                mCameraDevice = null;
            }

            if (mImageReader != null) {
                mImageReader.close();
                mImageReader = null;
            }
            mPreviewSurface = null;

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
                        image = reader.acquireLatestImage();
                        if (image == null) {
                            return;
                        }

                        // A callback must be registered
                        if (mFrameCallback == null) {
                            image.close();
                            return;
                        }

                        final Image.Plane[] planes = image.getPlanes();

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
                        Log.e(TAG, "❌ Error in onImageAvailable: ", e);
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
                Log.e(TAG, "❌ Failed to update flash mode", e);
            }
        }
    }

    /**
     * Switch camera (requires restart)
     */
    public void switchCamera() {
        Log.i(TAG, "🔄 Switching camera...");

        // Switch facing
        mCurrentCameraFacing = (mCurrentCameraFacing == CameraCharacteristics.LENS_FACING_FRONT)
                ? CameraCharacteristics.LENS_FACING_BACK
                : CameraCharacteristics.LENS_FACING_FRONT;

        // Restart camera with new facing
        stopCamera();
        startCamera();

        Log.i(TAG, "✅ Camera switched to: " +
                (mCurrentCameraFacing == CameraCharacteristics.LENS_FACING_FRONT ? "front" : "back"));
    }

    /**
     * Get the best FPS range supported by device
     * Priority: 30 FPS > 25 FPS > highest available
     */
    private Range<Integer> getBestFpsRange() {
        if (mCameraCharacteristics == null) {
            Log.w(TAG, "⚠️ Camera characteristics not available, using default 15-30 FPS");
            return new Range<>(15, 30);
        }

        try {
            // Get all supported FPS ranges
            Range<Integer>[] fpsRanges = mCameraCharacteristics.get(
                    CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES);
            if (fpsRanges == null || fpsRanges.length == 0) {
                Log.w(TAG, "⚠️ No FPS ranges available, using default");
                return new Range<>(15, 30);
            }

            // Log all available FPS ranges for debugging
            Log.d(TAG, "📊 Available FPS ranges:");
            for (Range<Integer> range : fpsRanges) {
                Log.d(TAG, "   - " + range.getLower() + " to " + range.getUpper() + " FPS");
            }

            // Priority 1: Try to find 30 FPS fixed
            for (Range<Integer> range : fpsRanges) {
                if (range.getLower() >= 30 && range.getUpper() >= 30) {
                    Log.i(TAG, "✅ Selected: 30 FPS fixed range");
                    return new Range<>(30, 30);
                }
            }

            // Priority 2: Try to find range that includes 30 FPS
            for (Range<Integer> range : fpsRanges) {
                if (range.getLower() <= 30 && range.getUpper() >= 30) {
                    Log.i(TAG, "✅ Selected: Variable range with 30 FPS max");
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

            Log.i(TAG, "✅ Selected: Best available range " + bestRange);
            return bestRange;

        } catch (Exception e) {
            Log.e(TAG, "❌ Error getting FPS ranges: " + e.getMessage());
            return new Range<>(15, 30);
        }
    }
}
