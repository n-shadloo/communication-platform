package com.example.communication_platform

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
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

/**
 * The protected-storage boundary, bound to a Context rather than to an Activity.
 *
 * It was originally written inside `MainActivity`, which was correct while the
 * application had one entry point. It has two now: the activity the user opens,
 * and the headless catch-up the platform starts when nobody is looking. Channel
 * handlers registered in `configureFlutterEngine` exist only on the engine that
 * registered them, so a headless engine calling this channel would have found
 * nothing behind it and failed to open its own database.
 *
 * Everything here needs a Context and nothing here needs a window, a user or an
 * activity: the wrapping key lives in the AndroidKeyStore, and the wrapped
 * material and the artifacts live in this application's own directories. The
 * two operations that genuinely need a window - marking a screen sensitive and
 * copying recovery text - deliberately stay in `MainActivity`, so a background
 * engine cannot reach them at all.
 */
internal class ProtectedStorageChannel(private val context: Context) {
    companion object {
        const val NAME = "communication_platform/protected_storage"
        private const val KEY_ALIAS = "communication_platform_storage_wrap_v1"
        private const val WRAPPED_KEY_FILE = "storage_key_v1.bin"
        private const val WRAPPED_KEY_TEMPORARY = "storage_key_v1.tmp"
    }

    private val aad = "communication-platform:android-storage-key:v1".toByteArray(Charsets.UTF_8)
    private val wrappedKeyFile: File
        get() = File(context.noBackupFilesDir, WRAPPED_KEY_FILE)

    fun attach(messenger: BinaryMessenger): MethodChannel =
        MethodChannel(messenger, NAME).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (!handle(call, result)) {
                    result.notImplemented()
                }
            }
        }

    /**
     * Returns true when the call was one this boundary owns.
     *
     * `MainActivity` delegates to this first and answers the window-bound
     * methods itself, so there is exactly one implementation of the storage key
     * and one of the artifact cleanup in the artifact.
     */
    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
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
            else -> return false
        }
        return true
    }

    private fun loadOrCreateStorageKey(): Map<String, Any> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return mapOf("status" to "unavailable", "protection" to "unknown")
        }
        return try {
            val keyStore = openKeyStore()
            val hasKey = keyStore.containsAlias(KEY_ALIAS)
            val hasWrappedMaterial = wrappedKeyFile.exists()
            if (hasKey != hasWrappedMaterial) {
                return mapOf("status" to "key_lost", "protection" to "unknown")
            }

            val wrappingKey = if (hasKey) {
                keyStore.getKey(KEY_ALIAS, null) as SecretKey
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
            // A locked device after a restart reaches here: the key is bound to
            // credential-encrypted state that does not exist before the first
            // unlock. "unavailable" is the whole of the answer, and the caller
            // concludes nothing rather than degrading to something weaker.
            mapOf("status" to "unavailable", "protection" to "unknown")
        }
    }

    private fun openKeyStore(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply {
        load(null)
    }

    private fun generateWrappingKey(preferStrongBox: Boolean): SecretKey {
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        val builder = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
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
        val temporary = File(context.noBackupFilesDir, WRAPPED_KEY_TEMPORARY)
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
            openKeyStore().deleteEntry(KEY_ALIAS)
        } finally {
            wrappedKeyFile.delete()
            File(context.noBackupFilesDir, WRAPPED_KEY_TEMPORARY).delete()
        }
    }

    private fun cleanupBounded(maximumEntries: Int): Map<String, Any> {
        if (maximumEntries == 0) {
            return mapOf("removedEntries" to 0, "hasMore" to false)
        }
        val cache = File(context.cacheDir, "secure_attachment_cache")
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
        val appFlutter = File(context.filesDir.parentFile, "app_flutter")
        val database = File(appFlutter, "communication_platform_secure_local.sqlite")
        listOf(database, File("${database.path}-wal"), File("${database.path}-shm"))
            .forEach(File::delete)
        File(context.cacheDir, "secure_attachment_cache").deleteRecursively()
    }
}
