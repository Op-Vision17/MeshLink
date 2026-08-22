import 'package:isar/isar.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/message_repository.dart';
import '../datasources/isar_datasource.dart';
import '../models/local/local_message.dart';

class MessageRepositoryImpl implements MessageRepository {
  final IsarDataSource _localDataSource;

  MessageRepositoryImpl(this._localDataSource);

  @override
  Future<void> saveMessage(ChatMessage message, {required String conversationId}) async {
    final localMsg = LocalMessage.fromDomain(message, conversationId);
    await _localDataSource.saveMessage(localMsg);
  }

  @override
  Future<List<ChatMessage>> getMessagesForConversation(String conversationId) async {
    final list = await _localDataSource.getMessagesForConversation(conversationId);
    return list.map((m) => m.toDomain()).toList();
  }

  @override
  Stream<List<ChatMessage>> watchMessagesForConversation(String conversationId) {
    return _localDataSource
        .watchMessagesForConversation(conversationId)
        .map((list) => list.map((m) => m.toDomain()).toList());
  }

  @override
  Future<void> updateMessageStatus(String messageId, MessageStatus status) async {
    final isar = await _localDataSource.db;
    final msg = await isar.localMessages.filter().messageIdEqualTo(messageId).findFirst();
    if (msg != null) {
      final updated = LocalMessage(
        messageId: msg.messageId,
        conversationId: msg.conversationId,
        senderId: msg.senderId,
        receiverId: msg.receiverId,
        payload: msg.payload,
        timestamp: msg.timestamp,
        deliveryStatus: status,
        isOutgoing: msg.isOutgoing,
      );
      await _localDataSource.saveMessage(updated);
    }
  }
}
