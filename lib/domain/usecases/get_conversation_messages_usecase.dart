import '../entities/chat_message.dart';
import '../repositories/message_repository.dart';

class GetConversationMessagesUseCase {
  final MessageRepository repository;

  GetConversationMessagesUseCase(this.repository);

  Future<List<ChatMessage>> getMessages(String conversationId) async {
    return await repository.getMessagesForConversation(conversationId);
  }

  Stream<List<ChatMessage>> watchMessages(String conversationId) {
    return repository.watchMessagesForConversation(conversationId);
  }
}
