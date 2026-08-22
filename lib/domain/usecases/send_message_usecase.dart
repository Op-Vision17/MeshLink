import '../../data/models/packet_model.dart';
import '../entities/chat_message.dart';
import '../repositories/mesh_repository.dart';
import '../repositories/message_repository.dart';

class SendMessageUseCase {
  final MeshRepository meshRepository;
  final MessageRepository messageRepository;

  SendMessageUseCase(this.meshRepository, this.messageRepository);

  Future<bool> execute(PacketModel packet) async {
    final chatMsg = ChatMessage(
      id: packet.messageId,
      senderId: packet.senderId,
      receiverId: packet.receiverId,
      content: packet.payload,
      timestamp: DateTime.fromMillisecondsSinceEpoch(packet.timestamp),
      status: MessageStatus.sending,
    );

    final cleanReceiver = packet.receiverId.length > 8 ? packet.receiverId.substring(0, 8).toLowerCase() : packet.receiverId.toLowerCase();
    await messageRepository.saveMessage(chatMsg, conversationId: cleanReceiver);

    final success = await meshRepository.sendPacket(packet);

    final finalStatus = success ? MessageStatus.sent : MessageStatus.failed;
    await messageRepository.updateMessageStatus(packet.messageId, finalStatus);

    return success;
  }
}
