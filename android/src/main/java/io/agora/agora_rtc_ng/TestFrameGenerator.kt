package io.agora.agora_rtc_ng

import android.util.Log

/**
 * TestFrameGenerator - Simple placeholder for test frame generation
 * This can be extended to generate test patterns if needed
 */
class TestFrameGenerator {
    companion object {
        private const val TAG = "TestFrameGenerator"
    }
    
    private var isRunning = false
    
    fun start() {
        isRunning = true
        Log.d(TAG, "Test frame generator started")
    }
    
    fun stop() {
        isRunning = false
        Log.d(TAG, "Test frame generator stopped")
    }
    
    fun isRunning(): Boolean = isRunning
}