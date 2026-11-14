import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:animetka_tv/api.dart';
import 'package:animetka_tv/cast.dart';

class FakeSocket extends Stream<dynamic> implements WebSocket {
  final incoming = StreamController<dynamic>();
  final sent = <Json>[];
  @override
  void add(dynamic data) => sent.add(object(jsonDecode(data as String)));
  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => incoming.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  Future<void> close([int? code, String? reason]) => incoming.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Device hello waits for server ready', () async {
    SharedPreferences.setMockInitialValues({
      'token': 'local-fake-token',
      'device_id': 'local-fake-device',
    });
    final session = Session(await SharedPreferences.getInstance(), Api());
    final socket = FakeSocket();
    final cast = CastTransport(session, connector: () => Future.value(socket));
    await cast.connect();
    expect(socket.sent.map((m) => m['type']), ['auth']);
    socket.incoming.add(jsonEncode({'type': 'ready', 'user_id': 1}));
    await Future<void>.delayed(Duration.zero);
    expect(socket.sent.map((m) => m['type']), ['auth', 'device:hello']);
    cast.dispose();
  });
  test('Heartbeat is rate limited and only emitted by master', () async {
    SharedPreferences.setMockInitialValues({
      'token': 'local-fake-token',
      'device_id': 'local-fake-device',
    });
    final session = Session(await SharedPreferences.getInstance(), Api());
    final socket = FakeSocket();
    final cast = CastTransport(session, connector: () => Future.value(socket));
    await cast.connect();
    socket.incoming.add(jsonEncode({'type': 'ready', 'user_id': 1}));
    await Future<void>.delayed(Duration.zero);
    cast.chatId = 'test-chat';
    cast.roomId = 1;
    cast.invited = true;
    cast.lastState = {'anime_id': '228'};
    cast.position(10, false, 1);
    expect(socket.sent.where((e) => e['type'] == 'watch:position'), isEmpty);
    cast.masterDeviceId = session.deviceId;
    cast.position(10, false, 1);
    cast.position(11, false, 1);
    expect(socket.sent.where((e) => e['type'] == 'watch:position').length, 1);
    cast.dispose();
  });
  test(
    'Uninvited watch messages and another device invitation have no effect',
    () async {
      SharedPreferences.setMockInitialValues({
        'token': 'local-fake-token',
        'device_id': 'our-device',
      });
      final session = Session(await SharedPreferences.getInstance(), Api());
      final socket = FakeSocket();
      final cast = CastTransport(
        session,
        connector: () => Future.value(socket),
      );
      await cast.connect();
      socket.incoming.add(jsonEncode({'type': 'ready'}));
      await Future<void>.delayed(Duration.zero);
      cast.handle({
        'type': 'watch:start',
        'anime_id': '228',
        'chat_id': 'unrelated',
      });
      expect(cast.lastState, isEmpty);
      cast.handle({
        'type': 'cast:invite',
        'target_device_id': 'another-device',
        'room_id': 3,
        'chat_id': 'unrelated',
      });
      expect(cast.invited, isFalse);
      expect(cast.roomId, isNull);
      cast.chatId = 'unrelated';
      cast.masterDeviceId = 'our-device';
      cast.position(100, false, 1);
      expect(socket.sent.where((e) => e['type'] == 'watch:position'), isEmpty);
      cast.dispose();
    },
  );
}
