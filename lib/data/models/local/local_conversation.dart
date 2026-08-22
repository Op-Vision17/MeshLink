import 'package:isar/isar.dart';
import 'fast_hash.dart';

part 'local_conversation.g.dart';

@collection
class LocalConversation {
  Id get isarId => fastHash(conversationId);

  @Index(unique: true, replace: true)
  final String conversationId;
  final String peerId;
  final String lastMessagePreview;
  final int lastMessageTimestamp;

  LocalConversation({
    required this.conversationId,
    required this.peerId,
    required this.lastMessagePreview,
    required this.lastMessageTimestamp,
  });
}
