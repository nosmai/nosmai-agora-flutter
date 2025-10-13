package io.agora.agora_rtc_ng;

import android.content.Context;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import java.util.Map;
import java.util.HashMap;
import java.util.List;
import java.util.ArrayList;
import com.nosmai.effect.NosmaiEffects;
import com.nosmai.effect.api.NosmaiCloud;
import com.nosmai.effect.api.NosmaiBeauty;
import com.nosmai.effect.api.NosmaiSDK;
import com.nosmai.effect.api.NosmaiPreviewView;
import com.nosmai.effect.api.NosmaiOffscreenSDK;
import java.io.File;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;
import android.widget.FrameLayout;
import com.nosmai.effect.api.NosmaiPreviewView;

/**
 * Plugin bridge for Nosmai Agora integration
 * Provides Flutter method channels for beauty filters and streaming
 * functionality
 */
public class NosmaiAgoraPlugin implements FlutterPlugin, MethodCallHandler {
    private static final String CHANNEL = "nosmai_agora";

    private MethodChannel channel;
    private Context context;
    
    // Mode detection for dual routing (streaming vs standalone camera)
    private static boolean isStreamingMode = false;
    private static boolean isStandaloneMode = false;
    
    // Debug method to check current mode
    private static void logCurrentMode(String context) {
        android.util.Log.d("NosmaiMode", context + " - Current mode: streaming=" + isStreamingMode + ", standalone=" + isStandaloneMode);
    }

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        context = flutterPluginBinding.getApplicationContext();
        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);

        // NOTE: Platform view factory already registered in AgoraRtcNgPlugin.java
        // No need for duplicate registration here
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
    }


    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        try {
            switch (call.method) {
                // SDK Initialization
                case "initialize":
                    String licenseKey = call.argument("licenseKey");
                    boolean initResult = NosmaiAgoraBridge.INSTANCE.initNosmai(context, licenseKey);
                    
                    // Also store license key for standalone SDK initialization
                    if (initResult && licenseKey != null) {
                        NosmaiNativeCameraFactory.Companion.setStandaloneLicense(licenseKey);
                        android.util.Log.d("NosmaiMode", "License key stored for standalone SDK: " + licenseKey.substring(0, Math.min(8, licenseKey.length())) + "...");
                    }
                    
                    result.success(initResult);
                    break;

                case "initAgora":
                    String appId = call.argument("appId");
                    boolean agoraInitResult = NosmaiAgoraBridge.INSTANCE.initAgora(context, appId);
                    result.success(agoraInitResult);
                    break;

                case "releaseAgora":
                    NosmaiAgoraBridge.INSTANCE.releaseAgora();
                    result.success(true);
                    break;

                // Streaming Control
                case "startCustomCamera":
                    String startAppId = call.argument("appId");
                    String token = call.argument("token");
                    String channelId = call.argument("channelId");
                    Integer userId = call.argument("userId");
                    Boolean startCameraImmediately = call.argument("startCameraImmediately");
                    if (startCameraImmediately == null)
                        startCameraImmediately = true;
                    if (userId == null)
                        userId = 0;

                    boolean startResult = NosmaiAgoraBridge.INSTANCE.startCustomCamera(
                            context, startAppId, token, channelId, userId, startCameraImmediately);
                    
                    // Mark as streaming mode when streaming starts
                    if (startResult) {
                        isStreamingMode = true;
                        isStandaloneMode = false;
                        android.util.Log.d("NosmaiMode", "Mode set to STREAMING");
                    }
                    
                    result.success(startResult);
                    break;

                case "stopCustomCamera":
                    boolean stopResult = NosmaiAgoraBridge.INSTANCE.stopCustomCamera();
                    
                    // When streaming stops, we might switch back to standalone mode
                    if (stopResult) {
                        isStreamingMode = false;
                        android.util.Log.d("NosmaiMode", "Streaming stopped - mode cleared");
                    }
                    
                    result.success(stopResult);
                    break;

                case "teardownStreaming":
                    NosmaiAgoraBridge.INSTANCE.teardownStreaming();
                    result.success(true);
                    break;

                // Agora Controls
                case "enableVideo":
                    boolean enableVideoResult = NosmaiAgoraBridge.INSTANCE.enableVideo();
                    result.success(enableVideoResult);
                    break;

                case "enableLocalVideo":
                    Boolean enabled = call.argument("enabled");
                    boolean enableLocalVideoResult = NosmaiAgoraBridge.INSTANCE
                            .enableLocalVideo(enabled != null ? enabled : false);
                    result.success(enableLocalVideoResult);
                    break;

                case "startPreview":
                    boolean startPreviewResult = NosmaiAgoraBridge.INSTANCE.startPreview();
                    result.success(startPreviewResult);
                    break;

                case "stopPreview":
                    boolean stopPreviewResult = NosmaiAgoraBridge.INSTANCE.stopPreview();
                    result.success(stopPreviewResult);
                    break;

                case "setClientRole":
                    Integer role = call.argument("role");
                    boolean setClientRoleResult = NosmaiAgoraBridge.INSTANCE.setClientRole(role != null ? role : 1);
                    result.success(setClientRoleResult);
                    break;

                case "joinChannel":
                    String joinToken = call.argument("token");
                    String joinChannelId = call.argument("channelId");
                    Integer joinUserId = call.argument("userId");
                    boolean joinResult = NosmaiAgoraBridge.INSTANCE.joinChannel(
                            joinToken, joinChannelId, joinUserId != null ? joinUserId : 0);
                    result.success(joinResult);
                    break;

                case "leaveChannel":
                    boolean leaveResult = NosmaiAgoraBridge.INSTANCE.leaveChannel();
                    result.success(leaveResult);
                    break;

                // Beauty Filters
                case "applyBrightness":
                    Double brightness = call.argument("brightness");
                    boolean brightnessResult = NosmaiAgoraBridge.INSTANCE.applyBrightness(
                            brightness != null ? brightness.floatValue() : 0.0f);
                    result.success(brightnessResult);
                    break;

                case "applySkinSmoothing":
                    logCurrentMode("applySkinSmoothing called");
                    Double skinSmoothing = call.argument("level");
                    float smoothingLevel = skinSmoothing != null ? skinSmoothing.floatValue() : 0.0f;
                    boolean skinSmoothingResult;
                    
                    if (isStandaloneMode) {
                        // Standalone mode: use NosmaiBeauty API directly (like reference implementation)
                        try {
                            // Reference implementation normalizes 0-10 range to 0-1 range
                            float normalized = (smoothingLevel / 10.0f);
                            normalized = Math.max(0.0f, Math.min(1.0f, normalized)); // clamp to 0-1
                            NosmaiBeauty.applySkinSmoothing(normalized);
                            skinSmoothingResult = true;
                            android.util.Log.d("NosmaiMode", "Applied skin smoothing in STANDALONE mode: " + normalized);
                        } catch (Exception e) {
                            android.util.Log.e("NosmaiMode", "Error applying skin smoothing in standalone: " + e.getMessage());
                            skinSmoothingResult = false;
                        }
                    } else {
                        // Streaming mode: use NosmaiAgoraBridge (original behavior)
                        skinSmoothingResult = NosmaiAgoraBridge.INSTANCE.applySkinSmoothing(smoothingLevel);
                        android.util.Log.d("NosmaiMode", "Applied skin smoothing in STREAMING mode: " + smoothingLevel);
                    }
                    
                    result.success(skinSmoothingResult);
                    break;

                case "applySkinWhitening":
                    Double skinWhitening = call.argument("level");
                    float whiteningLevel = skinWhitening != null ? skinWhitening.floatValue() : 0.0f;
                    boolean skinWhiteningResult;
                    
                    if (isStandaloneMode) {
                        // Standalone mode: use NosmaiBeauty API directly
                        try {
                            float normalized = (whiteningLevel / 10.0f);
                            normalized = Math.max(0.0f, Math.min(1.0f, normalized));
                            NosmaiBeauty.applySkinWhitening(normalized);
                            skinWhiteningResult = true;
                            android.util.Log.d("NosmaiMode", "Applied skin whitening in STANDALONE mode: " + normalized);
                        } catch (Exception e) {
                            android.util.Log.e("NosmaiMode", "Error applying skin whitening in standalone: " + e.getMessage());
                            skinWhiteningResult = false;
                        }
                    } else {
                        // Streaming mode: use NosmaiAgoraBridge
                        skinWhiteningResult = NosmaiAgoraBridge.INSTANCE.applySkinWhitening(whiteningLevel);
                        android.util.Log.d("NosmaiMode", "Applied skin whitening in STREAMING mode: " + whiteningLevel);
                    }
                    
                    result.success(skinWhiteningResult);
                    break;

                case "applyFaceSlimming":
                    Double faceSlimming = call.argument("level");
                    float slimmingLevel = faceSlimming != null ? faceSlimming.floatValue() : 0.0f;
                    boolean faceSlimmingResult;
                    
                    if (isStandaloneMode) {
                        // Standalone mode: use NosmaiBeauty API directly
                        try {
                            float normalized = (slimmingLevel / 10.0f);
                            normalized = Math.max(0.0f, Math.min(1.0f, normalized));
                            NosmaiBeauty.applyFaceSlimming(normalized);
                            faceSlimmingResult = true;
                            android.util.Log.d("NosmaiMode", "Applied face slimming in STANDALONE mode: " + normalized);
                        } catch (Exception e) {
                            android.util.Log.e("NosmaiMode", "Error applying face slimming in standalone: " + e.getMessage());
                            faceSlimmingResult = false;
                        }
                    } else {
                        // Streaming mode: use NosmaiAgoraBridge
                        faceSlimmingResult = NosmaiAgoraBridge.INSTANCE.applyFaceSlimming(slimmingLevel);
                        android.util.Log.d("NosmaiMode", "Applied face slimming in STREAMING mode: " + slimmingLevel);
                    }
                    
                    result.success(faceSlimmingResult);
                    break;

                case "applyEyeEnlargement":
                    Double eyeEnlargement = call.argument("level");
                    float enlargementLevel = eyeEnlargement != null ? eyeEnlargement.floatValue() : 0.0f;
                    boolean eyeEnlargementResult;
                    
                    if (isStandaloneMode) {
                        // Standalone mode: use NosmaiBeauty API directly
                        try {
                            float normalized = (enlargementLevel / 10.0f);
                            normalized = Math.max(0.0f, Math.min(1.0f, normalized));
                            NosmaiBeauty.applyEyeEnlargement(normalized);
                            eyeEnlargementResult = true;
                            android.util.Log.d("NosmaiMode", "Applied eye enlargement in STANDALONE mode: " + normalized);
                        } catch (Exception e) {
                            android.util.Log.e("NosmaiMode", "Error applying eye enlargement in standalone: " + e.getMessage());
                            eyeEnlargementResult = false;
                        }
                    } else {
                        // Streaming mode: use NosmaiAgoraBridge
                        eyeEnlargementResult = NosmaiAgoraBridge.INSTANCE.applyEyeEnlargement(enlargementLevel);
                        android.util.Log.d("NosmaiMode", "Applied eye enlargement in STREAMING mode: " + enlargementLevel);
                    }
                    
                    result.success(eyeEnlargementResult);
                    break;

                case "applyNoseSize":
                    Double noseSize = call.argument("level");
                    float noseSizeLevel = noseSize != null ? noseSize.floatValue() : 0.0f;
                    boolean noseSizeResult;
                    
                    if (isStandaloneMode) {
                        // Standalone mode: use NosmaiBeauty API directly
                        try {
                            float normalized = (noseSizeLevel / 100.0f); // Note: nose size uses 0-100 range
                            normalized = Math.max(0.0f, Math.min(1.0f, normalized));
                            NosmaiBeauty.applyNoseSize(normalized);
                            noseSizeResult = true;
                            android.util.Log.d("NosmaiMode", "Applied nose size in STANDALONE mode: " + normalized);
                        } catch (Exception e) {
                            android.util.Log.e("NosmaiMode", "Error applying nose size in standalone: " + e.getMessage());
                            noseSizeResult = false;
                        }
                    } else {
                        // Streaming mode: use NosmaiAgoraBridge
                        noseSizeResult = NosmaiAgoraBridge.INSTANCE.applyNoseSize(noseSizeLevel);
                        android.util.Log.d("NosmaiMode", "Applied nose size in STREAMING mode: " + noseSizeLevel);
                    }
                    
                    result.success(noseSizeResult);
                    break;

                case "applyContrast":
                    Double contrast = call.argument("contrast");
                    boolean contrastResult = NosmaiAgoraBridge.INSTANCE.applyContrast(
                            contrast != null ? contrast.floatValue() : 1.0f);
                    result.success(contrastResult);
                    break;

                case "applyHue":
                    Double hue = call.argument("hue");
                    boolean hueResult = NosmaiAgoraBridge.INSTANCE.applyHue(
                            hue != null ? hue.floatValue() : 0.0f);
                    result.success(hueResult);
                    break;

                case "applyRGB":
                    Double red = call.argument("red");
                    Double green = call.argument("green");
                    Double blue = call.argument("blue");
                    boolean rgbResult = NosmaiAgoraBridge.INSTANCE.applyRGB(
                            red != null ? red.floatValue() : 1.0f,
                            green != null ? green.floatValue() : 1.0f,
                            blue != null ? blue.floatValue() : 1.0f);
                    result.success(rgbResult);
                    break;

                case "applyLipstick":
                    Double lipstick = call.argument("intensity");
                    boolean lipstickResult = NosmaiAgoraBridge.INSTANCE.applyLipstick(
                            lipstick != null ? lipstick.floatValue() : 0.0f);
                    result.success(lipstickResult);
                    break;

                case "applyBlusher":
                    Double blusher = call.argument("intensity");
                    boolean blusherResult = NosmaiAgoraBridge.INSTANCE.applyBlusher(
                            blusher != null ? blusher.floatValue() : 0.0f);
                    result.success(blusherResult);
                    break;

                case "applyExposure":
                    Double exposure = call.argument("exposure");
                    boolean exposureResult = NosmaiAgoraBridge.INSTANCE.applyExposure(
                            exposure != null ? exposure.floatValue() : 0.0f);
                    result.success(exposureResult);
                    break;

                case "applySaturation":
                    Double saturation = call.argument("saturation");
                    boolean saturationResult = NosmaiAgoraBridge.INSTANCE.applySaturation(
                            saturation != null ? saturation.floatValue() : 1.0f);
                    result.success(saturationResult);
                    break;

                case "applySharpen":
                    Double sharpen = call.argument("sharpen");
                    boolean sharpenResult = NosmaiAgoraBridge.INSTANCE.applySharpen(
                            sharpen != null ? sharpen.floatValue() : 0.0f);
                    result.success(sharpenResult);
                    break;

                case "applyWhiteBalance":
                    Double temperatureK = call.argument("temperatureK");
                    Double tint = call.argument("tint");
                    boolean whiteBalanceResult = NosmaiAgoraBridge.INSTANCE.applyWhiteBalance(
                            temperatureK != null ? temperatureK.floatValue() : 5000.0f,
                            tint != null ? tint.floatValue() : 0.0f);
                    result.success(whiteBalanceResult);
                    break;

                case "setGrayscaleEnabled":
                    Boolean grayscaleEnabled = call.argument("enabled");
                    boolean grayscaleResult = NosmaiAgoraBridge.INSTANCE.setGrayscaleEnabled(
                            grayscaleEnabled != null ? grayscaleEnabled : false);
                    result.success(grayscaleResult);
                    break;

                case "removeAllFilters":
                    boolean removeFiltersResult = NosmaiAgoraBridge.INSTANCE.removeAllFilters();
                    result.success(removeFiltersResult);
                    break;

                case "applyMakeupBlendLevel":
                    String filterName = call.argument("filterName");
                    Double level = call.argument("level");
                    boolean makeupResult = NosmaiAgoraBridge.INSTANCE.applyMakeupBlendLevel(
                            filterName != null ? filterName : "",
                            level != null ? level.floatValue() : 0.0f);
                    result.success(makeupResult);
                    break;

                // Status and Info
                case "getCurrentFilterStates":
                    Map<String, Float> filterStates = NosmaiAgoraBridge.INSTANCE.getCurrentFilterStates();
                    Map<String, Object> convertedStates = new HashMap<>();
                    for (Map.Entry<String, Float> entry : filterStates.entrySet()) {
                        convertedStates.put(entry.getKey(), entry.getValue().doubleValue());
                    }
                    result.success(convertedStates);
                    break;

                case "hasActiveFilters":
                    boolean hasActiveFilters = NosmaiAgoraBridge.INSTANCE.hasActiveFilters();
                    result.success(hasActiveFilters);
                    break;

                case "getFlutterEngineInfo":
                    String engineInfo = NosmaiAgoraBridge.INSTANCE.getFlutterEngineInfo();
                    result.success(engineInfo);
                    break;

                // Filter and effect methods
                case "getLocalFilters":
                    handleGetLocalFilters(result);
                    break;

                case "getCloudFilters":
                    handleGetCloudFilters(result);
                    break;

                case "getFilters":
                    handleGetFilters(result);
                    break;

                case "applyEffect":
                case "applyFilter":
                    String effectPath = call.argument("path");
                    handleApplyEffect(effectPath, result);
                    break;

                case "removeAllEffects":
                    if (isStandaloneMode) {
                        // Standalone mode: Follow the developer guide approach (lines 163-173)
                        try {
                            // Remove effect with callback like the guide shows
                            NosmaiEffects.removeEffect(new NosmaiEffects.EffectCallback() {
                                @Override
                                public void onSuccess() {
                                    android.util.Log.d("NosmaiMode", "✅ Effects removed successfully in STANDALONE mode");
                                    // Request refresh to show the effect removal in preview
                                    NosmaiNativeCameraFactory.Companion.requestRefresh();
                                    result.success(true);
                                }
                                
                                @Override
                                public void onError(String errorMessage) {
                                    android.util.Log.e("NosmaiMode", "❌ Effect removal failed in STANDALONE mode: " + errorMessage);
                                    result.success(false);
                                }
                            });
                        } catch (Exception e) {
                            android.util.Log.e("NosmaiMode", "Failed to remove effects in standalone: " + e.getMessage());
                            result.success(false);
                        }
                    } else {
                        // Streaming mode: use NosmaiAgoraBridge or fallback
                        try {
                            boolean removeResult = NosmaiAgoraBridge.INSTANCE.removeAllFilters();
                            android.util.Log.d("NosmaiMode", "Filters removed in STREAMING mode");
                            result.success(removeResult);
                        } catch (Exception e) {
                            android.util.Log.e("NosmaiMode", "Failed to remove filters in streaming: " + e.getMessage());
                            result.success(false);
                        }
                    }
                    break;

                case "isCloudFilterEnabled":
                    handleIsCloudFilterEnabled(result);
                    break;

                case "downloadCloudFilter":
                    String filterId = call.argument("filterId");
                    handleDownloadCloudFilter(filterId, result);
                    break;

                // Standalone Camera Support (for beauty filters only - no streaming)
                case "startCameraPreview":
                    // Mark as standalone mode when standalone camera starts
                    isStandaloneMode = true;
                    isStreamingMode = false;
                    android.util.Log.d("NosmaiMode", "Mode set to STANDALONE - beauty filters will use NosmaiBeauty API");
                    
                    // For standalone mode, we don't start streaming - just indicate success
                    // The actual camera is handled by NosmaiNativeCameraFactory platform view
                    result.success(true);
                    break;

                case "stopCameraPreview":
                    // When standalone camera stops, clear the mode
                    isStandaloneMode = false;
                    android.util.Log.d("NosmaiMode", "Standalone camera stopped - mode cleared");
                    
                    result.success(true);
                    break;

                case "switchCamera":
                    boolean switchResult = NosmaiAgoraBridge.INSTANCE.switchCamera();
                    result.success(switchResult);
                    break;

                // case "setFlashMode":
                // String flashMode = call.argument("flashMode");
                // boolean flashResult = NosmaiAgoraBridge.INSTANCE.setFlashMode(
                // flashMode != null ? flashMode : "off");
                // result.success(flashResult);
                // break;

                // case "setTorchMode":
                // String torchMode = call.argument("torchMode");
                // boolean torchResult = NosmaiAgoraBridge.INSTANCE.setTorchMode(
                // torchMode != null ? torchMode : "off");
                // result.success(torchResult);
                // break;

                // Core Streaming Methods (already defined as startCustomCamera and
                // stopCustomCamera above)
                case "startStreaming":
                    String streamingAppId = call.argument("appId");
                    String streamingToken = call.argument("token");
                    String streamingChannelId = call.argument("channelId");
                    Integer streamingUserId = call.argument("userId");
                    Boolean streamingStartCameraImmediately = call.argument("startCameraImmediately");
                    if (streamingStartCameraImmediately == null)
                        streamingStartCameraImmediately = true;
                    if (streamingUserId == null)
                        streamingUserId = 0;

                    boolean streamingResult = NosmaiAgoraBridge.INSTANCE.startCustomCamera(
                            context, streamingAppId, streamingToken, streamingChannelId, streamingUserId,
                            streamingStartCameraImmediately);
                    result.success(streamingResult);
                    break;

                case "stopStreaming":
                    boolean stopStreamingResult = NosmaiAgoraBridge.INSTANCE.stopCustomCamera();
                    result.success(stopStreamingResult);
                    break;


                // Camera Control Methods
                case "flipCamera":
                    boolean flipResult = NosmaiAgoraBridge.INSTANCE.switchCamera();
                    result.success(flipResult);
                    break;

                // Audio Control Methods
                case "muteMicrophone":
                    Boolean muteState = call.argument("muted");
                    boolean muteResult = NosmaiAgoraBridge.INSTANCE.enableLocalAudio(
                            muteState != null ? !muteState : true);
                    result.success(muteResult);
                    break;

                case "toggleMirror":
                    Boolean mirrorEnabled = call.argument("enabled");
                    // Mirror toggle is handled by flipCameraPreview for now
                    boolean mirrorResult = NosmaiAgoraBridge.INSTANCE.flipCameraPreview();
                    result.success(mirrorResult);
                    break;

                // HSB Adjustment Methods
                case "adjustHSB":
                    Double hsbHue = call.argument("hue");
                    Double hsbSaturation = call.argument("saturation");
                    Double hsbBrightness = call.argument("brightness");
                    // Implement HSB by applying individual filters
                    boolean hsbResult = true;
                    try {
                        if (hsbHue != null) {
                            hsbResult &= NosmaiAgoraBridge.INSTANCE.applyHue(hsbHue.floatValue());
                        }
                        if (hsbSaturation != null) {
                            hsbResult &= NosmaiAgoraBridge.INSTANCE.applySaturation(hsbSaturation.floatValue());
                        }
                        if (hsbBrightness != null) {
                            hsbResult &= NosmaiAgoraBridge.INSTANCE.applyBrightness(hsbBrightness.floatValue());
                        }
                    } catch (Exception e) {
                        hsbResult = false;
                    }
                    result.success(hsbResult);
                    break;


                // case "applySharpen":
                // Double sharpenValue = call.argument("sharpening");
                // boolean applySharpnessResult = NosmaiAgoraBridge.INSTANCE.applySharpen(
                // sharpenValue != null ? sharpenValue.floatValue() : 0.0f);
                // result.success(applySharpnessResult);
                // break;

                default:
                    result.notImplemented();
                    break;
            }
        } catch (Exception e) {
            result.error("NOSMAI_AGORA_ERROR", e.getMessage(), e.getStackTrace());
        }
    }

    // ============== FILTER IMPLEMENTATION METHODS ==============

    private void handleGetLocalFilters(Result result) {
        try {
            // Scan for .nosmai files in flutter assets
            List<Map<String, Object>> filters = new ArrayList<>();
            java.util.Set<String> seenFilters = new java.util.HashSet<>(); // Deduplication

            // Try to read AssetManifest.json to find filter assets
            try {
                String manifestJson = readAssetText("flutter_assets/AssetManifest.json");
                if (manifestJson != null) {
                    // Parse JSON manually (basic JSON parsing)
                    String[] lines = manifestJson.split("\"");
                    for (String line : lines) {
                        if (line.contains("assets/filters/") && line.endsWith(".nosmai")) {
                            String assetPath = line;
                            String name = extractFilterName(assetPath);

                            // Skip duplicates
                            if (seenFilters.contains(name)) {
                                continue;
                            }
                            seenFilters.add(name);

                            String displayName = toTitleCase(name);

                            // Try to get file size from asset
                            int fileSize = 0;
                            try {
                                java.io.InputStream inputStream = context.getAssets().open(assetPath);
                                fileSize = inputStream.available();
                                inputStream.close();
                            } catch (Exception e) {
                                // Use 0 if cannot determine size
                            }

                            Map<String, Object> filterMap = new HashMap<>();
                            filterMap.put("id", name);
                            filterMap.put("name", name);
                            filterMap.put("displayName", displayName);
                            filterMap.put("description", "Local filter");
                            filterMap.put("path", assetPath);
                            filterMap.put("fileSize", fileSize);
                            filterMap.put("type", "local");
                            filterMap.put("filterType", "effect");
                            filterMap.put("isDownloaded", true);
                            filterMap.put("isFree", true);
                            filterMap.put("isBuiltIn", true);

                            filters.add(filterMap);
                        }
                    }
                }
            } catch (Exception e) {
                // If manifest reading fails, return empty list
                android.util.Log.w("NosmaiAgoraPlugin", "Failed to read AssetManifest.json: " + e.getMessage());
            }

            android.util.Log.d("NosmaiAgoraPlugin", "Found " + filters.size() + " unique local filters");
            result.success(filters);
        } catch (Exception e) {
            result.error("LOCAL_FILTERS_ERROR", e.getMessage(), null);
        }
    }

    private void handleIsCloudFilterEnabled(Result result) {
        try {
            result.success(NosmaiCloud.isEnabled());
        } catch (Exception e) {
            result.success(false);
        }
    }

    private String mapCategoryToFilterType(String cat) {
        String c = (cat != null ? cat : "").toLowerCase();
        switch (c) {
            case "fx-and-filters":
            case "filter":
                return "filter";
            case "special-effects":
            case "beauty-effects":
            case "effect":
                return "effect";
            default:
                return "effect";
        }
    }

    private void handleGetCloudFilters(Result result) {
        try {
            java.util.List<?> list = NosmaiCloud.list();
            java.util.List<Map<String, Object>> out = new ArrayList<>();
            for (Object itemObj : list) {
                // Cast to get fields - in Kotlin this works with dynamic typing
                Object item = itemObj;
                // Use reflection to access fields since we don't have the exact class
                // definition
                String id = getFieldString(item, "id");
                String name = getFieldString(item, "name");
                String displayName = toTitleCase(name != null && !name.isEmpty() ? name : id);
                String type = "cloud";
                boolean downloaded = getFieldBoolean(item, "isDownloaded");
                String localPath = getFieldString(item, "localPath");
                String category = getFieldString(item, "category");
                String filterType = mapCategoryToFilterType(category);
                int fileSize = 0;
                try {
                    if (downloaded && localPath != null && !localPath.isEmpty()) {
                        fileSize = (int) new java.io.File(localPath).length();
                    }
                } catch (Exception e) {
                    fileSize = 0;
                }

                Map<String, Object> m = new HashMap<>();
                m.put("id", id);
                m.put("name", name);
                m.put("displayName", displayName);
                m.put("type", type);
                m.put("filterType", filterType);
                m.put("isDownloaded", downloaded);
                m.put("fileSize", fileSize);
                m.put("isFree", true);

                // Include path for downloaded filters
                if (downloaded && localPath != null && !localPath.isEmpty()) {
                    m.put("path", localPath);
                    m.put("localPath", localPath);
                    // Try preview extract for downloaded
                    try {
                        Object bmp = com.nosmai.effect.NosmaiFilterManager.loadPreviewImageForFilter(localPath);
                        if (bmp != null) {
                            m.put("previewImageBase64", bitmapToBase64(bmp));
                        }
                    } catch (Exception e) {
                        // Ignore preview errors
                    }
                }

                // ALWAYS include thumbnailUrl/previewUrl if available
                String thumbnailUrl = getFieldString(item, "thumbnailUrl");
                if (thumbnailUrl != null && !thumbnailUrl.isEmpty()) {
                    m.put("previewUrl", thumbnailUrl);
                    m.put("thumbnailUrl", thumbnailUrl);
                }

                out.add(m);
            }
            result.success(out);
        } catch (Exception e) {
            result.error("CLOUD_FILTERS_ERROR", e.getMessage(), null);
        }
    }

    private void handleDownloadCloudFilter(String filterId, Result result) {
        if (filterId == null || filterId.isEmpty()) {
            result.error("ARG_ERROR", "filterId required", null);
            return;
        }
        try {
            java.util.concurrent.CountDownLatch latch = new java.util.concurrent.CountDownLatch(1);
            final boolean[] ok = { false };
            final String[] path = { null };
            final String[] err = { null };

            NosmaiCloud.download(filterId, new NosmaiCloud.DownloadCallback() {
                @Override
                public void onComplete(String id, boolean success, String localPath, String error) {
                    ok[0] = success;
                    path[0] = localPath;
                    err[0] = error;
                    latch.countDown();
                }
            });

            latch.await();
            Map<String, Object> map = new HashMap<>();
            map.put("success", ok[0]);
            if (ok[0] && path[0] != null && !path[0].isEmpty()) {
                map.put("path", path[0]);
            }
            if (!ok[0] && err[0] != null && !err[0].isEmpty()) {
                map.put("error", err[0]);
            }
            result.success(map);
        } catch (Exception e) {
            Map<String, Object> errorMap = new HashMap<>();
            errorMap.put("success", false);
            errorMap.put("error", e.getMessage() != null ? e.getMessage() : "Unknown error");
            result.success(errorMap);
        }
    }

    private void handleGetFilters(Result result) {
        try {
            java.util.Map<String, ?> grouped = com.nosmai.effect.NosmaiEffects.getFilters();
            java.util.List<Map<String, Object>> out = new ArrayList<>();
            if (grouped != null) {
                for (Map.Entry<String, ?> entry : grouped.entrySet()) {
                    Object listObj = entry.getValue();
                    if (listObj instanceof java.util.List<?>) {
                        java.util.List<?> list = (java.util.List<?>) listObj;
                        for (Object item : list) {
                            if (item instanceof Map<?, ?>) {
                                Map<?, ?> m = (Map<?, ?>) item;
                                String name = getString(m, "name");
                                if (name == null || name.trim().isEmpty())
                                    continue;

                                String id = getString(m, "filterId");
                                if (id == null || id.isEmpty())
                                    id = name;

                                String displayName = getString(m, "displayName");
                                if (displayName == null || displayName.isEmpty())
                                    displayName = toTitleCase(name);

                                String type = getString(m, "type");
                                if (type == null)
                                    type = "local";
                                type = type.toLowerCase();

                                String path = getString(m, "localPath");
                                if (path == null)
                                    path = getString(m, "path");
                                if (path == null)
                                    path = "";

                                Object fileSizeObj = m.get("fileSize");
                                int fileSize = 0;
                                if (fileSizeObj instanceof Number) {
                                    fileSize = ((Number) fileSizeObj).intValue();
                                }

                                String filterType = getString(m, "filterType");
                                if (filterType == null) {
                                    filterType = mapCategoryToFilterType(getString(m, "category"));
                                }
                                filterType = filterType.toLowerCase();

                                Object downloadedObj = m.get("isDownloaded");
                                boolean downloaded = true;
                                if (downloadedObj instanceof Boolean) {
                                    downloaded = (Boolean) downloadedObj;
                                } else if ("cloud".equals(type)) {
                                    downloaded = false;
                                }

                                String previewB64 = getString(m, "previewBase64");
                                String thumbUrl = getString(m, "thumbnailUrl");

                                Map<String, Object> outMap = new HashMap<>();
                                outMap.put("id", id);
                                outMap.put("name", name);
                                outMap.put("displayName", displayName);
                                outMap.put("type", type);
                                outMap.put("filterType", filterType);
                                outMap.put("isDownloaded", downloaded);
                                outMap.put("fileSize", fileSize);
                                if (!path.isEmpty())
                                    outMap.put("path", path);

                                if (previewB64 != null && !previewB64.isEmpty()) {
                                    outMap.put("previewImageBase64", previewB64);
                                }

                                if (thumbUrl != null && !thumbUrl.isEmpty()) {
                                    outMap.put("previewUrl", thumbUrl);
                                    outMap.put("thumbnailUrl", thumbUrl);
                                }

                                out.add(outMap);
                            }
                        }
                    }
                }
            }
            result.success(out);
        } catch (Exception e) {
            result.error("GET_FILTERS_ERROR", e.getMessage(), null);
        }
    }

    private void handleApplyEffect(String effectPath, Result result) {
        try {
            android.util.Log.d("NosmaiAgoraPlugin", "Attempting to apply effect: " + effectPath);

            // First, copy the asset to cache directory if it's an asset path
            String actualPath = effectPath;
            if (effectPath.startsWith("assets/")) {
                actualPath = copyAssetToCache(effectPath);
                if (actualPath == null) {
                    android.util.Log.e("NosmaiAgoraPlugin", "Failed to copy asset to cache: " + effectPath);
                    result.success(false);
                    return;
                }
                android.util.Log.d("NosmaiAgoraPlugin", "Asset copied to: " + actualPath);
            }

            if (isStandaloneMode) {
                // Standalone mode: Follow the developer guide approach (lines 609-618)
                try {
                    // Make actualPath final for use in callback
                    final String finalPath = actualPath;
                    
                    // Apply effect with callback like the guide shows
                    NosmaiEffects.applyEffect(finalPath, new NosmaiEffects.EffectCallback() {
                        @Override
                        public void onSuccess() {
                            android.util.Log.d("NosmaiMode", "✅ Effect applied successfully in STANDALONE mode: " + finalPath);
                            // Request refresh to show the effect change in preview
                            NosmaiNativeCameraFactory.Companion.requestRefresh();
                            result.success(true);
                        }
                        
                        @Override
                        public void onError(String errorMessage) {
                            android.util.Log.e("NosmaiMode", "❌ Effect failed in STANDALONE mode: " + errorMessage);
                            result.success(false);
                        }
                    });
                } catch (Exception e) {
                    android.util.Log.e("NosmaiMode", "Error applying effect in standalone: " + e.getMessage());
                    result.success(false);
                }
            } else {
                // Streaming mode: Use offscreen pipeline (current behavior)
                try {
                    NosmaiEffects.applyEffect(actualPath);
                    android.util.Log.d("NosmaiMode", "Effect applied in STREAMING mode: " + actualPath);
                    result.success(true);
                } catch (Exception e) {
                    android.util.Log.e("NosmaiMode", "Error applying effect in streaming: " + e.getMessage());
                    result.success(false);
                }
            }

        } catch (Exception e) {
            android.util.Log.e("NosmaiAgoraPlugin", "Error in handleApplyEffect: " + e.getMessage());
            result.success(false);
        }
    }

    // ============== HELPER METHODS ==============

    private String readAssetText(String assetPath) {
        try {
            java.io.InputStream inputStream = context.getAssets().open(assetPath);
            java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.InputStreamReader(inputStream));
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line);
            }
            reader.close();
            return sb.toString();
        } catch (Exception e) {
            return null;
        }
    }

    private String extractFilterName(String assetPath) {
        // Extract filename without extension from path like
        // "assets/filters/vintage.nosmai"
        String[] parts = assetPath.split("/");
        String filename = parts[parts.length - 1];
        return filename.replace(".nosmai", "");
    }

    private String toTitleCase(String input) {
        if (input == null || input.isEmpty()) {
            return input;
        }
        StringBuilder titleCase = new StringBuilder();
        boolean nextTitleCase = true;

        for (char c : input.toCharArray()) {
            if (Character.isSpaceChar(c) || c == '_' || c == '-') {
                nextTitleCase = true;
                titleCase.append(' ');
            } else if (nextTitleCase) {
                titleCase.append(Character.toTitleCase(c));
                nextTitleCase = false;
            } else {
                titleCase.append(Character.toLowerCase(c));
            }
        }

        return titleCase.toString();
    }

    private String copyAssetToCache(String assetPath) {
        try {
            // Create cache directory for Nosmai filters
            java.io.File cacheDir = new java.io.File(context.getCacheDir(), "NosmaiLocalFilters");
            if (!cacheDir.exists()) {
                cacheDir.mkdirs();
            }

            // Get filename from asset path
            String fileName = assetPath.substring(assetPath.lastIndexOf('/') + 1);
            java.io.File outFile = new java.io.File(cacheDir, fileName);

            // If file already exists and has content, return its path
            if (outFile.exists() && outFile.length() > 0) {
                android.util.Log.d("NosmaiAgoraPlugin", "Using cached file: " + outFile.getAbsolutePath());
                return outFile.getAbsolutePath();
            }

            // For Flutter assets, we need to use the proper lookup key
            // Flutter assets are stored in "flutter_assets/" subdirectory
            String flutterAssetPath = assetPath;
            if (!assetPath.startsWith("flutter_assets/")) {
                flutterAssetPath = "flutter_assets/" + assetPath;
            }

            java.io.InputStream inputStream = null;

            // Try different paths to find the asset
            String[] pathsToTry = {
                    flutterAssetPath,
                    assetPath,
                    "flutter_assets/" + assetPath,
                    assetPath.replace("assets/", "flutter_assets/assets/")
            };

            for (String path : pathsToTry) {
                try {
                    inputStream = context.getAssets().open(path);
                    android.util.Log.d("NosmaiAgoraPlugin", "Found asset at: " + path);
                    break;
                } catch (Exception e) {
                    // Try next path
                }
            }

            if (inputStream == null) {
                android.util.Log.e("NosmaiAgoraPlugin", "Could not find asset in any of the tried paths");
                return null;
            }

            // Copy asset to cache
            java.io.FileOutputStream outputStream = new java.io.FileOutputStream(outFile);

            byte[] buffer = new byte[1024];
            int length;
            while ((length = inputStream.read(buffer)) > 0) {
                outputStream.write(buffer, 0, length);
            }

            outputStream.close();
            inputStream.close();

            android.util.Log.d("NosmaiAgoraPlugin", "Asset copied successfully: " + outFile.getAbsolutePath());
            return outFile.getAbsolutePath();

        } catch (Exception e) {
            android.util.Log.e("NosmaiAgoraPlugin", "Failed to copy asset to cache: " + e.getMessage());
            e.printStackTrace();
            return null;
        }
    }

    // Helper method for safe string extraction from maps
    private String getString(Map<?, ?> map, String key) {
        Object value = map.get(key);
        return value != null ? value.toString() : null;
    }

    // Helper methods for reflection-based field access (for NosmaiCloud objects)
    private String getFieldString(Object obj, String fieldName) {
        try {
            java.lang.reflect.Field field = obj.getClass().getField(fieldName);
            Object value = field.get(obj);
            return value != null ? value.toString() : null;
        } catch (Exception e) {
            return null;
        }
    }

    private boolean getFieldBoolean(Object obj, String fieldName) {
        try {
            java.lang.reflect.Field field = obj.getClass().getField(fieldName);
            Object value = field.get(obj);
            return value instanceof Boolean ? (Boolean) value : false;
        } catch (Exception e) {
            return false;
        }
    }

    private String bitmapToBase64(Object bitmap) {
        try {
            // This would need proper implementation based on the actual bitmap type
            // For now, return empty string to avoid compilation errors
            return "";
        } catch (Exception e) {
            return "";
        }
    }

}