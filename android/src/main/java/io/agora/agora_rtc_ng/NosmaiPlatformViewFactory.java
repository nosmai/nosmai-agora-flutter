package io.agora.agora_rtc_ng;

import android.content.Context;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.view.ViewParent;
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
        private final NosmaiAgoraBridge bridge;
        private final FrameLayout container;
        private final NosmaiPreviewView preview;

        NosmaiPlatformView(Context context, NosmaiAgoraBridge bridge) {
            this.bridge = bridge;
            this.container = new FrameLayout(context);
            this.container.setBackgroundColor(android.graphics.Color.BLACK);

            NosmaiPreviewView existing = bridge.getPreviewView();
            if (existing != null) {
                preview = existing;
            } else {
                preview = new NosmaiPreviewView(context);
                bridge.setPreviewView(preview);
            }
            attachPreview(preview);
        }

        @NonNull
        @Override
        public View getView() {
            return container;
        }

        @Override
        public void dispose() {
            if (preview != null && preview.getParent() == container) {
                container.removeView(preview);
            }
            bridge.clearPreviewView(preview);
        }

        private void attachPreview(@NonNull NosmaiPreviewView view) {
            ViewParent currentParent = view.getParent();
            if (currentParent instanceof ViewGroup) {
                ((ViewGroup) currentParent).removeView(view);
            }
            container.removeAllViews();
            container.addView(view, new FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
            ));

            view.requestLayout();
            view.requestRenderUpdate();
        }
    }
}
