/*
 * NosmaiEffectsEngine.h
 * Nosmai SDK Effects Management Interface
 *
 * Created by Nosmai SDK Team
 * Copyright © 2024 Nosmai. All rights reserved.
 */

#ifndef NOSMAI_EFFECTS_ENGINE_H
#define NOSMAI_EFFECTS_ENGINE_H

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "NosmaiTypes.h"

@class NosmaiSDK;

NS_ASSUME_NONNULL_BEGIN

/**
 * NosmaiEffectsEngine - Professional Effects and Filters Management
 *
 * This class provides a clean interface for applying and managing various
 * visual effects, filters, and enhancements.
 */
@interface NosmaiEffectsEngine : NSObject

#pragma mark - Properties

/**
 * Effects delegate for state changes and events
 */
@property(nonatomic, weak, nullable) id<NosmaiEffectsDelegate> delegate;

/**
 * Currently loaded Nosmai filter path
 */
@property(nonatomic, readonly, nullable) NSString* activeNosmaiFilterPath;

/**
 * Indicates if any effects are currently active
 */
@property(nonatomic, readonly) BOOL hasActiveEffects;

/**
 * Checks if the current SDK license permits the use of beauty features.
 * Use this to enable or disable UI elements related to beauty effects.
 *
 * @return YES if beauty features are licensed and available, NO otherwise.
 */
- (BOOL)isBeautyEffectEnabled;

/**
 * Checks if the current SDK license permits fetching and using cloud filters.
 *
 * @return YES if cloud filters are licensed and available, NO otherwise.
 */
- (BOOL)isCloudFilterEnabled;

#pragma mark - Initialization

/**
 * Initialize effects engine with internal SDK instance
 *
 * @param internalSDK The internal NosmaiSDK instance
 * @return Initialized effects engine instance
 */
- (instancetype)initWithInternalSDK:(NosmaiSDK*)internalSDK
    NS_DESIGNATED_INITIALIZER;

/**
 * Unavailable. Use initWithInternalSDK: instead.
 */
- (instancetype)init NS_UNAVAILABLE;

#pragma mark - Effect Loading

/**
 * Apply a Nosmai effect from .nosmai file
 *
 * @param effectPath Path to .nosmai effect file
 * @param completion Completion handler
 */
- (void)applyEffect:(NSString*)effectPath
         completion:(nullable NosmaiEffectLoadCompletion)completion;

/**
 * Unload current Nosmai filter
 */
- (void)unloadNosmaiFilter;

/**
 * Get available parameters for current effect
 *
 * @return Array of parameter dictionaries, nil if no effect active
 */
- (nullable NSArray<NSDictionary*>*)getEffectParameters;

/**
 * Set effect parameter
 *
 * @param parameterName Parameter name
 * @param value Parameter value
 * @return YES if successful
 */
- (BOOL)setEffectParameter:(NSString*)parameterName value:(float)value;

/**
 * Get effect parameter value
 *
 * @param parameterName Parameter name
 * @return Current value, or 0 if not found
 */
- (float)getEffectParameterValue:(NSString*)parameterName;

#pragma mark - Cloud Filters

/**
 * Get available cloud filters
 *
 * @param completion Completion handler with filters array and error
 */
- (void)getCloudFilters:(void (^)(NSArray<NSDictionary*>* _Nullable filters,
                                  NSError* _Nullable error))completion;

/**
 * Download cloud filter
 *
 * @param filterId Filter identifier
 * @param progress Progress callback (0.0 to 1.0)
 * @param completion Download completion handler
 */
- (void)downloadCloudFilter:(NSString*)filterId
                   progress:(nullable NosmaiDownloadProgress)progress
                 completion:(NosmaiDownloadCompletion)completion;

/**
 * Apply downloaded cloud filter
 *
 * @param filterId Filter identifier
 * @return YES if successful
 */
- (BOOL)applyCloudFilter:(NSString*)filterId;

/**
 * Check if cloud filter is downloaded
 *
 * @param filterId Filter identifier
 * @return YES if downloaded
 */
- (BOOL)isCloudFilterDownloaded:(NSString*)filterId;

/**
 * Get local path for downloaded cloud filter
 *
 * @param filterId Filter identifier
 * @return Local file path, nil if not downloaded
 */
- (nullable NSString*)getCloudFilterLocalPath:(NSString*)filterId;

/**
 * Remove downloaded cloud filter
 *
 * @param filterId Filter identifier
 * @return YES if successful
 */
- (BOOL)removeCloudFilter:(NSString*)filterId;

#pragma mark - Built-in Filters

/**
 * Applies a real-time RGB color adjustment.
 * This filter can be layered on top of other built-in filters.
 *
 * @param redAdjustment Value for red channel (1.0 is no change).
 * @param greenAdjustment Value for green channel (1.0 is no change).
 * @param blueAdjustment Value for blue channel (1.0 is no change).
 */
- (void)applyRGBFilterWithRed:(float)redAdjustment
                        green:(float)greenAdjustment
                         blue:(float)blueAdjustment;

/**
 * Adjusts the brightness of the image.
 *
 * @param brightness The brightness adjustment. -1.0 to 1.0, with 0.0 being no
 * change.
 */
- (void)applyBrightnessFilter:(float)brightness;

/**
 * Adjusts the contrast of the image.
 * This can be layered with other built-in filters.
 *
 * @param contrast The contrast level. Ranges from 0.0 to 4.0, with 1.0 being
 * normal.
 */
- (void)applyContrastFilter:(float)contrast;

/**
 * Adjusts the slimming effect on the face.
 * Requires face detection to be active.
 *
 * @param level The intensity of the face slimming effect. Ranges from 0.0 (no
 * effect) to 1.0 (max effect).
 */
- (void)applyFaceSlimming:(float)level;

/**
 * Adjusts the enlargement effect on the eyes.
 * Requires face detection to be active.
 *
 * @param level The intensity of the eye enlargement effect. Ranges from 0.0 (no
 * effect) to 1.0 (max effect).
 */
- (void)applyEyeEnlargement:(float)level;

/**
 * Adjusts the nose size.
 * Requires face detection to be active.
 *
 * @param level The nose size adjustment. Ranges from 0.0 to 100.0, with 50.0
 * being normal size.
 */
- (void)applyNoseSize:(float)level;

/**
 * Adjusts the skin smoothing (blur) level.
 *
 * @param level The intensity of the skin smoothing. Ranges from 0.0 (no effect)
 * to 1.0 (max effect).
 */
- (void)applySkinSmoothing:(float)level;

/**
 * Adjusts the skin whitening level.
 *
 * @param level The intensity of the skin whitening. Ranges from 0.0 (no effect)
 * to 1.0 (max effect).
 */
- (void)applySkinWhitening:(float)level;

/**
 * Adjusts the sharpening level of the image.
 *
 * @param level The intensity of the sharpening. Ranges from 0.0 (no effect)
 * to 1.0 (max effect).
 */
- (void)applySharpening:(float)level;

/**
 * Adjusts the blend level for makeup filters like lipstick or blusher.
 *
 * @param filterName The name of the makeup filter (e.g., "LipstickFilter",
 * "BlusherFilter").
 * @param level The blend intensity. Ranges from 0.0 (transparent) to 1.0
 * (opaque).
 */
- (void)applyMakeupBlendLevel:(NSString*)filterName level:(float)level;

/**
 * Applies a grayscale (black and white) effect.
 */
- (void)applyGrayscaleFilter;

/**
 * Rotates the hue of the image.
 *
 * @param hueAngle The angle of hue rotation in degrees, from 0 to 360.
 */
- (void)applyHue:(float)hueAngle;

/**
 * Adjusts the color temperature and tint of the image.
 *
 * @param temperature The color temperature. 4000 is cool, 6500 is normal.
 * @param tint The tint adjustment.
 */
- (void)applyWhiteBalanceWithTemperature:(float)temperature tint:(float)tint;

/**
 * Resets the HSB filter to its default state.
 */
- (void)resetHSBFilter;

/**
 * Adjusts the hue, saturation, and brightness using a single powerful filter.
 * Note: These adjustments are additive. Use resetHSBFilter to start fresh.
 *
 * @param hue The hue rotation in degrees [-360, 360].
 * @param saturation The saturation level [0.0, 2.0]. 1.0 is normal.
 * @param brightness The brightness level [0.0, 2.0]. 1.0 is normal.
 */
- (void)adjustHSBWithHue:(float)hue
              saturation:(float)saturation
              brightness:(float)brightness;

- (void)removeBuiltInFilters;

/**
 * Removes a single built-in filter from the active chain by its class name.
 *
 * @param filterName The class name of the filter to remove (e.g., "RGBFilter",
 * "ToonFilter").
 */
- (void)removeBuiltInFilterByName:(NSString*)filterName;

#pragma mark - Effect Management

/**
 * Remove all active effects and filters
 */
- (void)removeAllEffects;

/**
 * Get list of all active effects
 *
 * @return Dictionary with effect types and their values
 */
- (NSDictionary<NSString*, id>*)getActiveEffects;

/**
 * Save current effect configuration
 *
 * @return Configuration dictionary that can be restored later
 */
- (NSDictionary<NSString*, id>*)saveEffectConfiguration;

/**
 * Restore effect configuration
 *
 * @param configuration Previously saved configuration
 * @param completion Completion handler
 */
- (void)restoreEffectConfiguration:(NSDictionary<NSString*, id>*)configuration
                        completion:(nullable void (^)(BOOL success,
                                                      NSError* _Nullable error))
                                       completion;

#pragma mark - Utility

/**
 * Reset all effects to default values
 */
- (void)resetToDefaults;

/**
 * Enable or disable all effects temporarily
 *
 * @param enabled YES to enable, NO to disable
 */
- (void)setEffectsEnabled:(BOOL)enabled;

/**
 * Check if effects are currently enabled
 *
 * @return YES if effects are enabled
 */
- (BOOL)areEffectsEnabled;

@end

NS_ASSUME_NONNULL_END

#endif /* NOSMAI_EFFECTS_ENGINE_H */
