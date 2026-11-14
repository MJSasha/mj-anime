package dev.independent.animetka_tv

import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.security.MessageDigest
import java.util.concurrent.CancellationException

/** HTTPS GitHub release assets only; never uses the account/API client. */
internal object ReleaseDownload {
    const val MAX_SIZE = 128L * 1024 * 1024

    fun validateUrl(value: String, initial: Boolean) {
        val uri = URI(value)
        require(uri.scheme == "https" && uri.port == -1 && uri.rawUserInfo == null && uri.fragment == null) { "Invalid update URL" }
        if (initial) {
            require(uri.host == "github.com" && uri.query == null &&
                Regex("/MJSasha/mj-anime/releases/download/v[0-9]+\\.[0-9]+\\.[0-9]+/MJAnime-[0-9]+\\.[0-9]+\\.[0-9]+\\.apk").matches(uri.path)) { "Invalid release asset" }
        } else {
            require(uri.host in setOf("github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com")) { "Invalid update redirect" }
        }
    }

    fun validateMetadata(size: Long, hash: String) {
        require(size in 1..MAX_SIZE && Regex("[a-f0-9]{64}").matches(hash)) { "Invalid update metadata" }
    }

    fun copyVerified(input: InputStream, output: OutputStream, size: Long, hash: String, cancelled: () -> Boolean) {
        validateMetadata(size, hash)
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(65536)
        var total = 0L
        while (true) {
            if (cancelled()) throw CancellationException()
            val count = input.read(buffer)
            if (count < 0) break
            total += count
            check(total <= size) { "APK больше ожидаемого" }
            digest.update(buffer, 0, count)
            output.write(buffer, 0, count)
        }
        check(total == size && digest.digest().joinToString("") { "%02x".format(it) } == hash) { "Контрольная сумма APK не совпадает" }
    }

    fun download(url: String, size: Long, hash: String, file: File, cancelled: () -> Boolean) {
        validateUrl(url, true)
        validateMetadata(size, hash)
        var target = url
        try {
            for (redirect in 0..5) {
                if (cancelled()) throw CancellationException()
                val connection = URI(target).toURL().openConnection() as HttpURLConnection
                try {
                    connection.instanceFollowRedirects = false
                    connection.connectTimeout = 15000
                    connection.readTimeout = 20000
                    connection.setRequestProperty("User-Agent", "MJAnime-Updater")
                    connection.setRequestProperty("Accept-Encoding", "identity")
                    val status = connection.responseCode
                    if (status in listOf(301, 302, 303, 307, 308)) {
                        check(redirect < 5) { "Слишком много перенаправлений" }
                        target = URI(target).resolve(connection.getHeaderField("Location") ?: error("Missing redirect")).toString()
                        validateUrl(target, false)
                        continue
                    }
                    check(status == 200) { "GitHub: HTTP $status" }
                    val length = connection.contentLengthLong
                    check(length < 0 || length == size) { "Размер APK не совпадает" }
                    connection.inputStream.use { input ->
                        file.outputStream().use { output ->
                            copyVerified(input, output, size, hash, cancelled)
                        }
                    }
                    if (cancelled()) throw CancellationException()
                    return
                } finally { connection.disconnect() }
            }
            error("Не удалось загрузить APK")
        } catch (e: Exception) { file.delete(); throw e }
    }
}
