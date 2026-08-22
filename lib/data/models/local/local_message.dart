import 'dart:convert';
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
    MessageType type = MessageType.text;
    String? localPath;
    String? fName;
    int? fSize;
    String displayContent = payload;

    if (payload.startsWith('{"__mesh_file__":true')) {
      try {
        final map = jsonDecode(payload) as Map<String, dynamic>;
        type = MessageType.values.firstWhere(
          (e) => e.name == map['type'],
          orElse: () => MessageType.file,
        );
        localPath = map['localPath'] as String?;
        fName = map['fileName'] as String?;
        fSize = (map['fileSize'] as num?)?.toInt();
        displayContent = fName ?? 'File';
      } catch (_) {}
    }

    return ChatMessage(
      id: messageId,
      senderId: senderId,
      receiverId: receiverId,
      content: displayContent,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
      status: deliveryStatus,
      messageType: type,
      localFilePath: localPath,
      fileName: fName,
      fileSize: fSize,
    );
  }

  factory LocalMessage.fromDomain(ChatMessage domain, String conversationId) {
    String storedPayload = domain.content;
    if (domain.messageType != MessageType.text) {
      storedPayload = jsonEncode({
        '__mesh_file__': true,
        'type': domain.messageType.name,
        'localPath': domain.localFilePath,
        'fileName': domain.fileName,
        'fileSize': domain.fileSize,
      });
    }

    return LocalMessage(
      messageId: domain.id,
      conversationId: conversationId,
      senderId: domain.senderId,
      receiverId: domain.receiverId,
      payload: storedPayload,
      timestamp: domain.timestamp.millisecondsSinceEpoch,
      deliveryStatus: domain.status,
      isOutgoing: domain.senderId == 'local',
    );
  }
}
