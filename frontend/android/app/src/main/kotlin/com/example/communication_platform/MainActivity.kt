package com.example.communication_platform

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import androidx.core.content.FileProvider
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private val channelName = "communication_platform/protected_storage"
    private val keyAlias = "communication_platform_storage_wrap_v1"
    private val aad = "communication-platform:android-storage-key:v1".toByteArray(Charsets.UTF_8)
    private val wrappedKeyFile: File
        get() = File(noBackupFilesDir, "storage_key_v1.bin")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                    "loadOrCreateStorageKey" -> result.success(loadOrCreateStorageKey())
                    "destroyWrappingKey" -> {
                        destroyWrappingKey()
                        result.success(null)
                    }
                    "cleanupBounded" -> {
                        val maximumEntries = call.argument<Int>("maximumEntries") ?: 0
                        result.success(cleanupBounded(maximumEntries.coerceAtLeast(0)))
                    }
                    "erasePersistentArtifacts" -> {
                        erasePersistentArtifacts()
                        result.success(null)
                    }
                    "setSensitiveScreen" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        if (enabled) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    "copySensitiveText" -> {
                        val text = call.argument<String>("text")
                        if (text == null) {
                            result.error("invalid_argument", null, null)
                        } else {
                            copySensitiveText(
                                text,
                                call.argument<Int>("clearAfterSeconds") ?: 60,
                            )
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "communication_platform/attachments",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "privateCacheDirectory" -> result.success(
                    cacheDir.resolve("secure_attachment_cache").absolutePath,
                )
                "shareVerifiedFile" -> {
                    val path = call.argument<String>("path")
                    val mime = safeShareMime(call.argument<String>("mime"))
                    if (path == null) {
                        result.error("invalid_argument", null, null)
                    } else {
                        try {
                            val file = File(path).canonicalFile
                            val cache = cacheDir.resolve("secure_attachment_cache").canonicalFile
                            if (!file.path.startsWith(cache.path + File.separator) || !file.isFile) {
                                result.error("invalid_argument", null, null)
                            } else {
                                val uri = FileProvider.getUriForFile(
                                    this,
                                    "${applicationContext.packageName}.attachments",
                                    file,
                                )
                                val intent = Intent(Intent.ACTION_SEND).apply {
                                    type = mime
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                startActivity(Intent.createChooser(intent, null))
                                result.success(null)
                            }
                        } catch (_: Exception) {
                            result.error("share_failed", null, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun copySensitiveText(text: String, clearAfterSeconds: Int) {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val label = "communication-platform-recovery"
        clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
        Handler(Looper.getMainLooper()).postDelayed({
            if (clipboard.primaryClipDescription?.label?.toString() == label) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    clipboard.clearPrimaryClip()
                } else {
                    clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
                }
            }
        }, clearAfterSeconds.coerceIn(1, 300) * 1000L)
    }

    private fun loadOrCreateStorageKey(): Map<String, Any> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return mapOf("status" to "unavailable", "protection" to "unknown")
        }
        return try {
            val keyStore = openKeyStore()
            val hasKey = keyStore.containsAlias(keyAlias)
            val hasWrappedMaterial = wrappedKeyFile.exists()
            if (hasKey != hasWrappedMaterial) {
                return mapOf("status" to "key_lost", "protection" to "unknown")
            }

            val wrappingKey = if (hasKey) {
                keyStore.getKey(keyAlias, null) as SecretKey
            } else {
                generateWrappingKey(preferStrongBox = true)
            }
            val databaseKey = if (hasWrappedMaterial) {
                unwrapDatabaseKey(wrappingKey)
            } else {
                val fresh = ByteArray(32).also(SecureRandom()::nextBytes)
                persistWrappedDatabaseKey(wrappingKey, fresh)
                fresh
            }
            mapOf(
                "status" to "ready",
                "protection" to protectionFor(wrappingKey),
                "databaseKey" to databaseKey,
            )
        } catch (_: AEADBadTagException) {
            mapOf("status" to "integrity_failure", "protection" to "unknown")
        } catch (_: Exception) {
            mapOf("status" to "unavailable", "protection" to "unknown")
        }
    }

    private fun openKeyStore(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply {
        load(null)
    }

    private fun generateWrappingKey(preferStrongBox: Boolean): SecretKey {
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        val builder = KeyGenParameterSpec.Builder(
            keyAlias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setKeySize(256)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
        if (preferStrongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            builder.setIsStrongBoxBacked(true)
        }
        return try {
            generator.init(builder.build())
            generator.generateKey()
        } catch (exception: Exception) {
            if (preferStrongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                generateWrappingKey(preferStrongBox = false)
            } else {
                throw exception
            }
        }
    }

    private fun persistWrappedDatabaseKey(wrappingKey: SecretKey, databaseKey: ByteArray) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, wrappingKey)
        cipher.updateAAD(aad)
        val ciphertext = cipher.doFinal(databaseKey)
        val payload = byteArrayOf(1) + cipher.iv + ciphertext
        val temporary = File(noBackupFilesDir, "storage_key_v1.tmp")
        FileOutputStream(temporary).use { output ->
            output.write(payload)
            output.fd.sync()
        }
        if (!temporary.renameTo(wrappedKeyFile)) {
            temporary.delete()
            throw IllegalStateException("Unable to atomically store wrapped key material")
        }
    }

    private fun unwrapDatabaseKey(wrappingKey: SecretKey): ByteArray {
        val payload = wrappedKeyFile.readBytes()
        if (payload.size != 1 + 12 + 32 + 16 || payload[0].toInt() != 1) {
            throw AEADBadTagException("Invalid wrapped key envelope")
        }
        val iv = payload.copyOfRange(1, 13)
        val ciphertext = payload.copyOfRange(13, payload.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, wrappingKey, GCMParameterSpec(128, iv))
        cipher.updateAAD(aad)
        return cipher.doFinal(ciphertext).also {
            if (it.size != 32) throw AEADBadTagException("Invalid database key length")
        }
    }

    private fun protectionFor(key: SecretKey): String {
        return try {
            val factory = SecretKeyFactory.getInstance(key.algorithm, "AndroidKeyStore")
            val info = factory.getKeySpec(key, KeyInfo::class.java) as KeyInfo
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                when (info.securityLevel) {
                    KeyProperties.SECURITY_LEVEL_STRONGBOX -> "strongbox"
                    KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> "tee"
                    else -> "software"
                }
            } else if (info.isInsideSecureHardware) {
                "tee"
            } else {
                "software"
            }
        } catch (_: Exception) {
            "unknown"
        }
    }

    private fun destroyWrappingKey() {
        try {
            openKeyStore().deleteEntry(keyAlias)
        } finally {
            wrappedKeyFile.delete()
            File(noBackupFilesDir, "storage_key_v1.tmp").delete()
        }
    }

    private fun cleanupBounded(maximumEntries: Int): Map<String, Any> {
        if (maximumEntries == 0) {
            return mapOf("removedEntries" to 0, "hasMore" to false)
        }
        val cache = File(cacheDir, "secure_attachment_cache")
        val expiredBefore = System.currentTimeMillis() - 7L * 24L * 60L * 60L * 1000L
        val candidates = cache.listFiles()
            ?.filter { it.isFile && it.lastModified() <= expiredBefore }
            ?.sortedBy { it.lastModified() }
            .orEmpty()
        var removed = 0
        for (file in candidates.take(maximumEntries)) {
            if (file.delete()) removed += 1
        }
        return mapOf(
            "removedEntries" to removed,
            "hasMore" to (candidates.size > maximumEntries),
        )
    }

    private fun erasePersistentArtifacts() {
        val appFlutter = File(filesDir.parentFile, "app_flutter")
        val database = File(appFlutter, "communication_platform_secure_local.sqlite")
        listOf(database, File("${database.path}-wal"), File("${database.path}-shm"))
            .forEach(File::delete)
        File(cacheDir, "secure_attachment_cache").deleteRecursively()
    }

    private fun safeShareMime(value: String?): String {
        val normalized = value?.trim()?.lowercase() ?: return "application/octet-stream"
        val safe = setOf(
            "image/jpeg", "image/png", "image/webp", "image/gif",
            "audio/mpeg", "audio/ogg", "audio/wav", "text/plain", "application/pdf",
        )
        return if (normalized in safe) normalized else "application/octet-stream"
    }
}
