abstract class MeshConstants {
  static const int defaultTtl = 7;
  static const int maxHops = 10;
  static const int tcpPort = 8888;
  static const String serviceUuid = '0000fe55-0000-1000-8000-00805f9b34fb';

  static const String packetTypeData = 'DATA';
  static const String packetTypeRouteReq = 'ROUTE_REQ';
  static const String packetTypeRouteRep = 'ROUTE_REP';
  static const String packetTypeAck = 'ACK';
  static const String packetTypeHeartbeat = 'HEARTBEAT';
}
