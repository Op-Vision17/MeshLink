import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/isar_datasource.dart';
import '../../data/datasources/platform_channel_datasource.dart';
import '../../data/models/packet_model.dart';
import '../../data/repositories/message_repository_impl.dart';
import '../../data/repositories/mesh_repository_impl.dart';
import '../../data/repositories/peer_repository_impl.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/mesh_event.dart';
import '../../domain/entities/peer_node.dart';
import '../../domain/repositories/message_repository.dart';
import '../../domain/repositories/mesh_repository.dart';
import '../../domain/repositories/peer_repository.dart';
import '../../domain/usecases/get_conversation_messages_usecase.dart';
import '../../domain/usecases/send_message_usecase.dart';
import '../../domain/usecases/sync_peer_list_usecase.dart';

String normalizeId(String id) {
  if (id.isEmpty || id == 'broadcast' || id == '*') return id;
  if (id.length <= 8) return id.toLowerCase();
  return id.substring(0, 8).toLowerCase();
}

final isarDataSourceProvider = Provider<IsarDataSource>((ref) {
  return IsarDataSource();
});

final activeChatPeerIdProvider = StateProvider<String?>((ref) => null);

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  final isarDs = ref.watch(isarDataSourceProvider);
  return MessageRepositoryImpl(isarDs);
});

final peerRepositoryProvider = Provider<PeerRepository>((ref) {
  final isarDs = ref.watch(isarDataSourceProvider);
  return PeerRepositoryImpl(isarDs);
});

final platformDataSourceProvider = Provider<PlatformChannelDataSource>((ref) {
  return PlatformChannelDataSource();
});

final meshRepositoryProvider = Provider<MeshRepository>((ref) {
  final ds = ref.watch(platformDataSourceProvider);
  return MeshRepositoryImpl(ds);
});

final sendMessageUseCaseProvider = Provider<SendMessageUseCase>((ref) {
  final meshRepo = ref.watch(meshRepositoryProvider);
  final msgRepo = ref.watch(messageRepositoryProvider);
  return SendMessageUseCase(meshRepo, msgRepo);
});

final getConversationMessagesUseCaseProvider =
    Provider<GetConversationMessagesUseCase>((ref) {
  final msgRepo = ref.watch(messageRepositoryProvider);
  return GetConversationMessagesUseCase(msgRepo);
});

final syncPeerListUseCaseProvider = Provider<SyncPeerListUseCase>((ref) {
  final peerRepo = ref.watch(peerRepositoryProvider);
  return SyncPeerListUseCase(peerRepo);
});

final conversationMessagesStreamProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, peerId) {
  final useCase = ref.watch(getConversationMessagesUseCaseProvider);
  return useCase.watchMessages(peerId);
});

// Per-peer Wi-Fi Direct connection states received from the native layer
enum PeerWifiState { discovered, connecting, connected, failed, disconnected }

PeerWifiState _parseWifiState(String? raw) {
  switch (raw) {
    case 'connecting':
      return PeerWifiState.connecting;
    case 'connected':
      return PeerWifiState.connected;
    case 'failed':
      return PeerWifiState.failed;
    case 'disconnected':
      return PeerWifiState.disconnected;
    default:
      return PeerWifiState.discovered;
  }
}

class PeerUiModel {
  final String id;
  final String name;
  final int rssi;
  final String connectionType;
  final PeerWifiState wifiState;
  final String? groupOwnerIp;

  const PeerUiModel({
    required this.id,
    required this.name,
    required this.rssi,
    required this.connectionType,
    this.wifiState = PeerWifiState.discovered,
    this.groupOwnerIp,
  });

  bool get isConnected => wifiState == PeerWifiState.connected;
  bool get isConnecting => wifiState == PeerWifiState.connecting;

  PeerUiModel copyWith({
    String? id,
    String? name,
    int? rssi,
    String? connectionType,
    PeerWifiState? wifiState,
    String? groupOwnerIp,
  }) {
    return PeerUiModel(
      id: id ?? this.id,
      name: name ?? this.name,
      rssi: rssi ?? this.rssi,
      connectionType: connectionType ?? this.connectionType,
      wifiState: wifiState ?? this.wifiState,
      groupOwnerIp: groupOwnerIp ?? this.groupOwnerIp,
    );
  }
}

class MeshUiState {
  final bool isDiscovering;
  final String statusMessage;
  final String? localNodeId;
  final List<PeerUiModel> peers;
  final List<PeerUiModel> savedPeers;
  final List<PacketModel> receivedPackets;
  final List<ChatMessage> chatMessages;
  final List<String> errorLog;
  final List<String> debugLogs;

  const MeshUiState({
    required this.isDiscovering,
    required this.statusMessage,
    this.localNodeId,
    required this.peers,
    this.savedPeers = const [],
    required this.receivedPackets,
    this.chatMessages = const [],
    this.errorLog = const [],
    this.debugLogs = const [],
  });

  MeshUiState copyWith({
    bool? isDiscovering,
    String? statusMessage,
    String? localNodeId,
    List<PeerUiModel>? peers,
    List<PeerUiModel>? savedPeers,
    List<PacketModel>? receivedPackets,
    List<ChatMessage>? chatMessages,
    List<String>? errorLog,
    List<String>? debugLogs,
  }) {
    return MeshUiState(
      isDiscovering: isDiscovering ?? this.isDiscovering,
      statusMessage: statusMessage ?? this.statusMessage,
      localNodeId: localNodeId ?? this.localNodeId,
      peers: peers ?? this.peers,
      savedPeers: savedPeers ?? this.savedPeers,
      receivedPackets: receivedPackets ?? this.receivedPackets,
      chatMessages: chatMessages ?? this.chatMessages,
      errorLog: errorLog ?? this.errorLog,
      debugLogs: debugLogs ?? this.debugLogs,
    );
  }
}

class MeshNotifier extends StateNotifier<MeshUiState> {
  final MeshRepository _repository;
  final SendMessageUseCase _sendMessageUseCase;
  final MessageRepository _messageRepository;
  final SyncPeerListUseCase _syncPeerListUseCase;
  final PeerRepository _peerRepository;
  StreamSubscription<MeshEvent>? _eventSubscription;

  MeshNotifier(
    this._repository,
    this._sendMessageUseCase,
    this._messageRepository,
    this._syncPeerListUseCase,
    this._peerRepository,
  ) : super(const MeshUiState(
          isDiscovering: false,
          statusMessage: 'Ready',
          peers: [],
          receivedPackets: [],
          chatMessages: [],
          debugLogs: [],
        )) {
    _initPersistenceAndEvents();
  }

  void _addDebugLog(String log) {
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final entry = '[$timeStr] $log';
    debugPrint('[MeshLink Debug] $entry');
    state = state.copyWith(debugLogs: [...state.debugLogs, entry]);
  }

  void clearDebugLogs() {
    state = state.copyWith(debugLogs: [], errorLog: []);
  }

  Future<void> _initPersistenceAndEvents() async {
    _listenToEvents();
    try {
      final savedPeers = await _peerRepository.getPeers();
      final peerModels = savedPeers
          .map((p) => PeerUiModel(
                id: p.id,
                name: p.name,
                rssi: -60,
                connectionType: 'Saved Friend',
                wifiState: PeerWifiState.disconnected,
              ))
          .toList();
      state = state.copyWith(savedPeers: peerModels);
    } catch (e) {
      debugPrint('Error loading saved peers: $e');
    }

    try {
      final nodeId = await _repository.getLocalNodeId();
      if (nodeId != null && nodeId.isNotEmpty) {
        state = state.copyWith(localNodeId: nodeId);
        debugPrint('[MeshLink] Local Node ID initialized: $nodeId');
      }
    } catch (e) {
      debugPrint('Error getting local Node ID: $e');
    }
  }

  void _listenToEvents() {
    _eventSubscription = _repository.meshEvents.listen(
      _handleEvent,
      onError: (Object err) {
        final errStr = 'Event stream error: $err';
        _addDebugLog('❌ $errStr');
        state = state.copyWith(statusMessage: errStr);
      },
    );
  }

  void _handleEvent(MeshEvent event) {
    switch (event) {
      case PeerFoundEvent():
        _addDebugLog('🔍 Peer Found: ${event.peerName} (${event.peerId}) RSSI=${event.rssi}');
        final uiModel = PeerUiModel(
          id: event.peerId,
          name: event.peerName,
          rssi: event.rssi,
          connectionType: event.connectionType,
        );
        _upsertPeer(uiModel);
        _syncPeerListUseCase.execute(PeerNode(
          id: event.peerId,
          name: event.peerName,
          connectionType: event.connectionType,
          rssi: event.rssi,
          lastSeen: DateTime.now(),
        ));
        state = state.copyWith(
          statusMessage: 'Discovered: ${event.peerName}',
        );

      case PeerLostEvent():
        _addDebugLog('⚠️ Peer Lost: ${event.peerId}');
        state = state.copyWith(
          peers: state.peers.where((p) => p.id != event.peerId).toList(),
          statusMessage: 'Lost peer: ${event.peerId}',
        );

      case PeerConnectedEvent():
        _addDebugLog('✅ Connected to ${event.peerId} (IP: ${event.groupOwnerIp ?? "GroupOwner"})');
        _updatePeer(event.peerId, (p) => p.copyWith(
              wifiState: PeerWifiState.connected,
              groupOwnerIp: event.groupOwnerIp,
            ));
        state = state.copyWith(
          statusMessage:
              'Connected ✓ ${event.peerId}${event.groupOwnerIp != null ? " @ ${event.groupOwnerIp}" : ""}',
        );

      case PeerDisconnectedEvent():
        _addDebugLog('🔌 Disconnected: ${event.peerId}');
        _updatePeer(event.peerId,
            (p) => p.copyWith(wifiState: PeerWifiState.disconnected));
        state = state.copyWith(statusMessage: 'Disconnected: ${event.peerId}');

      case ConnectionStateChangedEvent():
        _addDebugLog('🔄 State change for ${event.peerId ?? "Mesh"}: state=${event.connectionState} isConnected=${event.isConnected}');
        if (event.peerId != null && event.connectionState != null) {
          _updatePeer(event.peerId!, (p) => p.copyWith(
                wifiState: _parseWifiState(event.connectionState),
              ));
        }
        if (event.peerId == null) {
          state = state.copyWith(
            statusMessage: event.isConnected
                ? 'Active connections: ${event.activePeersCount}'
                : 'Mesh idle',
          );
        }

      case PacketReceivedEvent():
        final cleanSender = normalizeId(event.packet.senderId);
        final cleanReceiver = normalizeId(event.packet.receiverId);
        _addDebugLog('📩 Packet Received from $cleanSender (${event.packet.packetType})');
        final conversationId = cleanSender.isNotEmpty ? cleanSender : 'broadcast';
        final newMsg = ChatMessage(
          id: event.packet.messageId,
          senderId: cleanSender,
          receiverId: cleanReceiver,
          content: event.packet.payload,
          timestamp: DateTime.fromMillisecondsSinceEpoch(event.packet.timestamp),
          status: MessageStatus.delivered,
        );
        _messageRepository.saveMessage(newMsg, conversationId: conversationId);
        state = state.copyWith(
          receivedPackets: [...state.receivedPackets, event.packet],
          chatMessages: [...state.chatMessages, newMsg],
          statusMessage: 'Packet ← $cleanSender',
        );

      case MeshErrorEvent():
        final entry = '[${event.errorCode}] ${event.message}';
        _addDebugLog('🚨 ERROR ${event.errorCode}: ${event.message}');
        state = state.copyWith(
          statusMessage: 'Error: ${event.message}',
          errorLog: [...state.errorLog, entry],
        );
    }
  }

  // ── Peer helpers ─────────────────────────────────────────────────────────

  void _upsertPeer(PeerUiModel peer) {
    final norm = normalizeId(peer.id);
    final idx = state.peers.indexWhere((p) => p.id == peer.id || normalizeId(p.id) == norm);
    final updatedLive = List<PeerUiModel>.from(state.peers);
    if (idx >= 0) {
      // Preserve Wi-Fi state and groupOwnerIp on re-advertisement
      updatedLive[idx] = updatedLive[idx].copyWith(
        name: peer.name,
        rssi: peer.rssi,
        connectionType: peer.connectionType,
      );
    } else {
      updatedLive.add(peer);
    }

    final updatedSaved = state.savedPeers.map((sp) {
      if (sp.id == peer.id || normalizeId(sp.id) == norm) {
        return sp.copyWith(name: peer.name);
      }
      return sp;
    }).toList();

    state = state.copyWith(peers: updatedLive, savedPeers: updatedSaved);
  }

  void _updatePeer(String peerId, PeerUiModel Function(PeerUiModel) update) {
    final norm = normalizeId(peerId);
    final updatedLive = state.peers.map((p) {
      return (p.id == peerId || normalizeId(p.id) == norm) ? update(p) : p;
    }).toList();

    final updatedSaved = state.savedPeers.map((p) {
      return (p.id == peerId || normalizeId(p.id) == norm) ? update(p) : p;
    }).toList();

    state = state.copyWith(peers: updatedLive, savedPeers: updatedSaved);
  }

  // ── Public actions ────────────────────────────────────────────────────────

  Future<void> startDiscovery() async {
    state = state.copyWith(
      isDiscovering: true,
      statusMessage: 'Looking for nearby friends…',
    );
    await _repository.startDiscovery();
  }

  Future<void> forgetFriend(String peerId) async {
    try {
      await _peerRepository.deletePeer(peerId);
      final norm = normalizeId(peerId);
      final updatedSaved = state.savedPeers.where((p) => p.id != peerId && normalizeId(p.id) != norm).toList();
      state = state.copyWith(savedPeers: updatedSaved);
    } catch (e) {
      debugPrint('Failed to forget friend $peerId: $e');
    }
  }

  Future<void> stopDiscovery() async {
    await _repository.stopDiscovery();
    state = state.copyWith(
      isDiscovering: false,
      statusMessage: 'Discovery stopped',
    );
  }

  Future<void> connectToPeer(String peerId, {String? peerName}) async {
    final targetPeer = state.peers.firstWhere(
      (p) => p.id == peerId,
      orElse: () => state.savedPeers.firstWhere(
        (sp) => sp.id == peerId,
        orElse: () => PeerUiModel(id: peerId, name: peerName ?? peerId, rssi: -60, connectionType: 'Saved'),
      ),
    );
    _updatePeer(peerId, (p) => p.copyWith(wifiState: PeerWifiState.connecting));
    state = state.copyWith(statusMessage: 'Connecting to ${targetPeer.name}…');
    await _repository.connectToPeer(peerId, peerName: targetPeer.name);
  }

  Future<void> disconnectFromPeer(String peerId) async {
    _updatePeer(peerId, (p) => p.copyWith(wifiState: PeerWifiState.disconnected, groupOwnerIp: null));
    state = state.copyWith(statusMessage: 'Disconnected from $peerId');
    await _repository.disconnectFromPeer(peerId);
  }

  Future<void> sendPacket({
    required String receiverId,
    required String payload,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final msgId = 'msg_$timestamp';
    final packet = PacketModel(
      messageId: msgId,
      senderId: 'local',
      receiverId: receiverId,
      timestamp: timestamp,
      packetType: PacketType.text,
      payload: payload,
    );

    final chatMsg = ChatMessage(
      id: msgId,
      senderId: 'local',
      receiverId: receiverId,
      content: payload,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
      status: MessageStatus.sending,
    );

    state = state.copyWith(
      chatMessages: [...state.chatMessages, chatMsg],
      statusMessage: 'Sending packet to $receiverId…',
    );

    final success = await _sendMessageUseCase.execute(packet);
    
    // Update message status
    final updatedMessages = state.chatMessages.map((m) {
      if (m.id == msgId) {
        return ChatMessage(
          id: m.id,
          senderId: m.senderId,
          receiverId: m.receiverId,
          content: m.content,
          timestamp: m.timestamp,
          status: success ? MessageStatus.sent : MessageStatus.failed,
        );
      }
      return m;
    }).toList();

    state = state.copyWith(
      chatMessages: updatedMessages,
      statusMessage: success ? 'Packet → $receiverId' : 'Failed to send packet',
    );
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }
}

final meshProvider = StateNotifierProvider<MeshNotifier, MeshUiState>((ref) {
  final repository = ref.watch(meshRepositoryProvider);
  final sendMessageUseCase = ref.watch(sendMessageUseCaseProvider);
  final messageRepository = ref.watch(messageRepositoryProvider);
  final syncPeerListUseCase = ref.watch(syncPeerListUseCaseProvider);
  final peerRepository = ref.watch(peerRepositoryProvider);
  return MeshNotifier(
    repository,
    sendMessageUseCase,
    messageRepository,
    syncPeerListUseCase,
    peerRepository,
  );
});
