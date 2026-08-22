import '../../data/models/packet_model.dart';
import '../entities/mesh_event.dart';

abstract class MeshRepository {
  Future<bool> startDiscovery();
  Future<bool> stopDiscovery();
  Future<bool> connectToPeer(String peerId, {String? peerName, String? macAddress});
  Future<bool> disconnectFromPeer(String peerId);
  Future<bool> sendPacket(PacketModel packet);
  Future<bool> updateUserProfile(String displayName, int avatarIndex);
  Future<String?> getLocalNodeId();
  Stream<MeshEvent> get meshEvents;
}
