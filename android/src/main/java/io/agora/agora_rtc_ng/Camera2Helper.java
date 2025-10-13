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
import android.media.Image;
import android.media.ImageReader;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Log;
import android.util.Range;
import android.util.Size;
import android.view.Surface;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.app.ActivityCompat;

import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;

/**
 * Minimal Camera2 helper to feed YUV frames to NosmaiPreviewView.
 * Copied from reference implementation for standalone camera support.
 */
public class Camera2Helper {
    private static final String TAG = "Camera2Helper";

    public interface FrameCallback {
        void onFrameAvailable(ByteBuffer y, ByteBuffer u, ByteBuffer v,
                              int width, int height,
                              int yStride, int uStride, int vStride,
                              int uPixelStride, int vPixelStride);
    }

    private final Context context;
    private final boolean requestFront;
    private int currentFacing = CameraCharacteristics.LENS_FACING_FRONT;
    private CameraDevice cameraDevice;
    private CameraCaptureSession captureSession;
    private ImageReader imageReader;
    private Size previewSize;
    private HandlerThread bgThread;
    private Handler bgHandler;
    private final Semaphore cameraLock = new Semaphore(1);
    public int sensorOrientation = 0;
    private FrameCallback frameCallback;
    private Surface previewSurface;
    private int targetWidth = 1280;
    private int targetHeight = 720;
    private int retryCount = 0;
    private static final int MAX_RETRIES = 2;
    private long openSeq = 0;
    private boolean retryScheduled = false;
    private boolean stopped = false;
    private Runnable retryRunnable;

    public Camera2Helper(Context context, boolean isFront) {
        this.context = context.getApplicationContext();
        this.requestFront = isFront;
        this.currentFacing = isFront ? CameraCharacteristics.LENS_FACING_FRONT : CameraCharacteristics.LENS_FACING_BACK;
    }

    public void setFrameCallback(FrameCallback cb) { this.frameCallback = cb; }

    public int getSensorOrientation() { return sensorOrientation; }

    public boolean isFrontCamera() { return currentFacing == CameraCharacteristics.LENS_FACING_FRONT; }

    public int getPreviewWidth() { return previewSize != null ? previewSize.getWidth() : 0; }
    public int getPreviewHeight() { return previewSize != null ? previewSize.getHeight() : 0; }

    public void setPreviewSurface(@Nullable Surface surface) { this.previewSurface = surface; }
    
    public void setTargetDimensions(int width, int height) {
        this.targetWidth = width;
        this.targetHeight = height;
    }

    public void startCamera() { stopped = false; startBg(); openCamera(); }
    public void stopCamera() {
        stopped = true;
        cancelRetry();
        closeCamera();
        stopBg();
    }

    public void cancelRetry() {
        retryScheduled = false;
        if (bgHandler != null && retryRunnable != null) {
            bgHandler.removeCallbacks(retryRunnable);
        }
        retryRunnable = null;
    }

    private void startBg() {
        bgThread = new HandlerThread("CameraBg");
        bgThread.start();
        bgHandler = new Handler(bgThread.getLooper());
    }

    private void stopBg() {
        if (bgThread != null) {
            bgThread.quitSafely();
            try { bgThread.join(); } catch (InterruptedException ignore) {}
            bgThread = null; bgHandler = null;
        }
    }

    @SuppressLint("MissingPermission")
    private void openCamera() {
        if (ActivityCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            Log.e(TAG, "No camera permission");
            return;
        }
        CameraManager manager = (CameraManager) context.getSystemService(Context.CAMERA_SERVICE);
        try {
            retryScheduled = false;
            final long seq = ++openSeq;
            String cameraId = chooseCamera(manager);
            if (cameraId == null) { Log.e(TAG, "No camera found"); return; }
            CameraCharacteristics chars = manager.getCameraCharacteristics(cameraId);
            sensorOrientation = chars.get(CameraCharacteristics.SENSOR_ORIENTATION);
            StreamConfigurationMap map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
            Size[] sizes = map != null ? map.getOutputSizes(SurfaceTexture.class) : null;
            if (sizes == null) { Log.e(TAG, "No sizes"); return; }
            previewSize = chooseOptimalSize(sizes, targetWidth, targetHeight);

            imageReader = ImageReader.newInstance(previewSize.getWidth(), previewSize.getHeight(), ImageFormat.YUV_420_888, 3);
            imageReader.setOnImageAvailableListener(onImage, bgHandler);

            if (!cameraLock.tryAcquire(2500, TimeUnit.MILLISECONDS)) {
                throw new RuntimeException("Timeout locking camera open");
            }
            manager.openCamera(cameraId, new CameraDevice.StateCallback() {
                @Override public void onOpened(@NonNull CameraDevice camera) {
                    // Hold the lock while creating session to avoid races with close
                    if (seq != openSeq) {
                        Log.w(TAG, "Stale onOpened ignored; seq=" + seq + ", current=" + openSeq);
                        camera.close();
                        cameraLock.release();
                        return;
                    }
                    if (stopped) {
                        camera.close();
                        cameraLock.release();
                        return;
                    }
                    cameraDevice = camera;
                    try {
                        createSession();
                    } finally {
                        cameraLock.release();
                    }
                }
                @Override public void onDisconnected(@NonNull CameraDevice camera) {
                    cameraLock.release();
                    camera.close();
                    if (seq != openSeq) return;
                    cameraDevice = null;
                    scheduleRetry();
                }
                @Override public void onError(@NonNull CameraDevice camera, int error) {
                    cameraLock.release();
                    camera.close();
                    if (seq != openSeq) return;
                    cameraDevice = null;
                    Log.e(TAG, "camera error: " + error);
                    scheduleRetry();
                }
            }, bgHandler);
        } catch (Exception e) {
            Log.e(TAG, "openCamera failed", e);
            scheduleRetry();
        }
    }

    private String chooseCamera(CameraManager manager) throws CameraAccessException {
        for (String id : manager.getCameraIdList()) {
            CameraCharacteristics c = manager.getCameraCharacteristics(id);
            Integer facing = c.get(CameraCharacteristics.LENS_FACING);
            if (facing != null && facing == currentFacing) return id;
        }
        String[] ids = manager.getCameraIdList();
        return ids.length > 0 ? ids[0] : null;
    }

    private Size chooseOptimalSize(Size[] choices, int targetWidth, int targetHeight) {
        List<Size> bigEnough = new ArrayList<>();
        List<Size> notBigEnough = new ArrayList<>();
        
        // Target aspect ratio with tolerance
        float targetRatio = (float) targetHeight / targetWidth;
        float aspectTolerance = 0.1f;
        
        for (Size option : choices) {
            float optionRatio = (float) option.getHeight() / option.getWidth();
            
            // Check if aspect ratio is close enough
            if (Math.abs(optionRatio - targetRatio) <= aspectTolerance) {
                if (option.getWidth() >= targetWidth && option.getHeight() >= targetHeight) {
                    bigEnough.add(option);
                } else {
                    notBigEnough.add(option);
                }
            }
        }
        
        // Pick the smallest of those big enough, or if no one is big enough, pick the largest
        if (bigEnough.size() > 0) {
            return Collections.min(bigEnough, new Comparator<Size>() {
                @Override
                public int compare(Size a, Size b) {
                    return Long.signum((long) a.getWidth() * a.getHeight() - 
                                      (long) b.getWidth() * b.getHeight());
                }
            });
        } else if (notBigEnough.size() > 0) {
            return Collections.max(notBigEnough, new Comparator<Size>() {
                @Override
                public int compare(Size a, Size b) {
                    return Long.signum((long) a.getWidth() * a.getHeight() - 
                                      (long) b.getWidth() * b.getHeight());
                }
            });
        } else {
            // If no size matches aspect ratio, pick closest to target size
            Log.e(TAG, "No size matches aspect ratio, choosing closest");
            return choices[0];
        }
    }

    private void createSession() {
        try {
            if (cameraDevice == null || imageReader == null) return;
            List<Surface> targets = new ArrayList<>();
            Surface yuv = imageReader.getSurface();
            targets.add(yuv);
            if (previewSurface != null) targets.add(previewSurface);

            final CaptureRequest.Builder req = cameraDevice.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
            req.addTarget(yuv);
            if (previewSurface != null) req.addTarget(previewSurface);

            cameraDevice.createCaptureSession(targets, new CameraCaptureSession.StateCallback() {
                @Override public void onConfigured(@NonNull CameraCaptureSession session) {
                    captureSession = session;
                    try {
                        try { req.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, new Range<>(15, 30)); } catch (Exception ignored) {}
                        try { req.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE); } catch (Exception ignored) {}
                        session.setRepeatingRequest(req.build(), null, bgHandler);
                        retryCount = 0;
                    } catch (CameraAccessException e) {
                        Log.e(TAG, "setRepeatingRequest failed", e);
                        if (cameraDevice != null) {
                            try {
                                CaptureRequest.Builder simpleReq = cameraDevice.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
                                simpleReq.addTarget(yuv);
                                if (previewSurface != null) simpleReq.addTarget(previewSurface);
                                simpleReq.set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO);
                                session.setRepeatingRequest(simpleReq.build(), null, bgHandler);
                                Log.i(TAG, "Fallback to simple request succeeded");
                            } catch (Exception e2) {
                                Log.e(TAG, "Fallback also failed", e2);
                                scheduleRetry();
                            }
                        }
                    }
                }
                @Override public void onConfigureFailed(@NonNull CameraCaptureSession session) {
                    Log.e(TAG, "configureFailed");
                    scheduleRetry();
                }
            }, bgHandler);
        } catch (IllegalStateException e) {
            Log.e(TAG, "createSession illegal state (closed device)", e);
            scheduleRetry();
        } catch (CameraAccessException e) {
            Log.e(TAG, "createSession failed", e);
            scheduleRetry();
        }
    }

    private void closeCamera() {
        try { cameraLock.acquire(); } catch (InterruptedException ignore) {}
        try {
            if (captureSession != null) { captureSession.close(); captureSession = null; }
            if (cameraDevice != null) { cameraDevice.close(); cameraDevice = null; }
            if (imageReader != null) { imageReader.close(); imageReader = null; }
            previewSurface = null;
        } finally { cameraLock.release(); }
    }

    private final ImageReader.OnImageAvailableListener onImage = new ImageReader.OnImageAvailableListener() {
        @Override public void onImageAvailable(ImageReader reader) {
            Image image = null;
            try {
                image = reader.acquireLatestImage();
                if (image == null) return;
                if (frameCallback == null) { image.close(); return; }
                Image.Plane[] p = image.getPlanes();
                frameCallback.onFrameAvailable(
                        p[0].getBuffer(), p[1].getBuffer(), p[2].getBuffer(),
                        image.getWidth(), image.getHeight(),
                        p[0].getRowStride(), p[1].getRowStride(), p[2].getRowStride(),
                        p[1].getPixelStride(), p[2].getPixelStride()
                );
            } catch (Exception e) {
                Log.e(TAG, "onImageAvailable", e);
            } finally {
                if (image != null) image.close();
            }
        }
    };

    private void scheduleRetry() {
        if (stopped || retryCount >= MAX_RETRIES || retryScheduled) return;
        retryCount++;
        retryScheduled = true;
        Log.e(TAG, "Scheduling camera reopen, retry=" + retryCount);
        closeCamera();
        if (bgHandler != null) {
            retryRunnable = new Runnable() {
                @Override public void run() { retryScheduled = false; openCamera(); }
            };
            bgHandler.postDelayed(retryRunnable, 200);
        }
    }
}