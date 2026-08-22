import 'package:isar/isar.dart';
import '../../../domain/entities/peer_node.dart';
import 'fast_hash.dart';

part 'local_peer.g.dart';

@collection
class LocalPeer {
  Id get isarId => fastHash(peerId);

  @Index(unique: true, replace: true)
  final String peerId;
  final String displayName;
  final int lastSeen;
  final bool isFavorite;

  LocalPeer({
    required this.peerId,
    required this.displayName,
    required this.lastSeen,
    this.isFavorite = false,
  });

  PeerNode toDomain() {
    return PeerNode(
      id: peerId,
      name: displayName,
      connectionType: 'BLE',
      rssi: -60,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(lastSeen),
    );
  }

  factory LocalPeer.fromDomain(PeerNode domain, {bool isFavorite = false}) {
    return LocalPeer(
      peerId: domain.id,
      displayName: domain.name,
      lastSeen: domain.lastSeen.millisecondsSinceEpoch,
      isFavorite: isFavorite,
    );
  }
}
