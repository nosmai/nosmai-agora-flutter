package io.agora.agora_rtc_ng

import android.util.Log
import com.nosmai.effect.api.NosmaiBeauty
import com.nosmai.effect.api.NosmaiOffscreenSDK

/**
 * BeautyFilters - Manages beauty filter states and applications
 * This class provides a centralized way to handle all beauty filter operations
 */
class BeautyFilters {
    
    companion object {
        private const val TAG = "BeautyFilters"
    }
    
    // Filter state tracking
    private var skinSmoothingLevel: Float = 0.0f
    private var skinWhiteningLevel: Float = 0.0f
    private var faceSlimmingLevel: Float = 0.0f
    private var eyeEnlargementLevel: Float = 0.0f
    private var noseSizeLevel: Float = 0.0f
    private var brightnessLevel: Float = 0.0f
    private var contrastLevel: Float = 1.0f
    private var hueLevel: Float = 0.0f
    private var lipstickLevel: Float = 0.0f
    private var blusherLevel: Float = 0.0f
    
    // RGB filter values
    private var redMultiplier: Float = 1.0f
    private var greenMultiplier: Float = 1.0f
    private var blueMultiplier: Float = 1.0f
    
    // Additional filter values
    private var exposureLevel: Float = 0.0f
    private var saturationLevel: Float = 1.0f
    private var sharpenLevel: Float = 0.0f
    private var whiteBalanceTemp: Float = 5000.0f
    private var whiteBalanceTint: Float = 0.0f
    private var grayscaleEnabled: Boolean = false
    
    // Track if any filter is active
    private var isAnyFilterActive: Boolean = false
    
    /**
     * Apply skin smoothing filter
     * @param level 0.0 to 1.0 (normalized from iOS 0-10 range)
     */
    fun applySkinSmoothing(level: Float): Boolean {
        return try {
            skinSmoothingLevel = level.coerceIn(0.0f, 1.0f)
            // Apply via NosmaiBeauty SDK
            NosmaiBeauty.applySkinSmoothing(skinSmoothingLevel)
            Log.d(TAG, "Applied skin smoothing: $skinSmoothingLevel")
            updateFilterState()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply skin smoothing: ${e.message}")
            false
        }
    }
    
    /**
     * Apply skin whitening filter
     * @param level 0.0 to 1.0 (normalized from iOS 0-10 range)
     */
    fun applySkinWhitening(level: Float): Boolean {
        return try {
            skinWhiteningLevel = level.coerceIn(0.0f, 1.0f)
            // Apply via NosmaiBeauty SDK
            NosmaiBeauty.applySkinWhitening(skinWhiteningLevel)

            Log.d(TAG, "Applied skin whitening: $skinWhiteningLevel")
            updateFilterState()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply skin whitening: ${e.message}")
            false
        }
    }
    
    /**
     * Apply face slimming filter
     * @param level 0.0 to 1.0 (normalized from iOS 0-10 range)
     */
    fun applyFaceSlimming(level: Float): Boolean {
        return try {
            faceSlimmingLevel = level.coerceIn(0.0f, 1.0f)
            // Apply via NosmaiBeauty SDK
            NosmaiBeauty.applyFaceSlimming(faceSlimmingLevel)

            Log.d(TAG, "Applied face slimming: $faceSlimmingLevel")
            updateFilterState()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply face slimming: ${e.message}")
            false
        }
    }
    
    /**
     * Apply eye enlargement filter
     * @param level 0.0 to 1.0 (normalized from iOS 0-10 range)
     */
    fun applyEyeEnlargement(level: Float): Boolean {
        return try {
            eyeEnlargementLevel = level.coerceIn(0.0f, 1.0f)
            // Apply via NosmaiBeauty SDK
            NosmaiBeauty.applyEyeEnlargement(eyeEnlargementLevel)

            Log.d(TAG, "Applied eye enlargement: $eyeEnlargementLevel")
            updateFilterState()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply eye enlargement: ${e.message}")
            false
        }
    }
    
    /**
     * Apply nose size filter
     * @param level 0.0 to 1.0 (normalized from iOS 0-100 range)
     */
    fun applyNoseSize(level: Float): Boolean {
        return try {
            noseSizeLevel = level.coerceIn(0.0f, 1.0f)
            // Apply via NosmaiBeauty SDK
            NosmaiBeauty.applyNoseSize(noseSizeLevel)
   
            Log.d(TAG, "Applied nose size: $noseSizeLevel")
            updateFilterState()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply nose size: ${e.message}")
            false
        }
    }
    
    /**
     * Apply brightness filter
     * @param brightness -1.0 to 1.0
     */
    fun applyBrightness(brightness: Float): Boolean {
        return try {
            brightnessLevel = brightness.coerceIn(-1.0f, 1.0f)
            // Apply via NosmaiBeauty SDK
            NosmaiBeauty.applyBrightness(brightnessLevel)
          
            Log.d(TAG, "Applied brightness: $brightnessLevel")
            updateFilterState()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply brightness: ${e.message}")
            false
        }
    }
    
    /**
     * Apply contrast filter
     * @param contrast 0.0 to 2.0
     */
    fun applyContrast(contrast: Float): Boolean {
        return try {
            contrastLevel = contrast.coerceIn(0.0f, 2.0f)
            // Apply via NosmaiBeauty SDK
            NosmaiBeauty.applyContrast(contrastLevel)

            Log.d(TAG, "Applied contrast: $contrastLevel")
            updateFilterState()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply contrast: ${e.message}")
            false
        }
    }
    
    /**
     * Apply hue filter
     * @param hue Hue angle in degrees
     */
    fun applyHue(hue: Float): Boolean {
        return try {
            hueLevel = hue
            // Apply via NosmaiBeauty SDK
            NosmaiBeauty.applyHue(hueLevel)

            Log.d(TAG, "Applied hue: $hueLevel")
            updateFilterState()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply hue: ${e.message}")
            false
        }
    }
    
    /**
     * Apply RGB filter
     * @param red Red multiplier
     * @param green Green multiplier
     * @param blue Blue multiplier
     */
    fun applyRGB(red: Float, green: Float, blue: Float): Boolean {
        return try {
            redMultiplier = red
            greenMultiplier = green
            blueMultiplier = blue
            // Apply via NosmaiBeauty SDK
            NosmaiBeauty.applyRGB(redMultiplier, greenMultiplier, blueMultiplier)
            Log.d(TAG, "Applied RGB: R=$redMultiplier, G=$greenMultiplier, B=$blueMultiplier")
            updateFilterState()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply RGB filter: ${e.message}")
            false
        }
    }
    
    /**
     * Apply lipstick makeup
     * @param intensity 0.0 to 1.0 (normalized from iOS 0-100 range)
     */
    fun applyLipstick(intensity: Float): Boolean {
        return try {
            lipstickLevel = intensity.coerceIn(0.0f, 1.0f)
            // Apply via NosmaiBeauty SDK
            NosmaiBeauty.applyLipstick(lipstickLevel)
            
            Log.d(TAG, "Applied lipstick: $lipstickLevel")
            updateFilterState()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply lipstick: ${e.message}")
            false
        }
    }
    
    /**
     * Apply blusher makeup
     * @param intensity 0.0 to 1.0 (normalized from iOS 0-100 range)
     */
    fun applyBlusher(intensity: Float): Boolean {
        return try {
            blusherLevel = intensity.coerceIn(0.0f, 1.0f)
            // Apply via NosmaiBeauty SDK
            NosmaiBeauty.applyBlusher(blusherLevel)
         
            Log.d(TAG, "Applied blusher: $blusherLevel")
            updateFilterState()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply blusher: ${e.message}")
            false
        }
    }
    
    /**
     * Remove all beauty filters and reset to defaults
     */
    fun removeAllFilters(): Boolean {
        return try {
            // Reset all values to defaults
            skinSmoothingLevel = 0.0f
            skinWhiteningLevel = 0.0f
            faceSlimmingLevel = 0.0f
            eyeEnlargementLevel = 0.0f
            noseSizeLevel = 0.0f
            brightnessLevel = 0.0f
            contrastLevel = 1.0f
            hueLevel = 0.0f
            lipstickLevel = 0.0f
            blusherLevel = 0.0f
            redMultiplier = 1.0f
            greenMultiplier = 1.0f
            blueMultiplier = 1.0f
            
            // Remove all filters via NosmaiBeauty SDK
            NosmaiBeauty.removeAllBeautyFilters()
            
            // Also clear offscreen pipeline if active
            if (NosmaiOffscreenSDK.isActive()) {
                NosmaiOffscreenSDK.clearBeauty()
            }
            
            isAnyFilterActive = false
            Log.d(TAG, "All beauty filters removed")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to remove all filters: ${e.message}")
            false
        }
    }
    
    /**
     * Get current filter states as a map
     */
    fun getCurrentFilterStates(): Map<String, Float> {
        return mapOf(
            "skinSmoothing" to skinSmoothingLevel,
            "skinWhitening" to skinWhiteningLevel,
            "faceSlimming" to faceSlimmingLevel,
            "eyeEnlargement" to eyeEnlargementLevel,
            "noseSize" to noseSizeLevel,
            "brightness" to brightnessLevel,
            "contrast" to contrastLevel,
            "hue" to hueLevel,
            "lipstick" to lipstickLevel,
            "blusher" to blusherLevel,
            "redMultiplier" to redMultiplier,
            "greenMultiplier" to greenMultiplier,
            "blueMultiplier" to blueMultiplier
        )
    }
    
    /**
     * Check if any filter is currently active
     */
    fun hasActiveFilters(): Boolean = isAnyFilterActive
    
    /**
     * Update the filter state based on current values
     */
    private fun updateFilterState() {
        isAnyFilterActive = skinSmoothingLevel > 0.0f ||
                skinWhiteningLevel > 0.0f ||
                faceSlimmingLevel > 0.0f ||
                eyeEnlargementLevel > 0.0f ||
                noseSizeLevel > 0.0f ||
                brightnessLevel != 0.0f ||
                contrastLevel != 1.0f ||
                hueLevel != 0.0f ||
                lipstickLevel > 0.0f ||
                blusherLevel > 0.0f ||
                redMultiplier != 1.0f ||
                greenMultiplier != 1.0f ||
                blueMultiplier != 1.0f
    }
    
    /**
     * Apply a makeup blend level for specific filter types
     */
    fun applyMakeupBlendLevel(filterName: String, level: Float): Boolean {
        return try {
            when (filterName.lowercase()) {
                "lipstickfilter", "lipstick" -> applyLipstick(level / 100.0f)
                "blusherfilter", "blusher" -> applyBlusher(level / 100.0f)
                "skinsmoothing", "smoothing" -> applySkinSmoothing(level / 100.0f)
                "skinwhitening", "whitening" -> applySkinWhitening(level / 100.0f)
                else -> {
                    Log.w(TAG, "Unknown makeup filter: $filterName")
                    false
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply makeup blend level: ${e.message}")
            false
        }
    }
    
    /**
     * Apply exposure filter
     * @param exposure -10.0 to 10.0, 0 neutral
     */
    fun applyExposure(exposure: Float): Boolean {
        return try {
            exposureLevel = exposure.coerceIn(-10.0f, 10.0f)
            // Apply via NosmaiOffscreenSDK only (not available in NosmaiBeauty)
            if (NosmaiOffscreenSDK.isActive()) {
                NosmaiOffscreenSDK.setExposure(exposureLevel)
            }
            Log.d(TAG, "Applied exposure: $exposureLevel")
            updateFilterState()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply exposure: ${e.message}")
            false
        }
    }
    
    /**
     * Apply saturation filter
     * @param saturation 0.0 to 2.0, 1.0 neutral
     */
    fun applySaturation(saturation: Float): Boolean {
        return try {
            saturationLevel = saturation.coerceIn(0.0f, 2.0f)
            // Apply via NosmaiBeauty SDK
            NosmaiBeauty.applySaturation(saturationLevel)
            
            Log.d(TAG, "Applied saturation: $saturationLevel")
            updateFilterState()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply saturation: ${e.message}")
            false
        }
    }
    
    /**
     * Apply sharpen filter
     * @param sharpen 0.0 to 1.5 typical
     */
    fun applySharpen(sharpen: Float): Boolean {
        return try {
            sharpenLevel = sharpen.coerceIn(0.0f, 1.5f)
            // Apply via NosmaiBeauty SDK
            // NosmaiBeauty.applySharpening(sharpenLevel)
           
            Log.d(TAG, "Applied sharpen: $sharpenLevel")
            updateFilterState()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply sharpen: ${e.message}")
            false
        }
    }
    
    /**
     * Apply white balance filter
     * @param temperatureK Temperature in Kelvin (1000-12000)
     * @param tint Tint value (-200 to 200)
     */
    fun applyWhiteBalance(temperatureK: Float, tint: Float): Boolean {
        return try {
            whiteBalanceTemp = temperatureK.coerceIn(1000.0f, 12000.0f)
            whiteBalanceTint = tint.coerceIn(-200.0f, 200.0f)
            // Apply via NosmaiBeauty SDK
            NosmaiBeauty.applyWhiteBalance(whiteBalanceTemp, whiteBalanceTint)
           
            Log.d(TAG, "Applied white balance: temp=$whiteBalanceTemp, tint=$whiteBalanceTint")
            updateFilterState()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply white balance: ${e.message}")
            false
        }
    }
    
    /**
     * Enable/disable grayscale mode
     * @param enabled true for grayscale, false for color
     */
    fun setGrayscaleEnabled(enabled: Boolean): Boolean {
        return try {
            grayscaleEnabled = enabled
            // Apply via NosmaiBeauty SDK
            // NosmaiBeauty.applyGrayscaleFilter(enabled)
            // Also apply to offscreen pipeline if active
           
            Log.d(TAG, "Grayscale ${if (enabled) "enabled" else "disabled"}")
            updateFilterState()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set grayscale: ${e.message}")
            false
        }
    }
}