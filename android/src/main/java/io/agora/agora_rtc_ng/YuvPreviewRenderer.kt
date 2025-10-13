package io.agora.agora_rtc_ng

import android.opengl.GLES20
import android.opengl.GLSurfaceView
import java.nio.ByteBuffer
import java.nio.ByteOrder
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean


class RgbaPreviewRenderer : GLSurfaceView.Renderer {
    private var program = 0
    private var posLoc = 0
    private var uvLoc = 0
    private var texLoc = 0
    private var vbo = 0
    private var tex = 0
    private val hasNewFrame = AtomicBoolean(false)
    @Volatile private var frame: ByteArray? = null
    @Volatile private var w = 0
    @Volatile private var h = 0
    @Volatile private var mirrorX = false
    @Volatile private var mirrorY = false
    @Volatile private var updateVbo = false

    fun submitFrame(rgba: ByteArray, width: Int, height: Int) {
        frame = rgba
        w = width
        h = height
        hasNewFrame.set(true)
    }

    fun resetTextureState() {
        lastW = 0
        lastH = 0
        hasNewFrame.set(false)
        android.util.Log.d("RgbaRenderer", "resetTextureState called")
    }

    fun setMirrorX(mirror: Boolean) { 
        if (mirrorX != mirror) {
            mirrorX = mirror
            updateVbo = true 
        }
    }
    fun setMirrorY(mirror: Boolean) { 
        if (mirrorY != mirror) {
            mirrorY = mirror
            updateVbo = true
        }
    }
    
    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        val vs = """
            attribute vec2 aPos;
            attribute vec2 aUV;
            varying vec2 vUV;
            void main(){
              vUV = aUV;
              gl_Position = vec4(aPos, 0.0, 1.0);
            }
        """
        val fs = """
            precision mediump float;
            varying vec2 vUV;
            uniform sampler2D uTex;
            void main(){
              gl_FragColor = texture2D(uTex, vUV);
            }
        """
        program = buildProgram(vs, fs)
        posLoc = GLES20.glGetAttribLocation(program, "aPos")
        uvLoc = GLES20.glGetAttribLocation(program, "aUV")
        texLoc = GLES20.glGetUniformLocation(program, "uTex")

        buildOrUpdateVbo(false)

        val texs = IntArray(1)
        GLES20.glGenTextures(1, texs, 0)
        tex = texs[0]
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, tex)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
    }

    private var lastW = 0
    private var lastH = 0
    private var uploadBuf: ByteBuffer? = null

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

        if (updateVbo) {
            buildOrUpdateVbo(mirrorX)
            updateVbo = false
        }
    
        val data = frame ?: return
        val width = w
        val height = h
        if (data.size < width * height * 4) return

        GLES20.glUseProgram(program)
        GLES20.glBindBuffer(GLES20.GL_ARRAY_BUFFER, vbo)
        GLES20.glEnableVertexAttribArray(posLoc)
        GLES20.glVertexAttribPointer(posLoc, 2, GLES20.GL_FLOAT, false, 16, 0)
        GLES20.glEnableVertexAttribArray(uvLoc)
        GLES20.glVertexAttribPointer(uvLoc, 2, GLES20.GL_FLOAT, false, 16, 8)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, tex)
        GLES20.glUniform1i(texLoc, 0)
        GLES20.glPixelStorei(GLES20.GL_UNPACK_ALIGNMENT, 1)
        if (uploadBuf == null || uploadBuf!!.capacity() < data.size) {
            uploadBuf = ByteBuffer.allocateDirect(data.size).order(ByteOrder.nativeOrder())
        }
        val bb = uploadBuf!!
        bb.clear(); bb.put(data); bb.position(0)
        if (width != lastW || height != lastH) {
            GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA, width, height,
                0, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, bb)
            lastW = width; lastH = height
        } else {
            GLES20.glTexSubImage2D(GLES20.GL_TEXTURE_2D, 0, 0, 0, width, height,
                GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, bb)
        }

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
    }

    private fun buildOrUpdateVbo(mirrorHoriz: Boolean) {
        val data = when {
            mirrorX && !mirrorY -> floatArrayOf(
                -1f, -1f, 1f, 1f,
                 1f, -1f, 0f, 1f,
                -1f,  1f, 1f, 0f,
                 1f,  1f, 0f, 0f
            )
            !mirrorX && mirrorY -> floatArrayOf(
                -1f, -1f, 0f, 0f,
                 1f, -1f, 1f, 0f,
                -1f,  1f, 0f, 1f,
                 1f,  1f, 1f, 1f
            )
            mirrorX && mirrorY -> floatArrayOf(
                -1f, -1f, 1f, 0f,
                 1f, -1f, 0f, 0f,
                -1f,  1f, 1f, 1f,
                 1f,  1f, 0f, 1f
            )
            else -> floatArrayOf( 
                -1f, -1f, 0f, 1f,
                 1f, -1f, 1f, 1f,
                -1f,  1f, 0f, 0f,
                 1f,  1f, 1f, 0f
            )
        }
        val buffers = IntArray(1)
        if (vbo == 0) { GLES20.glGenBuffers(1, buffers, 0); vbo = buffers[0] }
        GLES20.glBindBuffer(GLES20.GL_ARRAY_BUFFER, vbo)
        val fb = ByteBuffer.allocateDirect(data.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        fb.put(data).position(0)
        GLES20.glBufferData(GLES20.GL_ARRAY_BUFFER, data.size * 4, fb, GLES20.GL_DYNAMIC_DRAW)
        GLES20.glBindBuffer(GLES20.GL_ARRAY_BUFFER, 0)
    }
    
    
    private fun buildProgram(vsSrc: String, fsSrc: String): Int {
        fun compile(type: Int, src: String): Int {
            val sh = GLES20.glCreateShader(type)
            GLES20.glShaderSource(sh, src)
            GLES20.glCompileShader(sh)
            val status = IntArray(1)
            GLES20.glGetShaderiv(sh, GLES20.GL_COMPILE_STATUS, status, 0)
            if (status[0] == 0) {
                val log = GLES20.glGetShaderInfoLog(sh)
                GLES20.glDeleteShader(sh)
                throw RuntimeException("Shader compile failed: $log")
            }
            return sh
        }
        val vs = compile(GLES20.GL_VERTEX_SHADER, vsSrc)
        val fs = compile(GLES20.GL_FRAGMENT_SHADER, fsSrc)
        val prog = GLES20.glCreateProgram()
        GLES20.glAttachShader(prog, vs)
        GLES20.glAttachShader(prog, fs)
        GLES20.glLinkProgram(prog)
        val status = IntArray(1)
        GLES20.glGetProgramiv(prog, GLES20.GL_LINK_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES20.glGetProgramInfoLog(prog)
            GLES20.glDeleteProgram(prog)
            throw RuntimeException("Program link failed: $log")
        }
        GLES20.glDeleteShader(vs)
        GLES20.glDeleteShader(fs)
        return prog
    }
}
