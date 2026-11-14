package dev.independent.animetka_tv

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.speech.RecognizerIntent
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/** Restored from the retained 1.7.0 classes; see docs/ANDROID-RECOVERY.md. */
class MainActivity : FlutterActivity() {
    private var speechResult: MethodChannel.Result? = null
    private var updateResult: MethodChannel.Result? = null
    private var updateFile: File? = null

    // Deliver exactly one route-pop for the full remote Back key pair.
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val engine = flutterEngine
        if (event.keyCode == KeyEvent.KEYCODE_BACK && engine != null) {
            if (event.action == KeyEvent.ACTION_UP && !event.isCanceled) {
                engine.navigationChannel.popRoute()
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "dev.independent.animetka/native")
            .setMethodCallHandler { call, result ->
                val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                when (call.method) {
                    "videoCheckMode" -> {
                        val requested = intent?.getStringExtra("mode") ?: "off"
                        result.success(if (intent?.action == "$packageName.VIDEO_CHECK" &&
                            requested in listOf("off", "light", "cnn_s", "cnn_m")) requested else null)
                    }
                    "appVersion" -> result.success(packageManager.getPackageInfo(packageName, 0).versionName)
                    "getVolume" -> result.success(audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() /
                        audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC))
                    "setVolume" -> {
                        val level = (call.arguments as? Number)?.toDouble()?.coerceIn(0.0, 1.0)
                        if (level == null) result.error("argument", "Invalid volume", null)
                        else {
                            audio.setStreamVolume(AudioManager.STREAM_MUSIC,
                                (level * audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)).toInt(), 0)
                            result.success(null)
                        }
                    }
                    "setKeepScreenOn" -> {
                        if (call.arguments == true) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        result.success(null)
                    }
                    "speech" -> {
                        if (speechResult != null) {
                            result.error("busy", "Распознавание уже запущено", null)
                            return@setMethodCallHandler
                        }
                        val request = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ru-RU")
                            putExtra(RecognizerIntent.EXTRA_PROMPT, "Название аниме")
                        }
                        try { speechResult = result; startActivityForResult(request, 45) }
                        catch (_: Exception) {
                            speechResult = null
                            result.error("unavailable", "Голосовой поиск недоступен на этом устройстве", null)
                        }
                    }
                    "openUrl" -> {
                        val uri = Uri.parse(call.arguments as? String ?: "")
                        if (uri.scheme !in listOf("https", "tg", "animetka")) result.error("argument", "Invalid URL", null)
                        else try { startActivity(Intent(Intent.ACTION_VIEW, uri)); result.success(null) }
                        catch (_: Exception) { result.error("unavailable", "Нет приложения для открытия ссылки", null) }
                    }
                    "installUpdate" -> {
                        if (updateResult != null) {
                            result.error("busy", "Установка уже запущена", null)
                            return@setMethodCallHandler
                        }
                        updateResult = result
                        try {
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                type = "application/vnd.android.package-archive"
                                addCategory(Intent.CATEGORY_OPENABLE)
                            }, 67)
                        } catch (_: Exception) {
                            updateResult = null
                            result.error("unavailable", "Не удалось открыть выбор APK", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun checkUpdate(file: File) {
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val candidate = packageManager.getPackageArchiveInfo(file.absolutePath, flags)
        check(candidate != null) { "Файл не является APK" }
        val current = packageManager.getPackageInfo(packageName, flags)
        check(candidate.packageName == packageName) { "Этот APK предназначен для другого приложения" }
        val next = if (Build.VERSION.SDK_INT >= 28) candidate.longVersionCode else candidate.versionCode.toLong()
        val installed = if (Build.VERSION.SDK_INT >= 28) current.longVersionCode else current.versionCode.toLong()
        check(next > installed) { "Выберите более новую версию приложения" }
        fun signers(info: PackageInfo): Set<String> {
            val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
            return signatures?.map { signature ->
                MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).joinToString("") { "%02x".format(it) }
            }?.toSet() ?: emptySet()
        }
        val expected = signers(current)
        check(expected.isNotEmpty() && expected == signers(candidate)) { "Подпись обновления не совпадает" }
    }

    private fun finishUpdate(error: String? = null) {
        val result = updateResult
        updateResult = null
        if (error == null) result?.success(null) else result?.error("update", error, null)
    }

    private fun installUpdate(file: File) {
        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
            startActivityForResult(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")), 68)
            return
        }
        Thread {
            var sessionId: Int? = null
            try {
                checkUpdate(file)
                val installer = packageManager.packageInstaller
                val parameters = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
                    setAppPackageName(packageName)
                    setSize(file.length())
                }
                val id = installer.createSession(parameters)
                sessionId = id
                installer.openSession(id).use { session ->
                    file.inputStream().use { input ->
                        session.openWrite("base.apk", 0, file.length()).use { output ->
                            input.copyTo(output)
                            session.fsync(output)
                        }
                    }
                    val callback = Intent(this, InstallResultReceiver::class.java).setAction("$packageName.INSTALL_RESULT")
                    session.commit(PendingIntent.getBroadcast(this, id, callback,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE).intentSender)
                }
                runOnUiThread { finishUpdate() }
            } catch (e: Exception) {
                sessionId?.let { try { packageManager.packageInstaller.abandonSession(it) } catch (_: Exception) {} }
                runOnUiThread { finishUpdate(e.message ?: "Не удалось установить обновление") }
            } finally {
                file.delete()
                updateFile = null
            }
        }.start()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 67) {
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) { finishUpdate(); return }
            Thread {
                val file = File(cacheDir, "client-update.apk")
                try {
                    contentResolver.openInputStream(uri).use { input ->
                        check(input != null) { "Не удалось прочитать APK" }
                        file.outputStream().use { output ->
                            val buffer = ByteArray(65536)
                            var total = 0L
                            while (true) {
                                val count = input.read(buffer)
                                if (count < 0) break
                                total += count
                                check(total <= 128L * 1024 * 1024) { "APK превышает 128 МБ" }
                                output.write(buffer, 0, count)
                            }
                        }
                    }
                    checkUpdate(file)
                    updateFile = file
                    runOnUiThread {
                        try { installUpdate(file) }
                        catch (e: Exception) { file.delete(); finishUpdate(e.message ?: "Не удалось начать установку") }
                    }
                } catch (e: Exception) {
                    file.delete()
                    runOnUiThread { finishUpdate(e.message ?: "Ошибка чтения APK") }
                }
            }.start()
        }
        if (requestCode == 68) {
            val file = updateFile
            if (file == null || (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls())) {
                file?.delete(); updateFile = null; finishUpdate("Установка обновлений не разрешена")
            } else installUpdate(file)
        }
        if (requestCode == 45) {
            val result = speechResult; speechResult = null
            result?.success(if (resultCode == Activity.RESULT_OK)
                data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull() else null)
        }
    }

    override fun onDestroy() {
        speechResult?.success(null); speechResult = null
        updateResult?.success(null); updateResult = null
        super.onDestroy()
    }
}
