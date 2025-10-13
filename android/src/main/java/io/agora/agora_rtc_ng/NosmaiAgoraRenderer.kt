package io.agora.agora_rtc_ng

import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.view.Surface
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.ShortBuffer
import javax.microedition.khronos.egl.EGL10
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.egl.EGLContext
import javax.microedition.khronos.egl.EGLDisplay
import javax.microedition.khronos.opengles.GL10
import android.content.Context
import android.util.Log
import com.nosmai.effect.api.NosmaiOffscreenSDK
import io.agora.rtc2.RtcEngine
import io.agora.rtc2.video.AgoraVideoFrame

class NosmaiAgoraRenderer(
    private val context: Context,
    private val rtcEngine: RtcEngine?
) : GLSurfaceView.Renderer {

    private val vertexShaderCode = """
        attribute vec4 vPosition;
        attribute vec2 vUv;
        varying vec2 uv;
        
        void main() {
            gl_Position = vPosition;
            uv = vUv;
        }
    """

    private val fragmentShaderCode = """
        #extension GL_OES_EGL_image_external : require
        precision mediump float;
        varying vec2 uv;
        uniform samplerExternalOES sampler;
        
        void main() {
            gl_FragColor = texture2D(sampler, uv);
        }
    """

    private val squareCoords = floatArrayOf(
        -1.0f, 1.0f, 0.0f,
        -1.0f, -1.0f, 0.0f,
        1.0f, -1.0f, 0.0f,
        1.0f, 1.0f, 0.0f
    )

    private val uvCoords = floatArrayOf(
        0.0f, 0.0f,
        0.0f, 1.0f,
        1.0f, 1.0f,
        1.0f, 0.0f
    )

    private val drawOrder = shortArrayOf(0, 1, 2, 0, 2, 3)

    private var vertexBuffer: FloatBuffer
    private var uvBuffer: FloatBuffer
    private var drawListBuffer: ShortBuffer
    private var program = 0
    private var texture = 0
    private var surfaceTexture: SurfaceTexture? = null
    private var surface: Surface? = null
    private var updateTexImage = false
    private var callInProgress = false
    private var eglContext: EGLContext? = null
    private var textureWidth = 720
    private var textureHeight = 1280
    private val transformMatrix = FloatArray(16)

    init {
        // Initialize vertex buffer
        val bb = ByteBuffer.allocateDirect(squareCoords.size * 4)
        bb.order(ByteOrder.nativeOrder())
        vertexBuffer = bb.asFloatBuffer()
        vertexBuffer.put(squareCoords)
        vertexBuffer.position(0)

        // Initialize UV buffer
        val uvbb = ByteBuffer.allocateDirect(uvCoords.size * 4)
        uvbb.order(ByteOrder.nativeOrder())
        uvBuffer = uvbb.asFloatBuffer()
        uvBuffer.put(uvCoords)
        uvBuffer.position(0)

        // Initialize draw order buffer
        val dlb = ByteBuffer.allocateDirect(drawOrder.size * 2)
        dlb.order(ByteOrder.nativeOrder())
        drawListBuffer = dlb.asShortBuffer()
        drawListBuffer.put(drawOrder)
        drawListBuffer.position(0)
    }

    override fun onSurfaceCreated(gl: GL10, config: EGLConfig) {
        GLES20.glClearColor(0.0f, 0.0f, 0.0f, 1.0f)

        // Create shader program
        val vertexShader = loadShader(GLES20.GL_VERTEX_SHADER, vertexShaderCode)
        val fragmentShader = loadShader(GLES20.GL_FRAGMENT_SHADER, fragmentShaderCode)
        program = GLES20.glCreateProgram().also {
            GLES20.glAttachShader(it, vertexShader)
            GLES20.glAttachShader(it, fragmentShader)
            GLES20.glLinkProgram(it)
        }

        // Set identity matrix
        android.opengl.Matrix.setIdentityM(transformMatrix, 0)
    }

    override fun onSurfaceChanged(gl: GL10, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)

        // Create texture for SurfaceTexture
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        texture = textures[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texture)

        textureWidth = width
        textureHeight = height

        // Set texture parameters
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)

        // Create SurfaceTexture and Surface
        surfaceTexture = SurfaceTexture(texture).apply {
            setDefaultBufferSize(width, height)
            setOnFrameAvailableListener {
                updateTexImage = true
            }
        }
        surface = Surface(surfaceTexture)

        // Set surface for Nosmai
        NosmaiOffscreenSDK.setRenderSurface(surface, width, height)
        NosmaiOffscreenSDK.setRenderRotation(0)
        // Ensure mirror is off in this renderer (we aren't using it for preview push)
        try { NosmaiOffscreenSDK.setMirrorX(false) } catch (_: Throwable) {}

        Log.d("NosmaiAgoraBridge", "Surface created: $width x $height, texture: $texture")
    }

    override fun onDrawFrame(gl: GL10) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

        if (updateTexImage) {
            updateTexImage = false
            surfaceTexture?.updateTexImage()
            surfaceTexture?.getTransformMatrix(transformMatrix)
        }

        // Draw the texture
        GLES20.glUseProgram(program)

        // Set vertex attributes
        val positionHandle = GLES20.glGetAttribLocation(program, "vPosition")
        GLES20.glEnableVertexAttribArray(positionHandle)
        GLES20.glVertexAttribPointer(positionHandle, 3, GLES20.GL_FLOAT, false, 12, vertexBuffer)

        val uvHandle = GLES20.glGetAttribLocation(program, "vUv")
        GLES20.glEnableVertexAttribArray(uvHandle)
        GLES20.glVertexAttribPointer(uvHandle, 2, GLES20.GL_FLOAT, false, 8, uvBuffer)

        // Set sampler
        val samplerHandle = GLES20.glGetUniformLocation(program, "sampler")
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texture)
        GLES20.glUniform1i(samplerHandle, 0)

        // Draw
        GLES20.glDrawElements(GLES20.GL_TRIANGLES, drawOrder.size, GLES20.GL_UNSIGNED_SHORT, drawListBuffer)

        // Cleanup
        GLES20.glDisableVertexAttribArray(positionHandle)
        GLES20.glDisableVertexAttribArray(uvHandle)

        // Push frame to Agora if in a call
        if (callInProgress && rtcEngine != null) {
            val frame = AgoraVideoFrame().apply {
                format = AgoraVideoFrame.FORMAT_TEXTURE_OES
                textureID = texture
                stride = textureWidth
                height = textureHeight
                // Pass EGL10 context captured by our ContextFactory (stable for Agora JNI)
                try { this.eglContext10 = eglContext } catch (_: Throwable) {}
                // Push from the same GL thread (sync mode)
                try { this.syncMode = true } catch (_: Throwable) {}
                transform = transformMatrix
                timeStamp = System.currentTimeMillis()
                rotation = 0
            }
            rtcEngine.pushExternalVideoFrame(frame)
        }
    }

    private fun loadShader(type: Int, shaderCode: String): Int {
        return GLES20.glCreateShader(type).also { shader ->
            GLES20.glShaderSource(shader, shaderCode)
            GLES20.glCompileShader(shader)
        }
    }

    fun setCallInProgress(inProgress: Boolean) {
        callInProgress = inProgress
    }

    // Context factory to capture EGLContext for Agora
    class ContextFactory(private val renderer: NosmaiAgoraRenderer) : GLSurfaceView.EGLContextFactory {
        override fun createContext(egl: EGL10, display: EGLDisplay, config: EGLConfig): EGLContext {
            val attribList = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL10.EGL_NONE)
            val context = egl.eglCreateContext(display, config, EGL10.EGL_NO_CONTEXT, attribList)
            renderer.eglContext = context
            return context
        }

        override fun destroyContext(egl: EGL10, display: EGLDisplay, context: EGLContext) {
            egl.eglDestroyContext(display, context)
        }
    }
}