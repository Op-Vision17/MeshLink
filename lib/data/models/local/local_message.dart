import 'package:isar/isar.dart';
import '../../../domain/entities/chat_message.dart';
import 'fast_hash.dart';

part 'local_message.g.dart';

@collection
class LocalMessage {
  Id get isarId => fastHash(messageId);

  @Index(unique: true, replace: true)
  final String messageId;
  final String conversationId;
  final String senderId;
  final String receiverId;
  final String payload;
  final int timestamp;

  @enumerated
  final MessageStatus deliveryStatus;
  final bool isOutgoing;

  LocalMessage({
    required this.messageId,
    required this.conversationId,
    required this.senderId,
    required this.receiverId,
    required this.payload,
    required this.timestamp,
    required this.deliveryStatus,
    required this.isOutgoing,
  });

  ChatMessage toDomain() {
    return ChatMessage(
      id: messageId,
      senderId: senderId,
      receiverId: receiverId,
      content: payload,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
      status: deliveryStatus,
    );
  }

  factory LocalMessage.fromDomain(ChatMessage domain, String conversationId) {
    return LocalMessage(
      messageId: domain.id,
      conversationId: conversationId,
      senderId: domain.senderId,
      receiverId: domain.receiverId,
      payload: domain.content,
      timestamp: domain.timestamp.millisecondsSinceEpoch,
      deliveryStatus: domain.status,
      isOutgoing: domain.senderId == 'local',
    );
  }
}
