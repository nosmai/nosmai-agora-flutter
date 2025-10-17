package io.agora.agora_rtc_ng;

import android.content.Context;
import android.view.View;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;

import com.nosmai.effect.api.NosmaiPreviewView;

/**
 * Platform View Factory for Nosmai Camera Preview
 * Provides the native NosmaiPreviewView to Flutter
 */
public class NosmaiPlatformViewFactory extends PlatformViewFactory {

    private final NosmaiAgoraBridge bridge;

    public NosmaiPlatformViewFactory(NosmaiAgoraBridge bridge) {
        super(StandardMessageCodec.INSTANCE);
        this.bridge = bridge;
    }

    @NonNull
    @Override
    public PlatformView create(@NonNull Context context, int viewId, @Nullable Object args) {
        return new NosmaiPlatformView(context, bridge);
    }

    /**
     * PlatformView implementation that wraps NosmaiPreviewView
     */
    private static class NosmaiPlatformView implements PlatformView {
        private final NosmaiPreviewView previewView;
        private final NosmaiAgoraBridge bridge;

        NosmaiPlatformView(Context context, NosmaiAgoraBridge bridge) {
            this.bridge = bridge;
            this.previewView = bridge.getPreviewView();

            // If preview view doesn't exist yet, create a placeholder
            // The actual preview will be attached when camera starts
            if (this.previewView == null) {
                android.util.Log.w("NosmaiPlatformView",
                    "PreviewView not yet created - will be attached when camera starts");
            }
        }

        @NonNull
        @Override
        public View getView() {
            if (previewView != null) {
                return previewView;
            } else {
                // Return a placeholder view until camera starts
                android.widget.FrameLayout placeholder = new android.widget.FrameLayout(
                    bridge.getContext()
                );
                placeholder.setBackgroundColor(android.graphics.Color.BLACK);
                return placeholder;
            }
        }

        @Override
        public void dispose() {
            // Don't dispose the preview view here - it's managed by the bridge
            android.util.Log.d("NosmaiPlatformView", "Platform view disposed");
        }
    }
}
