package com.agentgrid.mobile.network

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import com.agentgrid.mobile.domain.PairingPayload
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json

internal class PairingStore(context: Context) : PhoneCredentialStore {
    private val preferences =
        context.getSharedPreferences("agentgrid-pairing", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }

    override suspend fun save(pairing: PairingPayload) = withContext(Dispatchers.IO) {
        val plaintext = json.encodeToString(PairingPayload.serializer(), pairing).encodeToByteArray()
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val encrypted = cipher.doFinal(plaintext)
        check(preferences.edit()
            .putString("iv", android.util.Base64.encodeToString(cipher.iv, android.util.Base64.NO_WRAP))
            .putString("payload", android.util.Base64.encodeToString(encrypted, android.util.Base64.NO_WRAP))
            .commit()) { "无法保存配对凭据" }
    }

    override suspend fun load(): PairingPayload? = withContext(Dispatchers.IO) {
        val iv = preferences.getString("iv", null) ?: return@withContext null
        val payload = preferences.getString("payload", null) ?: return@withContext null
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            secretKey(),
            GCMParameterSpec(128, android.util.Base64.decode(iv, android.util.Base64.NO_WRAP)),
        )
        val decrypted = cipher.doFinal(
            android.util.Base64.decode(payload, android.util.Base64.NO_WRAP),
        )
        json.decodeFromString(PairingPayload.serializer(), decrypted.decodeToString())
    }

    override suspend fun clear() = withContext(Dispatchers.IO) {
        // 控制序号绑定设备身份，解除配对后仍需保持单调，避免被 Mac 判为重放。
        check(
            preferences.edit()
                .remove("iv")
                .remove("payload")
                .commit(),
        ) { "无法清除配对凭据" }
    }

    override suspend fun reserveNextSequence(): ULong = withContext(Dispatchers.IO) {
        synchronized(preferences) {
            val previous = preferences.getLong("sequence", 0L)
            check(previous < Long.MAX_VALUE) { "控制序号已耗尽" }
            val value = previous + 1L
            check(preferences.edit().putLong("sequence", value).commit()) {
                "无法保存控制序号"
            }
            value.toULong()
        }
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val KEY_ALIAS = "agentgrid-pairing-key"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
