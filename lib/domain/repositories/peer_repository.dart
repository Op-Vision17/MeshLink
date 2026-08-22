import '../entities/peer_node.dart';

abstract class PeerRepository {
  Future<void> savePeer(PeerNode peer);
  Future<List<PeerNode>> getPeers();
  Stream<List<PeerNode>> watchPeers();
}
