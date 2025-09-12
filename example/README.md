# Nosmai Beauty Filters Demo

This Flutter application demonstrates the integration of Nosmai beauty filters with the Agora Flutter SDK. The demo showcases real-time video streaming with various beauty enhancement features.

## Features

- **Real-time Beauty Filters**: Apply various beauty filters in real-time during video streaming
- **Skin Enhancement**: Skin smoothing and whitening effects
- **Facial Adjustments**: Face slimming, eye enlargement, and nose size modifications
- **Color Adjustments**: Brightness, contrast, saturation, and hue controls
- **Makeup Effects**: Lipstick and blusher applications
- **Live Streaming**: Stream with filters to other users in real-time
- **Cross-Platform**: Works on both Android and iOS devices

## Prerequisites

Before running this demo, ensure you have:

1. **Flutter SDK** installed (version 3.8.1 or higher)
2. **Agora Account**: Get your App ID from [Agora Console](https://console.agora.io/)
3. **Nosmai License Key**: Obtain from your Nosmai SDK provider
4. **Android Studio** or **Xcode** for running on respective platforms

## Setup Instructions

### 1. Configure Agora and Nosmai

1. Open `lib/config/agora_config.dart`
2. Replace the placeholder values:
   ```dart
   static const String appId = 'YOUR_AGORA_APP_ID';           // Your Agora App ID
   static const String nosmaiLicenseKey = 'YOUR_NOSMAI_LICENSE_KEY'; // Your Nosmai License
   ```
3. Optionally, configure the token and channel settings for production use

### 2. Install Dependencies

```bash
cd /path/to/streaming/example
flutter pub get
```

### 3. Platform-Specific Setup

#### Android Setup
- Permissions are already configured in `android/app/src/main/AndroidManifest.xml`
- The demo uses the local Agora Flutter SDK with Nosmai integration
- Minimum SDK version: API 21 (Android 5.0)

#### iOS Setup
- Permissions are configured in `ios/Runner/Info.plist`
- The demo will use the Nosmai framework included in the Agora SDK
- Minimum iOS version: 9.0

### 4. Run the Demo

```bash
# For Android
flutter run -d android

# For iOS
flutter run -d ios
```

## Usage Guide

### Getting Started
1. Launch the app on your device
2. Grant camera and microphone permissions when prompted
3. Tap "Start Beauty Filters Demo" to enter the main screen

### Main Features

#### Video Preview
- **Local Video**: Shows your camera feed with applied filters
- **Remote Video**: Shows other users' streams (when connected)
- **Status Indicators**: 
  - SDK initialization status (Nosmai ✓/✗, Agora ✓/✗)
  - Streaming status (PREVIEW/STREAMING)

#### Controls
- **Start Streaming**: Begin streaming to the Agora channel
- **Stop Streaming**: End the streaming session
- **Reset Filters**: Clear all applied beauty filters

#### Beauty Filters

**Skin Enhancement:**
- **Skin Smoothing** (0.0 - 1.0): Reduces skin imperfections
- **Skin Whitening** (0.0 - 1.0): Lightens skin tone

**Facial Adjustments:**
- **Face Slimming** (0.0 - 1.0): Makes face appear slimmer
- **Eye Enlargement** (0.0 - 1.0): Makes eyes appear larger
- **Nose Size** (0.0 - 1.0): Adjusts nose size

**Color Adjustments:**
- **Brightness** (-1.0 - 1.0): Adjusts overall brightness
- **Contrast** (0.0 - 2.0): Adjusts color contrast
- **Saturation** (0.0 - 2.0): Adjusts color intensity
- **Hue** (-180° - 180°): Shifts color spectrum

**Makeup Effects:**
- **Lipstick** (0.0 - 1.0): Applies virtual lipstick
- **Blusher** (0.0 - 1.0): Applies virtual blush

#### Filter State Management
- **Get Filter States**: View current filter values
- **Real-time Adjustment**: All filters apply instantly as you move sliders
- **Persistent Settings**: Filter values are maintained during streaming

## Architecture

### Project Structure
```
lib/
├── config/
│   └── agora_config.dart          # Agora and Nosmai configuration
├── nosmai_beauty_filters_screen.dart # Main demo screen
└── main.dart                      # App entry point
```

### Integration Details

The demo uses:
- **Local Agora Flutter SDK**: Custom fork with Nosmai integration (`../Agora-Flutter-SDK`)
- **NosmaiIntegration Class**: Mock implementation for demonstration
- **Permission Handler**: Manages camera/microphone permissions
- **Material Design**: Modern Flutter UI components

### Key Components

1. **RTC Engine**: Manages Agora video/audio streaming
2. **Beauty Filters**: Real-time video processing with Nosmai SDK
3. **Video Views**: Local and remote video rendering
4. **Filter Controls**: Interactive sliders for real-time adjustment

## Troubleshooting

### Common Issues

**App ID Error**
- Ensure your Agora App ID is correctly set in `agora_config.dart`
- Verify the App ID matches your Agora Console project

**License Key Error**
- Confirm your Nosmai license key is valid and active
- Check with your Nosmai SDK provider for license status

**Permission Denied**
- Ensure camera and microphone permissions are granted
- Restart the app if permissions were initially denied

**Video Not Showing**
- Check if the device camera is being used by another app
- Verify the Agora SDK initialization is successful

**Filters Not Working**
- Confirm both Nosmai and Agora SDKs are initialized (check status indicators)
- Ensure the device supports the required OpenGL features

### Debug Information

The app logs debug information to the console. Enable debug mode to see:
- SDK initialization status
- Filter application results
- Streaming connection status
- Error messages and troubleshooting hints

```bash
flutter run --debug
```

## Production Considerations

For production deployment:

1. **Token Authentication**: Implement server-side token generation
2. **Error Handling**: Add comprehensive error handling and recovery
3. **Performance Optimization**: Profile and optimize for target devices  
4. **UI/UX Enhancement**: Customize the interface for your brand
5. **Analytics**: Add usage tracking and performance monitoring

## Support

For technical support:
- **Agora SDK**: [Agora Documentation](https://docs.agora.io/)
- **Flutter Issues**: Check the Flutter SDK repository
- **Nosmai Integration**: Contact your Nosmai SDK provider

## License

This demo application is provided for demonstration purposes. Please ensure you have proper licenses for:
- Agora RTC SDK usage
- Nosmai beauty filter SDK usage
- Any additional third-party libraries used