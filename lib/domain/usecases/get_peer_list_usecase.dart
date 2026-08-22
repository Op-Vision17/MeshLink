import '../entities/peer_node.dart';
import '../repositories/peer_repository.dart';

class GetPeerListUseCase {
  final PeerRepository repository;

  GetPeerListUseCase(this.repository);

  Future<List<PeerNode>> getPeers() async {
    return await repository.getPeers();
  }

  Stream<List<PeerNode>> watchPeers() {
    return repository.watchPeers();
  }
}
