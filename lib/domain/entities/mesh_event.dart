import '../../data/models/packet_model.dart';

sealed class MeshEvent {
  const MeshEvent();

  factory MeshEvent.fromMap(Map<String, dynamic> map) {
    final eventType = map['eventType'] as String? ?? '';
    switch (eventType) {
      case 'peerFound':
        return PeerFoundEvent(
          peerId: map['peerId'] as String? ?? '',
          peerName: map['peerName'] as String? ?? 'Unknown Peer',
          rssi: (map['rssi'] as num?)?.toInt() ?? -70,
          connectionType: map['connectionType'] as String? ?? 'BLE',
        );
      case 'peerLost':
        return PeerLostEvent(peerId: map['peerId'] as String? ?? '');
      case 'peerConnected':
        return PeerConnectedEvent(
          peerId: map['peerId'] as String? ?? '',
          groupOwnerIp: map['groupOwnerIp'] as String?,
          isGroupOwner: map['isGroupOwner'] as bool? ?? false,
        );
      case 'peerDisconnected':
        return PeerDisconnectedEvent(peerId: map['peerId'] as String? ?? '');
      case 'packetReceived':
        final jsonStr = map['packetJson'] as String? ?? '{}';
        return PacketReceivedEvent(packet: PacketModel.fromJson(jsonStr));
      case 'connectionStateChanged':
        return ConnectionStateChangedEvent(
          isConnected: map['isConnected'] as bool? ?? false,
          activePeersCount: (map['activePeersCount'] as num?)?.toInt() ?? 0,
          peerId: map['peerId'] as String?,
          connectionState: map['connectionState'] as String?,
        );
      case 'error':
        return MeshErrorEvent(
          errorCode: map['errorCode'] as String? ?? 'UNKNOWN',
          message: map['message'] as String? ?? 'An unknown error occurred',
        );
      default:
        // Unknown events are silently dropped — future-proofing
        return MeshErrorEvent(
          errorCode: 'UNKNOWN_EVENT',
          message: 'Unrecognised event type: $eventType',
        );
    }
  }
}

class PeerFoundEvent extends MeshEvent {
  final String peerId;
  final String peerName;
  final int rssi;
  final String connectionType;

  const PeerFoundEvent({
    required this.peerId,
    required this.peerName,
    required this.rssi,
    required this.connectionType,
  });
}

class PeerLostEvent extends MeshEvent {
  final String peerId;
  const PeerLostEvent({required this.peerId});
}

class PeerConnectedEvent extends MeshEvent {
  final String peerId;
  final String? groupOwnerIp;
  final bool isGroupOwner;

  const PeerConnectedEvent({
    required this.peerId,
    this.groupOwnerIp,
    this.isGroupOwner = false,
  });
}

class PeerDisconnectedEvent extends MeshEvent {
  final String peerId;
  const PeerDisconnectedEvent({required this.peerId});
}

class PacketReceivedEvent extends MeshEvent {
  final PacketModel packet;
  const PacketReceivedEvent({required this.packet});
}

/// Emitted both for global connection state and per-peer Wi-Fi Direct state changes.
/// [peerId] and [connectionState] are null for global broadcasts.
/// [connectionState] values: "connecting" | "connected" | "failed" | "disconnected"
class ConnectionStateChangedEvent extends MeshEvent {
  final bool isConnected;
  final int activePeersCount;
  final String? peerId;
  final String? connectionState;

  const ConnectionStateChangedEvent({
    required this.isConnected,
    required this.activePeersCount,
    this.peerId,
    this.connectionState,
  });
}

class MeshErrorEvent extends MeshEvent {
  final String errorCode;
  final String message;
  const MeshErrorEvent({required this.errorCode, required this.message});
}
