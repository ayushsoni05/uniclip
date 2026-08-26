package com.globalclipboard.global_clipboard

import android.accessibilityservice.AccessibilityService
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.view.accessibility.AccessibilityEvent

class ClipboardAccessibilityService : AccessibilityService() {

    private var clipboardManager: ClipboardManager? = null
    private var lastClipboardText: String? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        checkAndSyncClipboard()
    }

    private fun checkAndSyncClipboard() {
        try {
            val clip = clipboardManager?.primaryClip
            if (clip != null && clip.itemCount > 0) {
                val item = clip.getItemAt(0)
                val currentText = item.text?.toString()
                if (currentText != null && currentText.isNotEmpty() && currentText != lastClipboardText) {
                    lastClipboardText = currentText
                    MainActivity.onGlobalClipboardChanged?.invoke(currentText)
                }
            }
        } catch (e: Exception) {
            // Ignore background security errors gracefully
        }
    }

    override fun onInterrupt() {}
}
