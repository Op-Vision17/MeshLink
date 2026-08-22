import 'dart:async';
import 'package:flutter/services.dart';
import '../../core/constants/channel_constants.dart';
import '../../domain/entities/mesh_event.dart';
import '../models/packet_model.dart';

class PlatformChannelDataSource {
  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  PlatformChannelDataSource({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel = methodChannel ??
            const MethodChannel(ChannelConstants.methodChannelName),
        _eventChannel = eventChannel ??
            const EventChannel(ChannelConstants.eventChannelName);

  Future<bool> startDiscovery() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        ChannelConstants.methodStartDiscovery,
      );
      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception('Failed to start discovery: ${e.message}');
    }
  }

  Future<bool> stopDiscovery() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        ChannelConstants.methodStopDiscovery,
      );
      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception('Failed to stop discovery: ${e.message}');
    }
  }

  Future<bool> connectToPeer(String peerId, {String? peerName, String? macAddress}) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        ChannelConstants.methodConnectToPeer,
        {
          'peerId': peerId,
          'peerName': peerName,
          'macAddress': macAddress,
        },
      );
      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception('Failed to connect to peer $peerId: ${e.message}');
    }
  }

  Future<bool> disconnectFromPeer(String peerId) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        ChannelConstants.methodDisconnectFromPeer,
        {'peerId': peerId},
      );
      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception('Failed to disconnect peer $peerId: ${e.message}');
    }
  }

  Future<bool> sendPacket(PacketModel packet) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        ChannelConstants.methodSendPacket,
        {'packetJson': packet.toJson()},
      );
      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception('Failed to send packet ${packet.messageId}: ${e.message}');
    }
  }

  Future<bool> isBluetoothEnabled() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        ChannelConstants.methodIsBluetoothEnabled,
      );
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> requestEnableBluetooth() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        ChannelConstants.methodRequestEnableBluetooth,
      );
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> isLocationServiceEnabled() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        ChannelConstants.methodIsLocationServiceEnabled,
      );
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> requestEnableLocationService() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        ChannelConstants.methodRequestEnableLocationService,
      );
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> isWifiEnabled() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        ChannelConstants.methodIsWifiEnabled,
      );
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> requestEnableWifi() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        ChannelConstants.methodRequestEnableWifi,
      );
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> updateUserProfile(String displayName, int avatarIndex) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        ChannelConstants.methodUpdateUserProfile,
        {
          'displayName': displayName,
          'avatarIndex': avatarIndex,
        },
      );
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> openFile(String filePath) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        ChannelConstants.methodOpenFile,
        {'filePath': filePath},
      );
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<String?> saveFileToDownloads(String filePath, String fileName) async {
    try {
      final result = await _methodChannel.invokeMethod<String>(
        ChannelConstants.methodSaveFileToDownloads,
        {
          'filePath': filePath,
          'fileName': fileName,
        },
      );
      return result;
    } on PlatformException catch (_) {
      return null;
    }
  }

  Future<String?> createVideoThumbnail(String videoPath) async {
    try {
      final result = await _methodChannel.invokeMethod<String>(
        ChannelConstants.methodCreateVideoThumbnail,
        {'videoPath': videoPath},
      );
      return result;
    } on PlatformException catch (_) {
      return null;
    }
  }

  Future<String?> getLocalNodeId() async {
    try {
      final result = await _methodChannel.invokeMethod<String>(
        ChannelConstants.methodGetLocalNodeId,
      );
      return result;
    } on PlatformException catch (_) {
      return null;
    }
  }

  Stream<MeshEvent> get meshEvents {
    return _eventChannel.receiveBroadcastStream().map((dynamic eventData) {
      final map = Map<String, dynamic>.from(eventData as Map);
      return MeshEvent.fromMap(map);
    });
  }
}
