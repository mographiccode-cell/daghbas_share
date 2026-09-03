package com.waqt.alarm

import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.Ringtone
import android.media.RingtoneManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.waqt.alarm/audio"
    private var player: MediaPlayer? = null
    private var ringtone: Ringtone? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "previewSound" -> {
                        val key = call.argument<String>("soundKey") ?: "waqt_classic"
                        try {
                            previewSound(key)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("preview_failed", e.message, null)
                        }
                    }
                    "stopSoundPreview" -> {
                        stopPreview()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun previewSound(key: String) {
        stopPreview()
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        if (key == "system") {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ringtone = RingtoneManager.getRingtone(this, uri)?.apply {
                audioAttributes = attributes
                play()
            }
            return
        }

        // Static references keep the alarm sounds in optimized release APKs.
        val resId = when (key) {
            "waqt_soft" -> R.raw.waqt_soft
            "waqt_digital" -> R.raw.waqt_digital
            else -> R.raw.waqt_classic
        }

        val fd = resources.openRawResourceFd(resId)
            ?: throw IllegalStateException("Unable to open alarm sound resource")
        player = MediaPlayer().apply {
            setAudioAttributes(attributes)
            setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
            fd.close()
            setOnCompletionListener {
                it.release()
                if (player === it) player = null
            }
            prepare()
            start()
        }
    }

    private fun stopPreview() {
        try {
            player?.stop()
        } catch (_: Exception) {}
        player?.release()
        player = null

        try {
            ringtone?.stop()
        } catch (_: Exception) {}
        ringtone = null
    }

    override fun onStop() {
        stopPreview()
        super.onStop()
    }

    override fun onDestroy() {
        stopPreview()
        super.onDestroy()
    }
}
