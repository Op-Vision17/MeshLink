class MeshPacket {
  final String messageId;
  final String senderId;
  final String receiverId;
  final String previousHop;
  final int hopCount;
  final int ttl;
  final int timestamp;
  final String packetType;
  final String payload;

  const MeshPacket({
    required this.messageId,
    required this.senderId,
    required this.receiverId,
    required this.previousHop,
    required this.hopCount,
    required this.ttl,
    required this.timestamp,
    required this.packetType,
    required this.payload,
  });
}
