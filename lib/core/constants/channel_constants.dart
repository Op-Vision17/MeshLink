abstract class ChannelConstants {
  static const String methodChannelName = 'com.meshlink.app/mesh_method';
  static const String eventChannelName = 'com.meshlink.app/mesh_events';

  // Method Names
  static const String methodStartDiscovery = 'startDiscovery';
  static const String methodStopDiscovery = 'stopDiscovery';
  static const String methodSendPacket = 'sendPacket';
  static const String methodConnectToPeer = 'connectToPeer';
  static const String methodDisconnectFromPeer = 'disconnectFromPeer';
  static const String methodIsBluetoothEnabled = 'isBluetoothEnabled';
  static const String methodRequestEnableBluetooth = 'requestEnableBluetooth';
  static const String methodIsLocationServiceEnabled = 'isLocationServiceEnabled';
  static const String methodRequestEnableLocationService =
      'requestEnableLocationService';
  static const String methodIsWifiEnabled = 'isWifiEnabled';
  static const String methodRequestEnableWifi = 'requestEnableWifi';
  static const String methodUpdateUserProfile = 'updateUserProfile';
  static const String methodOpenFile = 'openFile';
  static const String methodSaveFileToDownloads = 'saveFileToDownloads';
  static const String methodCreateVideoThumbnail = 'createVideoThumbnail';
  static const String methodGetLocalNodeId = 'getLocalNodeId';

  // Event Types
  static const String eventPeerFound = 'peerFound';
  static const String eventPeerLost = 'peerLost';
  static const String eventPeerConnected = 'peerConnected';
  static const String eventPeerDisconnected = 'peerDisconnected';
  static const String eventPacketReceived = 'packetReceived';
  static const String eventConnectionStateChanged = 'connectionStateChanged';
}
