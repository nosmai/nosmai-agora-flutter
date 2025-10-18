# Nosmai + Agora Initialization Guide

## ⚠️ Common Issue: Double Engine Initialization

**Problem:** Creating multiple Agora engine instances causes crashes (SIGSEGV) during cleanup.

**Root Cause:** Calling both `Nosmai.initAgora()` and `createAgoraRtcEngine()` creates duplicate engines that conflict with each other.

---

## ✅ Correct Initialization Pattern

### Rule #1: Choose ONE initialization method per user role

- **Broadcaster (with GPU filters)**: Use `Nosmai.startStreaming()` ONLY
- **Viewer (remote watching)**: Use standard Agora `RtcEngine` ONLY

### Rule #2: NEVER mix both methods for the same user

❌ **WRONG:**
```dart
// DON'T DO THIS!
await Nosmai.initAgora(appId);           // Creates engine #1
RtcEngine engine = createAgoraRtcEngine(); // Creates engine #2
await engine.initialize(...);             // CONFLICT!
await Nosmai.startStreaming(...);         // Creates engine #3 - CRASH!
```

✅ **CORRECT:**
```dart
// For broadcasters - ONLY Nosmai
await Nosmai.initialize(licenseKey);
await Nosmai.startStreaming(appId, token, channelId, userId);
```

```dart
// For viewers - ONLY standard Agora
RtcEngine engine = createAgoraRtcEngine();
await engine.initialize(RtcEngineContext(appId: appId));
await engine.joinChannel(token: token, channelId: channelId, uid: userId);
```

---

## 📋 Implementation Patterns

### Pattern 1: Broadcaster Only App (Simplest)

**Use Case:** Single broadcaster streaming with GPU filters

```dart
class LiveStreamController extends GetxController {

  @override
  void onInit() {
    super.onInit();
    _initializeBroadcaster();
  }

  Future<void> _initializeBroadcaster() async {
    // Step 1: Initialize Nosmai SDK
    final initialized = await Nosmai.initialize('YOUR_LICENSE_KEY');
    if (!initialized) {
      print('Failed to initialize Nosmai');
      return;
    }

    // Step 2: Wait for stream ready, then start streaming
    // This is typically triggered by a socket event or button press
  }

  Future<void> startBroadcast(String appId, String token, String channel, int userId) async {
    // This handles ALL Agora initialization internally
    final started = await Nosmai.startStreaming(
      appId,
      token,
      channel,
      userId,
      startCameraImmediately: true,
    );

    if (started) {
      await Nosmai.enableVideo();
      print('✅ Broadcasting started');
    }
  }

  Future<void> stopBroadcast() async {
    await Nosmai.stopStreaming();
    await Nosmai.cleanup();
    print('✅ Broadcasting stopped');
  }

  @override
  void onClose() {
    stopBroadcast();
    super.onClose();
  }
}
```

**UI Widget:**
```dart
class BroadcasterView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Use NosmaiCameraPreview for local preview
        // autoStart: false because startStreaming() manages the camera
        NosmaiCameraPreview(autoStart: false),

        // Your UI controls here
      ],
    );
  }
}
```

---

### Pattern 2: Viewer Only App

**Use Case:** Users watching live streams (no broadcasting)

```dart
class ViewerController extends GetxController {
  RtcEngine? _engine;

  @override
  void onInit() {
    super.onInit();
    _initializeViewer();
  }

  Future<void> _initializeViewer() async {
    // Use standard Agora initialization
    _engine = createAgoraRtcEngine();

    await _engine!.initialize(
      RtcEngineContext(
        appId: 'YOUR_APP_ID',
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
      ),
    );

    await _engine!.enableVideo();

    // Set client role to AUDIENCE
    await _engine!.setClientRole(role: ClientRoleType.clientRoleAudience);
  }

  Future<void> joinStream(String token, String channel, int userId) async {
    await _engine!.joinChannel(
      token: token,
      channelId: channel,
      uid: userId,
      options: const ChannelMediaOptions(),
    );
    print('✅ Joined stream as viewer');
  }

  Future<void> leaveStream() async {
    await _engine?.leaveChannel();
    print('✅ Left stream');
  }

  @override
  void onClose() async {
    await _engine?.leaveChannel();
    await _engine?.release();
    super.onClose();
  }
}
```

**UI Widget:**
```dart
class ViewerView extends StatelessWidget {
  final int broadcasterUid;

  @override
  Widget build(BuildContext context) {
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: controller.engine,
        canvas: VideoCanvas(uid: broadcasterUid),
        connection: RtcConnection(channelId: channelId),
      ),
    );
  }
}
```

---

### Pattern 3: Full-Featured App (Broadcaster + Viewer + Multi-Guest)

**Use Case:** App supporting both broadcasting and viewing (like your app)

```dart
class LiveStreamController extends GetxController {
  RtcEngine? _rtcEngine;
  bool _isRtcEngineInitialized = false;
  bool _isNosmaiStreamingActive = false;

  // IMPORTANT: Separate initialization for different roles

  /// Initialize for BROADCASTER role
  Future<void> initAsBroadcaster() async {
    // Step 1: Initialize Nosmai SDK only
    final nosmaiInit = await Nosmai.initialize('YOUR_LICENSE_KEY');
    if (!nosmaiInit) {
      print('❌ Failed to initialize Nosmai');
      return;
    }

    // Step 2: DO NOT create RtcEngine here!
    // Nosmai.startStreaming() will handle it

    print('✅ Broadcaster initialized (waiting for stream start)');
  }

  /// Initialize for VIEWER role
  Future<void> initAsViewer() async {
    // For viewers, use standard Agora initialization
    _rtcEngine = createAgoraRtcEngine();

    await _rtcEngine!.initialize(
      RtcEngineContext(
        appId: 'YOUR_APP_ID',
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
      ),
    );

    await _rtcEngine!.enableVideo();
    await _rtcEngine!.setClientRole(role: ClientRoleType.clientRoleAudience);

    _isRtcEngineInitialized = true;
    print('✅ Viewer initialized');
  }

  /// Start broadcasting with Nosmai
  Future<void> startBroadcasting(String appId, String token, String channel, int userId) async {
    if (_isNosmaiStreamingActive) {
      print('⚠️ Already broadcasting');
      return;
    }

    final started = await Nosmai.startStreaming(
      appId,
      token,
      channel,
      userId,
      startCameraImmediately: true,
    );

    if (started) {
      await Nosmai.enableVideo();
      _isNosmaiStreamingActive = true;
      print('✅ Broadcasting started');
    }
  }

  /// Join as viewer
  Future<void> joinAsViewer(String token, String channel, int userId) async {
    if (_rtcEngine == null) {
      print('❌ Engine not initialized. Call initAsViewer() first');
      return;
    }

    await _rtcEngine!.joinChannel(
      token: token,
      channelId: channel,
      uid: userId,
      options: const ChannelMediaOptions(),
    );
    print('✅ Joined as viewer');
  }

  /// Promote viewer to broadcaster (multi-guest scenario)
  Future<void> promoteToGuest(String appId, String token, String channel, int userId) async {
    // First, leave as viewer if needed
    if (_isRtcEngineInitialized) {
      await _rtcEngine?.leaveChannel();
    }

    // Then start broadcasting with Nosmai
    await startBroadcasting(appId, token, channel, userId);
  }

  /// Proper cleanup
  Future<void> dispose() async {
    // Step 1: Stop Nosmai streaming if active
    if (_isNosmaiStreamingActive) {
      print('[Cleanup] Stopping Nosmai streaming...');
      await Nosmai.stopStreaming();
      await Nosmai.cleanup();
      _isNosmaiStreamingActive = false;
      print('[Cleanup] ✅ Nosmai cleaned up');
    }

    // Step 2: Release Flutter RTC engine if initialized
    if (_isRtcEngineInitialized && _rtcEngine != null) {
      print('[Cleanup] Releasing RTC engine...');
      await _rtcEngine!.leaveChannel();
      await _rtcEngine!.release();
      _rtcEngine = null;
      _isRtcEngineInitialized = false;
      print('[Cleanup] ✅ RTC engine released');
    }

    print('[Cleanup] ✅ Complete');
  }

  @override
  void onClose() {
    dispose();
    super.onClose();
  }
}
```

**UI Widget:**
```dart
class LiveStreamView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<LiveStreamController>();

    return Obx(() {
      // Show local broadcaster view (with GPU filters)
      if (controller.amIBroadcaster) {
        return NosmaiCameraPreview(autoStart: false);
      }

      // Show remote broadcaster view (standard Agora)
      return AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: controller.engine,
          canvas: VideoCanvas(uid: controller.broadcasterUid),
          connection: RtcConnection(channelId: controller.channelId),
        ),
      );
    });
  }
}
```

---

## 🔄 Proper Disposal Pattern

### Critical Rules:

1. **Always clean up in reverse order** of initialization
2. **Wait for async operations** to complete (DO NOT call dispose in background)
3. **Stop Nosmai BEFORE releasing Agora engine**

### ✅ Correct Disposal:

```dart
Future<void> cleanup() async {
  try {
    // Step 1: Stop Nosmai streaming
    if (_isNosmaiStreamingActive) {
      await Nosmai.stopStreaming();
      await Nosmai.cleanup();
      _isNosmaiStreamingActive = false;
    }

    // Step 2: Small delay for native threads to finish
    // (This is already handled in the native code, but good practice)
    await Future.delayed(Duration(milliseconds: 100));

    // Step 3: Release Flutter RTC engine
    if (_rtcEngine != null) {
      await _rtcEngine!.leaveChannel();
      await _rtcEngine!.release();
      _rtcEngine = null;
    }

    print('✅ Cleanup complete');
  } catch (e) {
    print('❌ Cleanup error: $e');
  }
}
```

### ❌ Common Disposal Mistakes:

```dart
// DON'T DO THIS - No await!
void cleanup() {
  Nosmai.stopStreaming();  // ❌ Missing await
  _rtcEngine?.release();   // ❌ Missing await
}

// DON'T DO THIS - Wrong order!
Future<void> cleanup() async {
  await _rtcEngine?.release();  // ❌ Released engine first
  await Nosmai.stopStreaming(); // ❌ Nosmai tries to access freed engine - CRASH!
}

// DON'T DO THIS - Calling in synchronous context!
@override
void onClose() {
  cleanup(); // ❌ Missing await - disposal happens in background!
  super.onClose();
}
```

---

## 🐛 Troubleshooting

### Issue: App crashes on dispose with SIGSEGV

**Symptoms:**
```
F/libc: Fatal signal 11 (SIGSEGV), code 2 (SEGV_ACCERR)
```

**Causes:**
1. ✅ **Multiple engine instances created** - Check you're not calling both `Nosmai.initAgora()` and `createAgoraRtcEngine()`
2. ✅ **Incorrect disposal order** - Always stop Nosmai BEFORE releasing RTC engine
3. ✅ **Missing await in cleanup** - Disposal must be fully awaited

**Solution:** Follow the patterns above exactly!

---

### Issue: Camera toggle causes black screen

**Symptoms:** Local preview goes black after toggling camera off/on

**Cause:** Widget disposing and recreating platform view

**Solution:** Use `Visibility` widget instead of conditional rendering:

```dart
// ❌ WRONG - Widget gets disposed
user.camera.value
  ? NosmaiCameraPreview(autoStart: false)
  : ProfilePicture()

// ✅ CORRECT - Widget stays in tree
Stack(
  children: [
    Visibility(
      visible: user.camera.value,
      maintainState: true,  // Keep platform view alive
      child: NosmaiCameraPreview(autoStart: false),
    ),
    if (!user.camera.value)
      ProfilePicture(),
  ],
)
```

---

### Issue: Double initialization detected

**Symptoms:**
```
I/NosmaiAgoraBridge: Nosmai already initialized
```

**Cause:** Calling `Nosmai.initialize()` multiple times

**Solution:** Initialize only once at app startup:

```dart
// main.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Nosmai SDK once
  await Nosmai.initialize('YOUR_LICENSE_KEY');

  runApp(MyApp());
}
```

---

## 📝 Quick Reference

| User Role | Initialization Method | Widget |
|-----------|----------------------|---------|
| Broadcaster (local with filters) | `Nosmai.startStreaming()` | `NosmaiCameraPreview(autoStart: false)` |
| Viewer (remote watching) | `createAgoraRtcEngine()` | `AgoraVideoView.remote()` |
| Guest (promoted viewer) | `Nosmai.startStreaming()` | `NosmaiCameraPreview(autoStart: false)` |

### Disposal Checklist:

- [ ] Stop Nosmai streaming first
- [ ] Wait for async cleanup
- [ ] Release RTC engine last
- [ ] All cleanup calls have `await`
- [ ] Cleanup called in async context

---

## 🎯 Summary

**Golden Rules:**

1. **One engine per user** - Never mix Nosmai and standard Agora initialization
2. **Broadcasters use Nosmai.startStreaming()** - It handles everything
3. **Viewers use createAgoraRtcEngine()** - Standard Agora flow
4. **Clean up in reverse order** - Nosmai first, RTC engine last
5. **Always await cleanup** - No fire-and-forget disposal

Follow these patterns and you'll avoid 99% of integration issues! 🚀

---

**Need help?** Check the example app at `/agora_nosmai_effects/lib/main.dart` for working reference implementations.
