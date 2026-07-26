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
import kotlinx.serialization.json.Json

class PairingStore(context: Context) {
    private val preferences =
        context.getSharedPreferences("agentgrid-pairing", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }

    fun save(pairing: PairingPayload) {
        val plaintext = json.encodeToString(PairingPayload.serializer(), pairing).encodeToByteArray()
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val encrypted = cipher.doFinal(plaintext)
        preferences.edit()
            .putString("iv", android.util.Base64.encodeToString(cipher.iv, android.util.Base64.NO_WRAP))
            .putString("payload", android.util.Base64.encodeToString(encrypted, android.util.Base64.NO_WRAP))
            .apply()
    }

    fun load(): PairingPayload? {
        val iv = preferences.getString("iv", null) ?: return null
        val payload = preferences.getString("payload", null) ?: return null
        return runCatching {
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
        }.getOrNull()
    }

    fun clear() {
        preferences.edit().clear().apply()
    }

    fun nextSequence(): ULong {
        val value = preferences.getLong("sequence", 0L) + 1L
        preferences.edit().putLong("sequence", value).apply()
        return value.toULong()
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

