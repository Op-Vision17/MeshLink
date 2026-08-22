import '../../domain/entities/peer_node.dart';
import '../../domain/repositories/peer_repository.dart';
import '../datasources/isar_datasource.dart';
import '../models/local/local_peer.dart';

class PeerRepositoryImpl implements PeerRepository {
  final IsarDataSource _localDataSource;

  PeerRepositoryImpl(this._localDataSource);

  @override
  Future<void> savePeer(PeerNode peer) async {
    final localPeer = LocalPeer.fromDomain(peer);
    await _localDataSource.savePeer(localPeer);
  }

  @override
  Future<void> deletePeer(String peerId) async {
    await _localDataSource.deletePeer(peerId);
  }

  @override
  Future<List<PeerNode>> getPeers() async {
    final list = await _localDataSource.getPeers();
    return list.map((p) => p.toDomain()).toList();
  }

  @override
  Stream<List<PeerNode>> watchPeers() {
    return _localDataSource.watchPeers().map((list) => list.map((p) => p.toDomain()).toList());
  }
}
