import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/local/local_conversation.dart';
import '../models/local/local_message.dart';
import '../models/local/local_peer.dart';

class IsarDataSource {
  static Future<Isar>? _isarFuture;
  late Future<Isar> db;

  IsarDataSource() {
    db = _getDb();
  }

  Future<Isar> _getDb() {
    _isarFuture ??= _initDb();
    return _isarFuture!;
  }

  Future<Isar> _initDb() async {
    final instance = Isar.getInstance();
    if (instance != null) {
      return instance;
    }
    final dir = await getApplicationDocumentsDirectory();
    return await Isar.open(
      [LocalMessageSchema, LocalPeerSchema, LocalConversationSchema],
      directory: dir.path,
      inspector: false,
    );
  }

  Future<void> saveMessage(LocalMessage msg) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.localMessages.put(msg);

      final conv = LocalConversation(
        conversationId: msg.conversationId,
        peerId: msg.isOutgoing ? msg.receiverId : msg.senderId,
        lastMessagePreview: msg.payload,
        lastMessageTimestamp: msg.timestamp,
      );
      await isar.localConversations.put(conv);
    });
  }

  Future<List<LocalMessage>> getMessagesForConversation(String conversationId) async {
    final isar = await db;
    return await isar.localMessages
        .filter()
        .conversationIdEqualTo(conversationId)
        .sortByTimestamp()
        .findAll();
  }

  Stream<List<LocalMessage>> watchMessagesForConversation(String conversationId) async* {
    final isar = await db;
    yield* isar.localMessages
        .filter()
        .conversationIdEqualTo(conversationId)
        .sortByTimestamp()
        .watch(fireImmediately: true);
  }

  Future<void> deleteConversation(String conversationId) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.localMessages.filter().conversationIdEqualTo(conversationId).deleteAll();
      await isar.localConversations.filter().conversationIdEqualTo(conversationId).deleteAll();
    });
  }

  Future<void> deleteMessage(String messageId) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.localMessages.filter().messageIdEqualTo(messageId).deleteAll();
    });
  }

  Future<void> savePeer(LocalPeer peer) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.localPeers.put(peer);
    });
  }

  Future<void> deletePeer(String peerId) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.localPeers.filter().peerIdEqualTo(peerId).deleteAll();
    });
  }

  Future<List<LocalPeer>> getPeers() async {
    final isar = await db;
    return await isar.localPeers.where().findAll();
  }

  Stream<List<LocalPeer>> watchPeers() async* {
    final isar = await db;
    yield* isar.localPeers.where().watch(fireImmediately: true);
  }
}
