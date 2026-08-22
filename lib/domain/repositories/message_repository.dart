import '../entities/chat_message.dart';

abstract class MessageRepository {
  Future<void> saveMessage(ChatMessage message, {required String conversationId});
  Future<List<ChatMessage>> getMessagesForConversation(String conversationId);
  Stream<List<ChatMessage>> watchMessagesForConversation(String conversationId);
  Future<void> updateMessageStatus(String messageId, MessageStatus status);
}
