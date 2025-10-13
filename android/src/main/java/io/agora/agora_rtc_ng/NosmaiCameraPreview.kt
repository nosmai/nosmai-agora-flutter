package io.agora.agora_rtc_ng

import android.content.Context
import android.widget.FrameLayout
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class NosmaiCameraPreviewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return NosmaiCameraPreviewView(context)
    }
}

class NosmaiCameraPreviewView(private val context: Context) : PlatformView {
    private val container = FrameLayout(context)

    init {
        // Setup GLSurfaceView for processed YUV preview
        NosmaiAgoraBridge.setupYuvPreview(container)
    }

    override fun getView(): android.view.View = container

    override fun dispose() {
        // no-op; GLSurfaceView cleanup handled by bridge if needed
    }
}
