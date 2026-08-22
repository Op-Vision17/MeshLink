import '../entities/peer_node.dart';
import '../repositories/peer_repository.dart';

class SyncPeerListUseCase {
  final PeerRepository repository;

  SyncPeerListUseCase(this.repository);

  Future<void> execute(PeerNode peer) async {
    await repository.savePeer(peer);
  }
}
