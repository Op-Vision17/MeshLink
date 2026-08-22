import '../../domain/entities/mesh_packet.dart';

class MeshPacketModel extends MeshPacket {
  const MeshPacketModel({
    required super.messageId,
    required super.senderId,
    required super.receiverId,
    required super.previousHop,
    required super.hopCount,
    required super.ttl,
    required super.timestamp,
    required super.packetType,
    required super.payload,
  });

  factory MeshPacketModel.fromMap(Map<String, dynamic> map) {
    return MeshPacketModel(
      messageId: map['messageId'] as String? ?? '',
      senderId: map['senderId'] as String? ?? '',
      receiverId: map['receiverId'] as String? ?? '',
      previousHop: map['previousHop'] as String? ?? '',
      hopCount: (map['hopCount'] as num?)?.toInt() ?? 0,
      ttl: (map['ttl'] as num?)?.toInt() ?? 7,
      timestamp: (map['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      packetType: map['packetType'] as String? ?? 'DATA',
      payload: map['payload'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'messageId': messageId,
      'senderId': senderId,
      'receiverId': receiverId,
      'previousHop': previousHop,
      'hopCount': hopCount,
      'ttl': ttl,
      'timestamp': timestamp,
      'packetType': packetType,
      'payload': payload,
    };
  }

  factory MeshPacketModel.fromEntity(MeshPacket entity) {
    return MeshPacketModel(
      messageId: entity.messageId,
      senderId: entity.senderId,
      receiverId: entity.receiverId,
      previousHop: entity.previousHop,
      hopCount: entity.hopCount,
      ttl: entity.ttl,
      timestamp: entity.timestamp,
      packetType: entity.packetType,
      payload: entity.payload,
    );
  }
}
