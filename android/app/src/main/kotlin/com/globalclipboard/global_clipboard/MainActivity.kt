package com.globalclipboard.global_clipboard

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ClipboardManager
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.text.TextUtils

class MainActivity : FlutterActivity() {
    private val CLIPBOARD_CHANNEL = "com.globalclipboard/clipboard"
    private var clipboardMethodChannel: MethodChannel? = null
    private var clipboardManager: ClipboardManager? = null
    private var clipboardListener: ClipboardManager.OnPrimaryClipChangedListener? = null
    private var lastClipboardContent: String? = null

    companion object {
        var onGlobalClipboardChanged: ((String) -> Unit)? = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboardMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CLIPBOARD_CHANNEL)
        
        onGlobalClipboardChanged = { text ->
            runOnUiThread {
                if (text != lastClipboardContent) {
                    lastClipboardContent = text
                    clipboardMethodChannel?.invokeMethod("onClipboardChanged", mapOf("text" to text))
                }
            }
        }

        clipboardMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getClipboardText" -> {
                    try {
                        val text = getClipboardText()
                        result.success(text)
                    } catch (e: Exception) {
                        result.error("CLIPBOARD_ERROR", e.message, null)
                    }
                }
                "setClipboardText" -> {
                    try {
                        val text = call.argument<String>("text") ?: ""
                        setClipboardText(text)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CLIPBOARD_ERROR", e.message, null)
                    }
                }
                "startListening" -> {
                    startClipboardListening()
                    result.success(true)
                }
                "stopListening" -> {
                    stopClipboardListening()
                    result.success(true)
                }
                "startForegroundService" -> {
                    startClipboardForegroundService()
                    result.success(true)
                }
                "stopForegroundService" -> {
                    stopClipboardForegroundService()
                    result.success(true)
                }
                "isAccessibilityServiceEnabled" -> {
                    try {
                        val enabled = isAccessibilityServiceEnabled()
                        result.success(enabled)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "openAccessibilitySettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SETTINGS_ERROR", e.message, null)
                    }
                }
                "openBatteryOptimizationSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SETTINGS_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    
    private fun isAccessibilityServiceEnabled(): Boolean {
        try {
            val expectedServiceName = "${packageName}/${ClipboardAccessibilityService::class.java.canonicalName}"
            val enabledServicesSetting = Settings.Secure.getString(
                contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false
            
            val colonSplitter = TextUtils.SimpleStringSplitter(':')
            colonSplitter.setString(enabledServicesSetting)
            
            while (colonSplitter.hasNext()) {
                val componentName = colonSplitter.next()
                if (componentName.equals(expectedServiceName, ignoreCase = true) ||
                    componentName.contains(ClipboardAccessibilityService::class.java.simpleName, ignoreCase = true)) {
                    return true
                }
            }
        } catch (e: Exception) {
            return false
        }
        return false
    }

    private fun getClipboardText(): String? {
        val clip = clipboardManager?.primaryClip
        if (clip != null && clip.itemCount > 0) {
            val item = clip.getItemAt(0)
            return item.text?.toString()
        }
        return null
    }
    
    private fun setClipboardText(text: String) {
        val clip = ClipData.newPlainText("Global Clipboard", text)
        clipboardManager?.setPrimaryClip(clip)
        lastClipboardContent = text
    }
    
    private fun startClipboardListening() {
        stopClipboardListening()
        clipboardListener = ClipboardManager.OnPrimaryClipChangedListener {
            val currentText = getClipboardText()
            if (currentText != null && currentText != lastClipboardContent) {
                lastClipboardContent = currentText
                clipboardMethodChannel?.invokeMethod("onClipboardChanged", mapOf("text" to currentText))
            }
        }
        clipboardManager?.addPrimaryClipChangedListener(clipboardListener)
    }
    
    private fun stopClipboardListening() {
        clipboardListener?.let {
            clipboardManager?.removePrimaryClipChangedListener(it)
        }
        clipboardListener = null
    }
    
    private fun startClipboardForegroundService() {
        val intent = Intent(this, ClipboardForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
    
    private fun stopClipboardForegroundService() {
        val intent = Intent(this, ClipboardForegroundService::class.java)
        stopService(intent)
    }
    
    override fun onDestroy() {
        stopClipboardListening()
        onGlobalClipboardChanged = null
        super.onDestroy()
    }
}
