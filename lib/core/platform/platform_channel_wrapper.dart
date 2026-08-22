import 'package:flutter/services.dart';
import '../constants/channel_constants.dart';

class PlatformChannelWrapper {
  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  PlatformChannelWrapper({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel = methodChannel ??
            const MethodChannel(ChannelConstants.methodChannelName),
        _eventChannel = eventChannel ??
            const EventChannel(ChannelConstants.eventChannelName);

  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    try {
      return await _methodChannel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (_) {
      rethrow;
    }
  }

  Stream<dynamic> get eventStream => _eventChannel.receiveBroadcastStream();
}
