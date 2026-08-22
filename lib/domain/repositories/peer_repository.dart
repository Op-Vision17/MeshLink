import '../entities/peer_node.dart';

abstract class PeerRepository {
  Future<void> savePeer(PeerNode peer);
  Future<void> deletePeer(String peerId);
  Future<List<PeerNode>> getPeers();
  Stream<List<PeerNode>> watchPeers();
}
