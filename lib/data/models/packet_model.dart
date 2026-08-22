import 'dart:convert';

enum PacketType {
  text,
  ack,
  discovery,
  heartbeat;

  String toRawString() {
    switch (this) {
      case PacketType.text:
        return 'TEXT';
      case PacketType.ack:
        return 'ACK';
      case PacketType.discovery:
        return 'DISCOVERY';
      case PacketType.heartbeat:
        return 'HEARTBEAT';
    }
  }

  static PacketType fromRawString(String value) {
    switch (value.toUpperCase()) {
      case 'ACK':
        return PacketType.ack;
      case 'DISCOVERY':
        return PacketType.discovery;
      case 'HEARTBEAT':
        return PacketType.heartbeat;
      case 'TEXT':
      default:
        return PacketType.text;
    }
  }
}

class PacketModel {
  final String messageId;
  final String senderId;
  final String receiverId;
  final String? previousHop;
  final int hopCount;
  final int ttl;
  final int timestamp;
  final PacketType packetType;
  final String payload;

  const PacketModel({
    required this.messageId,
    required this.senderId,
    required this.receiverId,
    this.previousHop,
    this.hopCount = 0,
    this.ttl = 7,
    required this.timestamp,
    this.packetType = PacketType.text,
    required this.payload,
  });

  Map<String, dynamic> toMap() {
    return {
      'messageId': messageId,
      'senderId': senderId,
      'receiverId': receiverId,
      'previousHop': previousHop,
      'hopCount': hopCount,
      'ttl': ttl,
      'timestamp': timestamp,
      'packetType': packetType.toRawString(),
      'payload': payload,
    };
  }

  factory PacketModel.fromMap(Map<String, dynamic> map) {
    return PacketModel(
      messageId: map['messageId'] as String? ?? '',
      senderId: map['senderId'] as String? ?? '',
      receiverId: map['receiverId'] as String? ?? '',
      previousHop: map['previousHop'] as String?,
      hopCount: (map['hopCount'] as num?)?.toInt() ?? 0,
      ttl: (map['ttl'] as num?)?.toInt() ?? 7,
      timestamp: (map['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      packetType: PacketType.fromRawString(map['packetType'] as String? ?? 'TEXT'),
      payload: map['payload'] as String? ?? '',
    );
  }

  String toJson() => json.encode(toMap());

  factory PacketModel.fromJson(String source) =>
      PacketModel.fromMap(json.decode(source) as Map<String, dynamic>);
}
