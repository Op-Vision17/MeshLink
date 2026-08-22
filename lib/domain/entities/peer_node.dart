class PeerNode {
  final String id;
  final String name;
  final String connectionType;
  final int rssi;
  final DateTime lastSeen;

  const PeerNode({
    required this.id,
    required this.name,
    required this.connectionType,
    required this.rssi,
    required this.lastSeen,
  });
}
