package com.example.communication_platform

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
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
                    else -> result.notImplemented()
                }
            }
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
}
