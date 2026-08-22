package com.meshlink.meshlink.security

import android.util.Base64
import android.util.Log
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class AesGcmSecurityProvider : SecurityProvider {
    private val TAG = "AesGcmSecurityProvider"
    private val IV_LENGTH_BYTES = 12
    private val TAG_LENGTH_BITS = 128
    private val secureRandom = SecureRandom()

    private fun deriveKey(secretKeyStr: String): SecretKey {
        val digest = MessageDigest.getInstance("SHA-256")
        val keyBytes = digest.digest(secretKeyStr.toByteArray(Charsets.UTF_8))
        return SecretKeySpec(keyBytes, "AES")
    }

    private fun deriveHmacKey(secretKeyStr: String): SecretKey {
        val digest = MessageDigest.getInstance("SHA-256")
        val keyBytes = digest.digest(("HMAC_" + secretKeyStr).toByteArray(Charsets.UTF_8))
        return SecretKeySpec(keyBytes, "HmacSHA256")
    }

    override fun encrypt(payload: String, secretKey: String): String {
        return try {
            val key = deriveKey(secretKey)
            val iv = ByteArray(IV_LENGTH_BYTES)
            secureRandom.nextBytes(iv)

            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val spec = GCMParameterSpec(TAG_LENGTH_BITS, iv)
            cipher.init(Cipher.ENCRYPT_MODE, key, spec)

            val ciphertext = cipher.doFinal(payload.toByteArray(Charsets.UTF_8))
            val combined = ByteArray(iv.size + ciphertext.size)
            System.arraycopy(iv, 0, combined, 0, iv.size)
            System.arraycopy(ciphertext, 0, combined, iv.size, ciphertext.size)

            Base64.encodeToString(combined, Base64.NO_WRAP)
        } catch (e: Exception) {
            Log.e(TAG, "Encryption error: ${e.message}", e)
            payload
        }
    }

    override fun decrypt(ciphertext: String, secretKey: String): String {
        return try {
            val combined = Base64.decode(ciphertext, Base64.NO_WRAP)
            if (combined.size < IV_LENGTH_BYTES) {
                Log.e(TAG, "Decryption error: Invalid payload length")
                return ciphertext
            }

            val iv = ByteArray(IV_LENGTH_BYTES)
            val encryptedBytes = ByteArray(combined.size - IV_LENGTH_BYTES)
            System.arraycopy(combined, 0, iv, 0, IV_LENGTH_BYTES)
            System.arraycopy(combined, IV_LENGTH_BYTES, encryptedBytes, 0, encryptedBytes.size)

            val key = deriveKey(secretKey)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val spec = GCMParameterSpec(TAG_LENGTH_BITS, iv)
            cipher.init(Cipher.DECRYPT_MODE, key, spec)

            val decryptedBytes = cipher.doFinal(encryptedBytes)
            String(decryptedBytes, Charsets.UTF_8)
        } catch (e: Exception) {
            Log.e(TAG, "Decryption error: ${e.message}")
            ciphertext
        }
    }

    override fun sign(data: String, secretKey: String): String {
        return try {
            val key = deriveHmacKey(secretKey)
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(key)
            val hash = mac.doFinal(data.toByteArray(Charsets.UTF_8))
            Base64.encodeToString(hash, Base64.NO_WRAP)
        } catch (e: Exception) {
            Log.e(TAG, "Signature error: ${e.message}", e)
            ""
        }
    }

    override fun verify(data: String, signature: String, publicKey: String): Boolean {
        if (signature.isBlank()) return false
        val expectedSig = sign(data, publicKey)
        return signature == expectedSig
    }
}
