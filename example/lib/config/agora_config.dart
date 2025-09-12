/// Agora configuration for the demo app
class AgoraConfig {
  /// Your Agora App ID
  /// Get your App ID from https://console.agora.io/
  static const String appId = 'YOUR_APPID_HERE';

  /// Your Agora Token (optional for testing)
  /// In production, you should generate tokens dynamically on your server
  static const String token = 'AGORA_TOKEN_HERE';

  /// Default channel ID for the demo
  static const String channelId = 'CHANNEL_NAME_HERE';

  /// Default user ID for the demo
  static const int uid = 0;

  /// Your Nosmai License Key
  /// Get your license key from Nosmai SDK provider
  /// IMPORTANT: Replace with your valid Nosmai license key
  static const String nosmaiLicenseKey = 'YOUR_NOSMAI_LICENSE_KEY_HERE';
}
