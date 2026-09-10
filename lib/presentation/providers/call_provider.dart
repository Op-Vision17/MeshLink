import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../../data/datasources/platform_channel_datasource.dart';
import '../../data/models/packet_model.dart';
import 'mesh_provider.dart';

enum CallStatus {
  idle,
  outgoingRinging,
  incomingRinging,
  connected,
  ended,
}

class CallStateModel {
  final CallStatus status;
  final String? peerId;
  final String? peerName;
  final int? peerAvatar;
  final bool isMuted;
  final bool isSpeakerOn;
  final int durationSeconds;
  final bool isOutgoing;
  final String? endReason;

  const CallStateModel({
    this.status = CallStatus.idle,
    this.peerId,
    this.peerName,
    this.peerAvatar,
    this.isMuted = false,
    this.isSpeakerOn = true,
    this.durationSeconds = 0,
    this.isOutgoing = false,
    this.endReason,
  });

  CallStateModel copyWith({
    CallStatus? status,
    String? peerId,
    String? peerName,
    int? peerAvatar,
    bool? isMuted,
    bool? isSpeakerOn,
    int? durationSeconds,
    bool? isOutgoing,
    String? endReason,
  }) {
    return CallStateModel(
      status: status ?? this.status,
      peerId: peerId ?? this.peerId,
      peerName: peerName ?? this.peerName,
      peerAvatar: peerAvatar ?? this.peerAvatar,
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      endReason: endReason ?? this.endReason,
    );
  }
}

class CallNotifier extends StateNotifier<CallStateModel> {
  final Ref _ref;
  final PlatformChannelDataSource _platformDataSource;
  final Uuid _uuid = const Uuid();

  Timer? _ringingTimeoutTimer;
  Timer? _durationTimer;

  CallNotifier(this._ref, this._platformDataSource) : super(const CallStateModel()) {
    _initConnectionWatchdog();
  }

  void _initConnectionWatchdog() {
    _ref.listen<MeshUiState>(meshProvider, (prev, next) {
      if (state.status == CallStatus.connected ||
          state.status == CallStatus.outgoingRinging ||
          state.status == CallStatus.incomingRinging) {
        final activePeer = state.peerId;
        if (activePeer != null) {
          final isPeerStillConnected = next.peers.any((p) =>
              (p.id == activePeer || normalizeId(p.id) == normalizeId(activePeer)) &&
              p.isConnected);
          if (!isPeerStillConnected && prev != null) {
            final wasConnected = prev.peers.any((p) =>
                (p.id == activePeer || normalizeId(p.id) == normalizeId(activePeer)) &&
                p.isConnected);
            if (wasConnected) {
              _endCallInternal(reason: 'Connection Lost', sendSignal: false);
            }
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _ringingTimeoutTimer?.cancel();
    _durationTimer?.cancel();
    super.dispose();
  }

  /// Initiates an outgoing voice call to [peer].
  Future<bool> startOutgoingCall(PeerUiModel peer) async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      debugPrint('Microphone permission denied for voice calling');
      return false;
    }

    _cleanupTimers();

    state = CallStateModel(
      status: CallStatus.outgoingRinging,
      peerId: peer.id,
      peerName: peer.name,
      peerAvatar: 0,
      isOutgoing: true,
      isMuted: false,
      isSpeakerOn: true,
    );

    // Send CALL_OFFER signaling packet
    final localNodeId = _ref.read(meshProvider).localNodeId ?? 'local';
    final offerPayload = jsonEncode({
      'callerId': localNodeId,
      'callerName': 'User',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    final packet = PacketModel(
      messageId: _uuid.v4(),
      senderId: localNodeId,
      receiverId: peer.id,
      hopCount: 0,
      ttl: 7,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      packetType: PacketType.callOffer,
      payload: offerPayload,
    );

    await _ref.read(meshProvider.notifier).sendRawPacket(packet);

    // 30-second ringing timeout
    _ringingTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (state.status == CallStatus.outgoingRinging) {
        _endCallInternal(reason: 'No Answer', sendSignal: true);
      }
    });

    return true;
  }

  /// Handles incoming CALL_OFFER from a remote peer.
  void handleIncomingCallOffer(String callerId, String callerName, int callerAvatar) {
    if (state.status != CallStatus.idle) {
      // Busy: decline immediately
      _sendCallSignal(callerId, PacketType.callDecline, {'reason': 'busy'});
      return;
    }

    _cleanupTimers();

    state = CallStateModel(
      status: CallStatus.incomingRinging,
      peerId: callerId,
      peerName: callerName.isNotEmpty ? callerName : 'Peer ${callerId.takeLast(4)}',
      peerAvatar: callerAvatar,
      isOutgoing: false,
      isMuted: false,
      isSpeakerOn: true,
    );

    // 30-second incoming ringing timeout
    _ringingTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (state.status == CallStatus.incomingRinging) {
        declineIncomingCall();
      }
    });
  }

  /// Accepts an incoming call.
  Future<void> acceptIncomingCall() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      declineIncomingCall();
      return;
    }

    final peerId = state.peerId;
    if (peerId == null) return;

    _cleanupTimers();

    // Send CALL_ANSWER signaling packet
    final localNodeId = _ref.read(meshProvider).localNodeId;
    _sendCallSignal(peerId, PacketType.callAnswer, {
      'accepted': true,
      'responderId': localNodeId,
    });

    // Start native VoIP audio streaming
    final peerIp = await _platformDataSource.getConnectedPeerIp(peerId);
    await _platformDataSource.startLiveCall(peerIp);
    await _platformDataSource.setCallSpeakerphone(state.isSpeakerOn);

    state = state.copyWith(
      status: CallStatus.connected,
      durationSeconds: 0,
    );

    _startDurationTimer();
  }

  /// Handles remote peer accepting our outgoing call.
  Future<void> handleIncomingCallAnswer(String responderId) async {
    if (state.status != CallStatus.outgoingRinging || state.peerId != responderId) {
      return;
    }

    _cleanupTimers();

    // Start native VoIP audio streaming
    final peerIp = await _platformDataSource.getConnectedPeerIp(responderId);
    await _platformDataSource.startLiveCall(peerIp);
    await _platformDataSource.setCallSpeakerphone(state.isSpeakerOn);

    state = state.copyWith(
      status: CallStatus.connected,
      durationSeconds: 0,
    );

    _startDurationTimer();
  }

  /// Declines an incoming call.
  void declineIncomingCall() {
    final peerId = state.peerId;
    if (peerId != null) {
      _sendCallSignal(peerId, PacketType.callDecline, {'reason': 'declined'});
    }
    _endCallInternal(reason: 'Call Declined', sendSignal: false);
  }

  /// Handles remote peer declining our outgoing call.
  void handleIncomingCallDecline(String responderId) {
    if (state.peerId == responderId) {
      _endCallInternal(reason: 'Call Declined', sendSignal: false);
    }
  }

  /// Ends the active call.
  void endActiveCall() {
    final peerId = state.peerId;
    if (peerId != null) {
      _sendCallSignal(peerId, PacketType.callEnd, {'reason': 'hangup'});
    }
    _endCallInternal(reason: 'Call Ended', sendSignal: false);
  }

  /// Handles remote peer hanging up.
  void handleIncomingCallEnd(String senderId) {
    if (state.peerId == senderId) {
      _endCallInternal(reason: 'Call Ended', sendSignal: false);
    }
  }

  /// Toggles microphone mute.
  void toggleMute() {
    final newMute = !state.isMuted;
    _platformDataSource.setCallMuted(newMute);
    state = state.copyWith(isMuted: newMute);
  }

  /// Toggles between loud speaker and earpiece.
  void toggleSpeaker() {
    final newSpeaker = !state.isSpeakerOn;
    _platformDataSource.setCallSpeakerphone(newSpeaker);
    state = state.copyWith(isSpeakerOn: newSpeaker);
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.status == CallStatus.connected) {
        state = state.copyWith(durationSeconds: state.durationSeconds + 1);
      } else {
        timer.cancel();
      }
    });
  }

  void _endCallInternal({required String reason, required bool sendSignal}) {
    _cleanupTimers();

    if (sendSignal && state.peerId != null) {
      _sendCallSignal(state.peerId!, PacketType.callEnd, {'reason': reason});
    }

    _platformDataSource.stopLiveCall();

    state = state.copyWith(
      status: CallStatus.ended,
      endReason: reason,
    );

    // Reset to idle after 1.5 seconds so UI dismisses gracefully
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        state = const CallStateModel(status: CallStatus.idle);
      }
    });
  }

  void _sendCallSignal(String targetPeerId, PacketType type, Map<String, dynamic> data) {
    try {
      final localNodeId = _ref.read(meshProvider).localNodeId ?? 'local';
      final packet = PacketModel(
        messageId: _uuid.v4(),
        senderId: localNodeId,
        receiverId: targetPeerId,
        hopCount: 0,
        ttl: 7,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        packetType: type,
        payload: jsonEncode(data),
      );
      _ref.read(meshProvider.notifier).sendRawPacket(packet);
    } catch (e) {
      debugPrint('Error sending call signal $type: $e');
    }
  }

  void _cleanupTimers() {
    _ringingTimeoutTimer?.cancel();
    _ringingTimeoutTimer = null;
    _durationTimer?.cancel();
    _durationTimer = null;
  }
}

final callProvider = StateNotifierProvider<CallNotifier, CallStateModel>((ref) {
  final platformDs = ref.watch(platformDataSourceProvider);
  return CallNotifier(ref, platformDs);
});

extension StringHelper on String {
  String takeLast(int n) {
    if (length <= n) return this;
    return substring(length - n);
  }
}
