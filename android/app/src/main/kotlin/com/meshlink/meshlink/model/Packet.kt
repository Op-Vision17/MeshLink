package com.meshlink.meshlink.model

import org.json.JSONObject

enum class PacketType {
    TEXT,
    ACK,
    DISCOVERY,
    HEARTBEAT,
    HANDSHAKE;

    companion object {
        fun fromString(value: String): PacketType {
            return try {
                valueOf(value.uppercase())
            } catch (e: Exception) {
                TEXT
            }
        }
    }
}

data class Packet(
    val messageId: String,
    val senderId: String,
    val receiverId: String,
    val previousHop: String? = null,
    val hopCount: Int = 0,
    val ttl: Int = 7,
    val timestamp: Long = System.currentTimeMillis(),
    val packetType: PacketType = PacketType.TEXT,
    val payload: String = "",
    val signature: String? = null
) {
    fun toJson(): String {
        val json = JSONObject()
        json.put("messageId", messageId)
        json.put("senderId", senderId)
        json.put("receiverId", receiverId)
        json.put("previousHop", previousHop ?: JSONObject.NULL)
        json.put("hopCount", hopCount)
        json.put("ttl", ttl)
        json.put("timestamp", timestamp)
        json.put("packetType", packetType.name)
        json.put("payload", payload)
        json.put("signature", signature ?: JSONObject.NULL)
        return json.toString()
    }

    fun toMap(): Map<String, Any?> {
        return mapOf(
            "messageId" to messageId,
            "senderId" to senderId,
            "receiverId" to receiverId,
            "previousHop" to previousHop,
            "hopCount" to hopCount,
            "ttl" to ttl,
            "timestamp" to timestamp,
            "packetType" to packetType.name,
            "payload" to payload,
            "signature" to signature
        )
    }

    companion object {
        fun fromJson(jsonStr: String): Packet {
            val json = JSONObject(jsonStr)
            val prevHopRaw = if (json.isNull("previousHop")) null else json.optString("previousHop", null)
            val sigRaw = if (json.isNull("signature")) null else json.optString("signature", null)
            return Packet(
                messageId = json.optString("messageId", ""),
                senderId = json.optString("senderId", ""),
                receiverId = json.optString("receiverId", ""),
                previousHop = prevHopRaw,
                hopCount = json.optInt("hopCount", 0),
                ttl = json.optInt("ttl", 7),
                timestamp = json.optLong("timestamp", System.currentTimeMillis()),
                packetType = PacketType.fromString(json.optString("packetType", "TEXT")),
                payload = json.optString("payload", ""),
                signature = sigRaw
            )
        }

        fun fromMap(map: Map<String, Any?>): Packet {
            return Packet(
                messageId = map["messageId"] as? String ?: "",
                senderId = map["senderId"] as? String ?: "",
                receiverId = map["receiverId"] as? String ?: "",
                previousHop = map["previousHop"] as? String,
                hopCount = (map["hopCount"] as? Number)?.toInt() ?: 0,
                ttl = (map["ttl"] as? Number)?.toInt() ?: 7,
                timestamp = (map["timestamp"] as? Number)?.toLong() ?: System.currentTimeMillis(),
                packetType = PacketType.fromString(map["packetType"] as? String ?: "TEXT"),
                payload = map["payload"] as? String ?: "",
                signature = map["signature"] as? String
            )
        }
    }
}
