import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/file_transfer_manager.dart';
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
  final FileTransferManager _fileTransferManager = FileTransferManager();

  StreamSubscription<MeshEvent>? _eventSubscription;

  MeshNotifier(
    this._repository,
    this._sendMessageUseCase,
    this._messageRepository,
    this._syncPeerListUseCase,
    this._peerRepository,
  ) : super(const MeshUiState(
          isDiscovering: false,
          statusMessage: 'MeshLink initialized',
          peers: [],
          savedPeers: [],
          receivedPackets: [],
        )) {
    _init();
  }

  void _addDebugLog(String log) {
    debugPrint('[MeshEngine] $log');
    final updated = [...state.debugLogs, '${DateTime.now().toIso8601String().substring(11, 19)} $log'];
    if (updated.length > 50) updated.removeAt(0);
    state = state.copyWith(debugLogs: updated);
  }

  Future<void> _init() async {
    try {
      final savedNodes = await _peerRepository.getPeers();
      final savedUi = savedNodes.map((n) {
        return PeerUiModel(
          id: n.id,
          name: n.name,
          rssi: n.rssi,
          connectionType: n.connectionType,
          wifiState: PeerWifiState.disconnected,
        );
      }).toList();

      final List<ChatMessage> allPastMessages = [];
      for (final node in savedNodes) {
        final msgs = await _messageRepository.getMessagesForConversation(normalizeId(node.id));
        allPastMessages.addAll(msgs);
      }

      state = state.copyWith(
        savedPeers: savedUi,
        chatMessages: allPastMessages,
      );
    } catch (e) {
      _addDebugLog('Failed to load saved peers and messages: $e');
    }

    try {
      final nodeId = await _repository.getLocalNodeId();
      state = state.copyWith(localNodeId: nodeId);
      _addDebugLog('Local Node ID: $nodeId');
    } catch (e) {
      _addDebugLog('Could not get local node ID: $e');
    }

    _eventSubscription = _repository.meshEvents.listen(
      (event) {
        _handleEvent(event);
      },
      onError: (error) {
        final errStr = 'Event stream error: $error';
        _addDebugLog('❌ $errStr');
        state = state.copyWith(statusMessage: errStr);
      },
    );
  }

  void _handleEvent(MeshEvent event) async {
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
        final conversationId = cleanSender.isNotEmpty ? cleanSender : 'broadcast';
        _addDebugLog('📩 Packet Received from $cleanSender (${event.packet.packetType})');

        if (event.packet.packetType == PacketType.fileMeta) {
          try {
            final meta = FileMetadataPayload.fromJson(event.packet.payload);
            await _fileTransferManager.handleIncomingMeta(meta);
            final msgType = MessageType.values.firstWhere(
              (e) => e.name == meta.messageType,
              orElse: () => MessageType.file,
            );
            final fileMsg = ChatMessage(
              id: meta.fileId,
              senderId: cleanSender,
              receiverId: cleanReceiver,
              content: meta.fileName,
              timestamp: DateTime.fromMillisecondsSinceEpoch(event.packet.timestamp),
              status: MessageStatus.sending,
              messageType: msgType,
              fileName: meta.fileName,
              fileSize: meta.totalBytes,
              progress: 0.0,
            );
            state = state.copyWith(
              chatMessages: [...state.chatMessages, fileMsg],
              statusMessage: 'Incoming file: ${meta.fileName}',
            );
          } catch (e) {
            _addDebugLog('Failed to parse FILE_META: $e');
          }
          return;
        }

        if (event.packet.packetType == PacketType.fileChunk) {
          try {
            final chunk = FileChunkPayload.fromJson(event.packet.payload);
            final result = await _fileTransferManager.handleIncomingChunk(chunk);
            if (result != null) {
              final updated = state.chatMessages.map((m) {
                if (m.id == chunk.fileId) {
                  return m.copyWith(
                    progress: result.progress,
                    localFilePath: result.isCompleted ? result.localPath : m.localFilePath,
                    status: result.isCompleted ? MessageStatus.delivered : MessageStatus.sending,
                  );
                }
                return m;
              }).toList();

              state = state.copyWith(chatMessages: updated);

              if (result.isCompleted && result.localPath != null) {
                final completedMsg = state.chatMessages.firstWhere((m) => m.id == chunk.fileId);
                await _messageRepository.saveMessage(completedMsg, conversationId: conversationId);

                // Send FILE_ACK back
                await _repository.sendPacket(PacketModel(
                  messageId: 'ack_${chunk.fileId}',
                  senderId: 'local',
                  receiverId: cleanSender,
                  timestamp: DateTime.now().millisecondsSinceEpoch,
                  packetType: PacketType.fileAck,
                  payload: jsonEncode({'fileId': chunk.fileId, 'status': 'DELIVERED'}),
                ));
              }
            }
          } catch (e) {
            _addDebugLog('Failed to process FILE_CHUNK: $e');
          }
          return;
        }

        if (event.packet.packetType == PacketType.fileAck) {
          try {
            final map = jsonDecode(event.packet.payload) as Map<String, dynamic>;
            final ackFileId = map['fileId'] as String?;
            final statusStr = map['status'] as String? ?? 'DELIVERED';

            if (ackFileId != null) {
              if (statusStr == 'CANCELLED') {
                _fileTransferManager.cancelTransfer(ackFileId);
                await _messageRepository.deleteMessage(ackFileId);
                final updated = state.chatMessages.where((m) => m.id != ackFileId).toList();
                state = state.copyWith(chatMessages: updated, statusMessage: 'Transfer cancelled');
              } else {
                final updated = state.chatMessages.map((m) {
                  if (m.id == ackFileId) {
                    final acked = m.copyWith(status: MessageStatus.delivered, progress: 1.0);
                    _messageRepository.saveMessage(acked, conversationId: conversationId);
                    return acked;
                  }
                  return m;
                }).toList();
                state = state.copyWith(chatMessages: updated);
              }
            }
          } catch (e) {
            _addDebugLog('Failed to parse FILE_ACK: $e');
          }
          return;
        }

        // Standard text packet
        final newMsg = ChatMessage(
          id: event.packet.messageId,
          senderId: cleanSender,
          receiverId: cleanReceiver,
          content: event.packet.payload,
          timestamp: DateTime.fromMillisecondsSinceEpoch(event.packet.timestamp),
          status: MessageStatus.delivered,
          messageType: MessageType.text,
        );
        _messageRepository.saveMessage(newMsg, conversationId: conversationId);

        final senderName = state.peers.firstWhere(
          (p) => p.id == event.packet.senderId || normalizeId(p.id) == cleanSender,
          orElse: () => state.savedPeers.firstWhere(
            (sp) => sp.id == event.packet.senderId || normalizeId(sp.id) == cleanSender,
            orElse: () => PeerUiModel(id: cleanSender, name: 'Friend $cleanSender', rssi: -60, connectionType: 'Direct'),
          ),
        ).name;

        final senderPeerNode = PeerNode(
          id: cleanSender,
          name: senderName,
          rssi: -60,
          connectionType: 'Direct',
          lastSeen: DateTime.now(),
        );
        _peerRepository.savePeer(senderPeerNode);
        _upsertSavedPeer(senderPeerNode);

        state = state.copyWith(
          receivedPackets: [...state.receivedPackets, event.packet],
          chatMessages: [...state.chatMessages, newMsg],
          statusMessage: 'Message ← $cleanSender',
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

  void _upsertSavedPeer(PeerNode peer) {
    final norm = normalizeId(peer.id);
    final idx = state.savedPeers.indexWhere((p) => p.id == peer.id || normalizeId(p.id) == norm);
    final updatedSaved = List<PeerUiModel>.from(state.savedPeers);
    final uiModel = PeerUiModel(
      id: peer.id,
      name: peer.name,
      rssi: peer.rssi,
      connectionType: peer.connectionType,
      wifiState: PeerWifiState.disconnected,
    );
    if (idx >= 0) {
      updatedSaved[idx] = updatedSaved[idx].copyWith(name: peer.name);
    } else {
      updatedSaved.add(uiModel);
    }
    state = state.copyWith(savedPeers: updatedSaved);
  }

  void _upsertPeer(PeerUiModel peer) {
    final norm = normalizeId(peer.id);
    final idx = state.peers.indexWhere((p) => p.id == peer.id || normalizeId(p.id) == norm);
    final updatedLive = List<PeerUiModel>.from(state.peers);
    if (idx >= 0) {
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

    final updatedSaved = state.savedPeers.map((sp) {
      return (sp.id == peerId || normalizeId(sp.id) == norm) ? update(sp) : sp;
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

  Future<void> deleteConversation(String peerId) async {
    try {
      final norm = normalizeId(peerId);
      await _messageRepository.deleteConversation(norm);
      final updatedMsgs = state.chatMessages.where((m) =>
          m.senderId != peerId &&
          normalizeId(m.senderId) != norm &&
          m.receiverId != peerId &&
          normalizeId(m.receiverId) != norm).toList();
      state = state.copyWith(chatMessages: updatedMsgs);
    } catch (e) {
      debugPrint('Failed to delete conversation with $peerId: $e');
    }
  }

  Future<void> deleteMessage(String messageId) async {
    try {
      await _messageRepository.deleteMessage(messageId);
      final updatedMsgs = state.chatMessages.where((m) => m.id != messageId).toList();
      state = state.copyWith(chatMessages: updatedMsgs);
    } catch (e) {
      debugPrint('Failed to delete message $messageId: $e');
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
      messageType: MessageType.text,
    );

    state = state.copyWith(
      chatMessages: [...state.chatMessages, chatMsg],
      statusMessage: 'Sending message to $receiverId…',
    );

    final success = await _sendMessageUseCase.execute(packet);

    final targetName = state.peers.firstWhere(
      (p) => p.id == receiverId || normalizeId(p.id) == normalizeId(receiverId),
      orElse: () => state.savedPeers.firstWhere(
        (sp) => sp.id == receiverId || normalizeId(sp.id) == normalizeId(receiverId),
        orElse: () => PeerUiModel(id: receiverId, name: 'Friend ${normalizeId(receiverId)}', rssi: -60, connectionType: 'Direct'),
      ),
    ).name;

    final peerNode = PeerNode(
      id: normalizeId(receiverId),
      name: targetName,
      rssi: -60,
      connectionType: 'Direct',
      lastSeen: DateTime.now(),
    );
    _peerRepository.savePeer(peerNode);
    _upsertSavedPeer(peerNode);

    final updatedMessages = state.chatMessages.map((m) {
      if (m.id == msgId) {
        return m.copyWith(status: success ? MessageStatus.sent : MessageStatus.failed);
      }
      return m;
    }).toList();

    state = state.copyWith(
      chatMessages: updatedMessages,
      statusMessage: success ? 'Message sent' : 'Failed to send message',
    );
  }

  Future<void> sendMessage({
    required String receiverId,
    required String content,
  }) async {
    await sendPacket(receiverId: receiverId, payload: content);
  }

  // ── High-Speed Offline File Transfer ──────────────────────────────────────

  Future<void> sendFile({
    required String receiverId,
    required File file,
    required MessageType type,
  }) async {
    final fileId = 'file_${DateTime.now().millisecondsSinceEpoch}';
    final meta = await _fileTransferManager.prepareFileForSend(
      fileId: fileId,
      file: file,
      type: type,
    );

    final targetName = state.peers.firstWhere(
      (p) => p.id == receiverId || normalizeId(p.id) == normalizeId(receiverId),
      orElse: () => state.savedPeers.firstWhere(
        (sp) => sp.id == receiverId || normalizeId(sp.id) == normalizeId(receiverId),
        orElse: () => PeerUiModel(id: receiverId, name: 'Friend ${normalizeId(receiverId)}', rssi: -60, connectionType: 'Direct'),
      ),
    ).name;

    final sendPeerNode = PeerNode(
      id: normalizeId(receiverId),
      name: targetName,
      rssi: -60,
      connectionType: 'Direct',
      lastSeen: DateTime.now(),
    );
    _peerRepository.savePeer(sendPeerNode);
    _upsertSavedPeer(sendPeerNode);

    final cleanReceiver = normalizeId(receiverId);
    final chatMsg = ChatMessage(
      id: fileId,
      senderId: 'local',
      receiverId: receiverId,
      content: meta.fileName,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      messageType: type,
      localFilePath: file.path,
      fileName: meta.fileName,
      fileSize: meta.totalBytes,
      progress: 0.0,
    );

    state = state.copyWith(
      chatMessages: [...state.chatMessages, chatMsg],
      statusMessage: 'Sending ${meta.fileName}…',
    );

    // 1. Send FILE_META packet
    final metaPacket = PacketModel(
      messageId: 'meta_$fileId',
      senderId: 'local',
      receiverId: receiverId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      packetType: PacketType.fileMeta,
      payload: meta.toJson(),
    );

    await _repository.sendPacket(metaPacket);

    // 2. Stream 64KB Chunks
    int sentChunks = 0;
    await for (final chunk in _fileTransferManager.streamFileChunks(
      fileId: fileId,
      file: file,
      totalChunks: meta.totalChunks,
    )) {
      if (_fileTransferManager.isTransferCancelled(fileId)) {
        await _messageRepository.deleteMessage(fileId);
        final updated = state.chatMessages.where((m) => m.id != fileId).toList();
        state = state.copyWith(chatMessages: updated, statusMessage: 'Transfer cancelled');
        try {
          await _repository.sendPacket(PacketModel(
            messageId: 'cancel_$fileId',
            senderId: 'local',
            receiverId: receiverId,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            packetType: PacketType.fileAck,
            payload: jsonEncode({'fileId': fileId, 'status': 'CANCELLED'}),
          ));
        } catch (_) {}
        return;
      }

      final chunkPacket = PacketModel(
        messageId: 'chk_${fileId}_${chunk.chunkIndex}',
        senderId: 'local',
        receiverId: receiverId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        packetType: PacketType.fileChunk,
        payload: chunk.toJson(),
      );

      await _repository.sendPacket(chunkPacket);
      sentChunks++;
      final prog = (sentChunks / meta.totalChunks).clamp(0.0, 1.0);

      final updated = state.chatMessages.map((m) {
        if (m.id == fileId) {
          return m.copyWith(progress: prog);
        }
        return m;
      }).toList();
      state = state.copyWith(chatMessages: updated);
    }

    if (_fileTransferManager.isTransferCancelled(fileId)) {
      await _messageRepository.deleteMessage(fileId);
      final updated = state.chatMessages.where((m) => m.id != fileId).toList();
      state = state.copyWith(chatMessages: updated, statusMessage: 'Transfer cancelled');
      return;
    }

    // 3. Mark locally as sent
    final finalSent = state.chatMessages.map((m) {
      if (m.id == fileId) {
        final sent = m.copyWith(status: MessageStatus.sent, progress: 1.0);
        _messageRepository.saveMessage(sent, conversationId: cleanReceiver);
        return sent;
      }
      return m;
    }).toList();

    state = state.copyWith(
      chatMessages: finalSent,
      statusMessage: 'Sent ${meta.fileName}',
    );
  }

  Future<void> cancelFileTransfer(String fileId, {required String receiverId}) async {
    _fileTransferManager.cancelTransfer(fileId);
    await _messageRepository.deleteMessage(fileId);
    final updated = state.chatMessages.where((m) => m.id != fileId).toList();

    state = state.copyWith(
      chatMessages: updated,
      statusMessage: 'Transfer cancelled',
    );

    try {
      await _repository.sendPacket(PacketModel(
        messageId: 'cancel_$fileId',
        senderId: 'local',
        receiverId: receiverId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        packetType: PacketType.fileAck,
        payload: jsonEncode({'fileId': fileId, 'status': 'CANCELLED'}),
      ));
    } catch (_) {}
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
