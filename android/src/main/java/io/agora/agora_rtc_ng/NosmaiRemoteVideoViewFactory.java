package io.agora.agora_rtc_ng;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.view.SurfaceView;
import android.view.View;
import android.widget.FrameLayout;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.util.Map;

import io.agora.rtc2.RtcEngine;
import io.agora.rtc2.video.VideoCanvas;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;

/**
 * Provides PlatformViews that render remote participants using the Nosmai-managed Agora engine.
 *
 * Once the host/guest is streaming via Nosmai (which owns the Agora engine), Flutter can no longer
 * access the engine instance directly. This factory produces SurfaceView backed PlatformViews that
 * bind to the internal engine so that remote co-host video can be rendered inside Flutter layouts.
 */
class NosmaiRemoteVideoViewFactory extends PlatformViewFactory {

    private static final String TAG = "NosmaiRemoteView";

    private final NosmaiAgoraBridge bridge;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    NosmaiRemoteVideoViewFactory(NosmaiAgoraBridge bridge) {
        super(StandardMessageCodec.INSTANCE);
        this.bridge = bridge;
    }

    @NonNull
    @Override
    public PlatformView create(@NonNull Context context, int viewId, @Nullable Object args) {
        int uid = 0;
        String channelId = null;
        if (args instanceof Map) {
            Object uidObj = ((Map<?, ?>) args).get("uid");
            if (uidObj instanceof Number) {
                uid = ((Number) uidObj).intValue();
            }
            Object channelObj = ((Map<?, ?>) args).get("channelId");
            if (channelObj instanceof String) {
                channelId = (String) channelObj;
            }
        }
        return new NosmaiRemoteVideoPlatformView(context, bridge, uid, channelId);
    }

    private final class NosmaiRemoteVideoPlatformView implements PlatformView {

        private final FrameLayout container;
        private final SurfaceView surfaceView;
        private final NosmaiAgoraBridge bridge;
        private final int remoteUid;
        @Nullable
        private final String channelId;

        NosmaiRemoteVideoPlatformView(
                Context context,
                NosmaiAgoraBridge bridge,
                int remoteUid,
                @Nullable String channelId
        ) {
            this.bridge = bridge;
            this.remoteUid = remoteUid;
            this.channelId = channelId;
            this.container = new FrameLayout(context);
            this.surfaceView = new SurfaceView(context);

            FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
            );
            container.addView(surfaceView, params);

            attachToEngine();
        }

        private void attachToEngine() {
            final RtcEngine engine = bridge.getAgoraEngine();
            if (engine == null) {
                android.util.Log.w(TAG, "Agora engine not ready yet. Will retry binding remote view (uid=" + remoteUid + ")");
                scheduleRetry();
                return;
            }

            mainHandler.post(() -> {
                try {
                    VideoCanvas canvas = new VideoCanvas(surfaceView, VideoCanvas.RENDER_MODE_HIDDEN, remoteUid);
                    engine.setupRemoteVideo(canvas);
                } catch (Exception e) {
                    android.util.Log.e(TAG, "Failed to bind remote view", e);
                }
            });
        }

        private int retryCount = 0;

        private void scheduleRetry() {
            if (retryCount >= 10) {
                android.util.Log.e(TAG, "Giving up binding remote view. Engine still null after retries");
                return;
            }
            retryCount++;
            mainHandler.postDelayed(this::attachToEngine, 300);
        }

        @NonNull
        @Override
        public View getView() {
            return container;
        }

        @Override
        public void dispose() {
            final RtcEngine engine = bridge.getAgoraEngine();
            if (engine == null) {
                return;
            }

            mainHandler.post(() -> {
                try {
                    VideoCanvas canvas = new VideoCanvas(null, VideoCanvas.RENDER_MODE_HIDDEN, remoteUid);
                    engine.setupRemoteVideo(canvas);
                } catch (Exception e) {
                    android.util.Log.w(TAG, "Error detaching remote view", e);
                }
            });
        }
    }
}
