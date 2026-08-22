package com.meshlink.meshlink.security

interface SecurityProvider {
    fun encrypt(payload: String, secretKey: String): String
    fun decrypt(ciphertext: String, secretKey: String): String
    fun sign(data: String, secretKey: String): String
    fun verify(data: String, signature: String, publicKey: String): Boolean
}
