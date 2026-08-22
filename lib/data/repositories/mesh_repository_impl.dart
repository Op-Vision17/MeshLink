import '../../domain/entities/mesh_event.dart';
import '../../domain/repositories/mesh_repository.dart';
import '../datasources/platform_channel_datasource.dart';
import '../models/packet_model.dart';

class MeshRepositoryImpl implements MeshRepository {
  final PlatformChannelDataSource _dataSource;

  MeshRepositoryImpl(this._dataSource);

  @override
  Future<bool> startDiscovery() async {
    return await _dataSource.startDiscovery();
  }

  @override
  Future<bool> stopDiscovery() async {
    return await _dataSource.stopDiscovery();
  }

  @override
  Future<bool> connectToPeer(String peerId, {String? peerName, String? macAddress}) async {
    return await _dataSource.connectToPeer(peerId, peerName: peerName, macAddress: macAddress);
  }

  @override
  Future<bool> disconnectFromPeer(String peerId) async {
    return await _dataSource.disconnectFromPeer(peerId);
  }

  @override
  Future<bool> sendPacket(PacketModel packet) async {
    return await _dataSource.sendPacket(packet);
  }

  @override
  Future<bool> updateUserProfile(String displayName, int avatarIndex) async {
    return await _dataSource.updateUserProfile(displayName, avatarIndex);
  }

  @override
  Future<String?> getLocalNodeId() async {
    return await _dataSource.getLocalNodeId();
  }

  @override
  Stream<MeshEvent> get meshEvents => _dataSource.meshEvents;
}
