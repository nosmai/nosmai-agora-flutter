package io.agora.agora_rtc_ng;

import android.content.Context;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import android.util.Log;
import com.nosmai.effect.api.NosmaiSDK;
import java.util.Map;
import java.util.HashMap;
import java.util.List;

/**
 * NosmaiAgoraPlugin - Flutter Plugin for Nosmai SDK + Agora Integration
 *
 * Handles method channel communication between Flutter and native Android
 * Supports dual mode: Camera Only and Live Streaming with filters
 */
public class NosmaiAgoraPlugin implements FlutterPlugin, MethodCallHandler {

    private static final String TAG = "NosmaiAgoraPlugin";
    private static final String CHANNEL_NAME = "nosmai_agora";

    private MethodChannel channel;
    private Context context;
    private NosmaiAgoraBridge bridge;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        context = flutterPluginBinding.getApplicationContext();
        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), CHANNEL_NAME);
        channel.setMethodCallHandler(this);

        // Initialize bridge singleton
        bridge = NosmaiAgoraBridge.getInstance(context);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        Log.i(TAG, "NosmaiAgoraPlugin detached from engine");
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        try {
            handleMethodCall(call, result);
        } catch (Exception e) {
            Log.e(TAG, "Error handling method: " + call.method, e);
            result.error("ERROR", e.getMessage(), null);
        }
    }

    private void handleMethodCall(@NonNull MethodCall call, @NonNull Result result) {

        // ============================================
        // SDK INITIALIZATION
        // ============================================

        if ("initialize".equals(call.method)) {
            String licenseKey = call.argument("licenseKey");
            boolean success = bridge.initialize(licenseKey);
            result.success(success);
        }

        else if ("initAgora".equals(call.method)) {
            String appId = call.argument("appId");
            boolean success = bridge.initAgora(appId);
            result.success(success);
        }

        else if ("releaseAgora".equals(call.method)) {
            boolean success = bridge.releaseAgora();
            result.success(success);
        }

        // ============================================
        // STREAMING CONTROL (Mode 2)
        // ============================================

        else if ("startCustomCamera".equals(call.method)) {
            String appId = call.argument("appId");
            String token = call.argument("token");
            String channelId = call.argument("channelId");
            Integer userId = call.argument("userId");
            Boolean startCameraImmediately = call.argument("startCameraImmediately");

            boolean success = bridge.startCustomCamera(
                appId != null ? appId : "",
                token != null ? token : "",
                channelId != null ? channelId : "",
                userId != null ? userId : 0,
                startCameraImmediately != null ? startCameraImmediately : true
            );
            result.success(success);
        }

        else if ("stopCustomCamera".equals(call.method)) {
            boolean success = bridge.stopCustomCamera();
            result.success(success);
        }

        else if ("teardownStreaming".equals(call.method)) {
            bridge.teardownStreaming();
            result.success(true);
        }

        // ============================================
        // CAMERA ONLY MODE (Mode 2 - No Streaming)
        // ============================================

        else if ("startCameraPreview".equals(call.method)) {
            boolean success = bridge.startCameraPreview();
            result.success(success);
        }

        else if ("stopCameraPreview".equals(call.method)) {
            boolean success = bridge.stopCameraPreview();
            result.success(success);
        }

        // ============================================
        // AGORA CONTROLS
        // ============================================

        else if ("enableVideo".equals(call.method)) {
            boolean success = bridge.enableVideo();
            result.success(success);
        }

        else if ("enableLocalVideo".equals(call.method)) {
            Boolean enabled = call.argument("enabled");
            boolean success = bridge.enableLocalVideo(enabled != null ? enabled : false);
            result.success(success);
        }

        else if ("setClientRole".equals(call.method)) {
            Integer role = call.argument("role");
            boolean success = bridge.setClientRole(role != null ? role : 1);
            result.success(success);
        }

        else if ("joinChannel".equals(call.method)) {
            String token = call.argument("token");
            String channelId = call.argument("channelId");
            Integer userId = call.argument("userId");

            boolean success = bridge.joinChannel(
                token != null ? token : "",
                channelId != null ? channelId : "",
                userId != null ? userId : 0
            );
            result.success(success);
        }

        else if ("leaveChannel".equals(call.method)) {
            boolean success = bridge.leaveChannel();
            result.success(success);
        }

        // ============================================
        // CAMERA CONTROLS
        // ============================================

        else if ("flipCamera".equals(call.method)) {
            boolean success = bridge.flipCamera();
            result.success(success);
        }

        else if ("switchCamera".equals(call.method)) {
            boolean success = bridge.switchCamera();
            result.success(success);
        }

        else if ("muteMicrophone".equals(call.method)) {
            Boolean muted = call.argument("muted");
            boolean success = bridge.muteMicrophone(muted != null ? muted : false);
            result.success(success);
        }

        else if ("toggleMirror".equals(call.method)) {
            Boolean enabled = call.argument("enabled");
            boolean success = bridge.toggleMirror(enabled != null ? enabled : false);
            result.success(success);
        }

        // ============================================
        // BEAUTY FILTERS
        // ============================================

        else if ("applySkinSmoothing".equals(call.method)) {
            Double level = call.argument("level");
            boolean success = bridge.applySkinSmoothing(level != null ? level.floatValue() : 0.0f);
            result.success(success);
        }

        else if ("applySkinWhitening".equals(call.method)) {
            Double level = call.argument("level");
            boolean success = bridge.applySkinWhitening(level != null ? level.floatValue() : 0.0f);
            result.success(success);
        }

        else if ("applyFaceSlimming".equals(call.method)) {
            Double level = call.argument("level");
            boolean success = bridge.applyFaceSlimming(level != null ? level.floatValue() : 0.0f);
            result.success(success);
        }

        else if ("applyEyeEnlargement".equals(call.method)) {
            Double level = call.argument("level");
            boolean success = bridge.applyEyeEnlargement(level != null ? level.floatValue() : 0.0f);
            result.success(success);
        }

        else if ("applyNoseSize".equals(call.method)) {
            Double level = call.argument("level");
            boolean success = bridge.applyNoseSize(level != null ? level.floatValue() : 0.0f);
            result.success(success);
        }

        else if ("applyBrightness".equals(call.method)) {
            Double brightness = call.argument("brightness");
            boolean success = bridge.applyBrightness(brightness != null ? brightness.floatValue() : 0.0f);
            result.success(success);
        }

        else if ("applyContrast".equals(call.method)) {
            Double contrast = call.argument("contrast");
            boolean success = bridge.applyContrast(contrast != null ? contrast.floatValue() : 1.0f);
            result.success(success);
        }

        else if ("applyHue".equals(call.method)) {
            Double hue = call.argument("hue");
            boolean success = bridge.applyHue(hue != null ? hue.floatValue() : 0.0f);
            result.success(success);
        }

        else if ("applyRGB".equals(call.method)) {
            Double red = call.argument("red");
            Double green = call.argument("green");
            Double blue = call.argument("blue");
            boolean success = bridge.applyRGB(
                red != null ? red.floatValue() : 1.0f,
                green != null ? green.floatValue() : 1.0f,
                blue != null ? blue.floatValue() : 1.0f
            );
            result.success(success);
        }

        else if ("applyLipstick".equals(call.method)) {
            Double intensity = call.argument("intensity");
            boolean success = bridge.applyLipstick(intensity != null ? intensity.floatValue() : 0.0f);
            result.success(success);
        }

        else if ("applyBlusher".equals(call.method)) {
            Double intensity = call.argument("intensity");
            boolean success = bridge.applyBlusher(intensity != null ? intensity.floatValue() : 0.0f);
            result.success(success);
        }

        else if ("applyExposure".equals(call.method)) {
            Double exposure = call.argument("exposure");
            boolean success = bridge.applyExposure(exposure != null ? exposure.floatValue() : 0.0f);
            result.success(success);
        }

        else if ("applySaturation".equals(call.method)) {
            Double saturation = call.argument("saturation");
            boolean success = bridge.applySaturation(saturation != null ? saturation.floatValue() : 1.0f);
            result.success(success);
        }

        else if ("applySharpening".equals(call.method)) {
            Double sharpening = call.argument("sharpening");
            boolean success = bridge.applySharpening(sharpening != null ? sharpening.floatValue() : 0.0f);
            result.success(success);
        }

        else if ("applyWhiteBalance".equals(call.method)) {
            Double temperatureK = call.argument("temperatureK");
            Double tint = call.argument("tint");
            boolean success = bridge.applyWhiteBalance(
                temperatureK != null ? temperatureK.floatValue() : 5000.0f,
                tint != null ? tint.floatValue() : 0.0f
            );
            result.success(success);
        }

        else if ("setGrayscaleEnabled".equals(call.method)) {
            Boolean enabled = call.argument("enabled");
            boolean success = bridge.setGrayscaleEnabled(enabled != null ? enabled : false);
            result.success(success);
        }

        // ============================================
        // FILTER MANAGEMENT
        // ============================================

        else if ("applyFilter".equals(call.method)) {
            String path = call.argument("path");
            boolean success = bridge.applyFilter(path != null ? path : "");
            result.success(success);
        }

        else if ("removeAllFilters".equals(call.method)) {
            boolean success = bridge.removeAllFilters();
            result.success(success);
        }

        else if ("getLocalFilters".equals(call.method)) {
            List<Map<String, Object>> filters = bridge.getLocalFilters();
            result.success(filters);
        }

        else if ("getCloudFilters".equals(call.method)) {
            List<Map<String, Object>> filters = bridge.getCloudFilters();
            result.success(filters);
        }

        else if ("getFilters".equals(call.method)) {
            List<Map<String, Object>> filters = bridge.getFilters();
            result.success(filters);
        }

        else if ("downloadCloudFilter".equals(call.method)) {
            String filterId = call.argument("filterId");
            Map<String, Object> downloadResult = bridge.downloadCloudFilter(filterId != null ? filterId : "");
            result.success(downloadResult);
        }

        else if ("isCloudFilterEnabled".equals(call.method)) {
            boolean enabled = bridge.isCloudFilterEnabled();
            result.success(enabled);
        }

        // ============================================
        // FILTER STATUS
        // ============================================

        else if ("getCurrentFilterStates".equals(call.method)) {
            Map<String, Double> states = bridge.getCurrentFilterStates();
            result.success(states);
        }

        else if ("hasActiveFilters".equals(call.method)) {
            boolean hasFilters = bridge.hasActiveFilters();
            result.success(hasFilters);
        }

        else if ("isBeautyFilterEnabled".equals(call.method)) {
            boolean enabled = bridge.isBeautyFilterEnabled();
            result.success(enabled);
        }

        // ============================================
        // ADVANCED FILTERS
        // ============================================

        else if ("applyMakeupBlendLevel".equals(call.method)) {
            String filterName = call.argument("filterName");
            Double level = call.argument("level");
            boolean success = bridge.applyMakeupBlendLevel(
                filterName != null ? filterName : "",
                level != null ? level.floatValue() : 0.0f
            );
            result.success(success);
        }

        else if ("adjustHSB".equals(call.method)) {
            Double hue = call.argument("hue");
            Double saturation = call.argument("saturation");
            Double brightness = call.argument("brightness");
            boolean success = bridge.adjustHSB(
                hue != null ? hue.floatValue() : 0.0f,
                saturation != null ? saturation.floatValue() : 0.0f,
                brightness != null ? brightness.floatValue() : 0.0f
            );
            result.success(success);
        }

        else if ("resetHSBFilter".equals(call.method)) {
            boolean success = bridge.resetHSBFilter();
            result.success(success);
        }

        // ============================================
        // UTILITY METHODS
        // ============================================

        else if ("cleanup".equals(call.method)) {
            boolean success = bridge.cleanup();
            result.success(success);
        }

        else if ("getFlutterEngineInfo".equals(call.method)) {
            String info = bridge.getFlutterEngineInfo();
            result.success(info);
        }

        // ============================================
        // RECORDING AND PHOTO CAPTURE (Camera Mode)
        // ============================================

        else if ("startRecording".equals(call.method)) {
            boolean success = bridge.startRecording();
            result.success(success);
        }

        else if ("stopRecording".equals(call.method)) {
            // Pass Result object to bridge - it will return asynchronously from callback
            bridge.stopRecording(result);
        }

        else if ("capturePhoto".equals(call.method)) {
            Map<String, Object> photoResult = bridge.capturePhoto();
            result.success(photoResult);
        }

        else if ("saveImageToGallery".equals(call.method)) {
            // Get image data as byte array
            byte[] imageData = call.argument("imageData");
            String name = call.argument("name");

            if (imageData != null && name != null) {
                Map<String, Object> saveResult = bridge.saveImageToGallery(imageData, name);
                result.success(saveResult);
            } else {
                Map<String, Object> errorResult = new HashMap<>();
                errorResult.put("success", false);
                errorResult.put("error", "Missing imageData or name parameter");
                result.success(errorResult);
            }
        }

        else if ("saveVideoToGallery".equals(call.method)) {
            String videoPath = call.argument("videoPath");
            String name = call.argument("name");

            if (videoPath != null && name != null) {
                Map<String, Object> saveResult = bridge.saveVideoToGallery(videoPath, name);
                result.success(saveResult);
            } else {
                Map<String, Object> errorResult = new HashMap<>();
                errorResult.put("success", false);
                errorResult.put("error", "Missing videoPath or name parameter");
                result.success(errorResult);
            }
        }

        // ============================================
        // CAMERA CONFIGURATION AND FLASH/TORCH
        // ============================================

        else if ("configureCamera".equals(call.method)) {
            String position = call.argument("position");
            String sessionPreset = call.argument("sessionPreset");
            boolean success = bridge.configureCamera(
                position != null ? position : "front",
                sessionPreset != null ? sessionPreset : "high"
            );
            result.success(success);
        }

        else if ("hasFlash".equals(call.method)) {
            boolean hasFlash = bridge.hasFlash();
            result.success(hasFlash);
        }

        else if ("hasTorch".equals(call.method)) {
            boolean hasTorch = bridge.hasTorch();
            result.success(hasTorch);
        }

        else if ("setFlashMode".equals(call.method)) {
            String mode = call.argument("mode");
            boolean success = bridge.setFlashMode(mode != null ? mode : "off");
            result.success(success);
        }

        else if ("setTorchMode".equals(call.method)) {
            String mode = call.argument("mode");
            boolean success = bridge.setTorchMode(mode != null ? mode : "off");
            result.success(success);
        }

        else if ("getFlashMode".equals(call.method)) {
            String mode = bridge.getFlashMode();
            result.success(mode);
        }

        else if ("getTorchMode".equals(call.method)) {
            String mode = bridge.getTorchMode();
            result.success(mode);
        }

        else if ("startProcessing".equals(call.method)) {
            boolean success = bridge.startProcessing();
            result.success(success);
        }

        else if ("stopProcessing".equals(call.method)) {
            boolean success = bridge.stopProcessing();
            result.success(success);
        }

        else if ("detachCameraView".equals(call.method)) {
            boolean success = bridge.detachCameraView();
            result.success(success);
        }

        // ============================================
        // NOT IMPLEMENTED
        // ============================================

        else {
            Log.w(TAG, "Method not implemented: " + call.method);
            result.notImplemented();
        }
    }
}
