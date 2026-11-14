import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api.dart';

class CastTransport {
  final Session session;
  final events = StreamController<Json>.broadcast();
  WebSocket? socket;
  Timer? retry;
  bool disposed = false, connecting = false, authenticated = false;
  int attempt = 0;
  DateTime lastPosition = DateTime.fromMillisecondsSinceEpoch(0);
  int? roomId, activeAnimeId;
  bool invited = false;
  String? chatId, masterDeviceId;
  Json lastState = {};
  final Future<WebSocket> Function() connector;
  CastTransport(this.session, {Future<WebSocket> Function()? connector})
    : connector = connector ?? openSocket;
  static Future<WebSocket> openSocket() => WebSocket.connect(
    'wss://animetka.com/api/voice/ws',
    headers: {'User-Agent': 'Dart/3.14 (dart:io)'},
  );
  Future<void> connect() async {
    if (disposed || connecting || socket != null || !session.loggedIn) return;
    connecting = true;
    try {
      final ws = await connector().timeout(const Duration(seconds: 20));
      if (disposed) {
        await ws.close();
        return;
      }
      socket = ws;
      attempt = 0;
      send({'type': 'auth', 'token': session.api.token});

      ws.listen(
        (raw) {
          if (disposed) return;
          try {
            final e = object(jsonDecode('$raw'));
            handle(e);
            events.add(e);
          } catch (_) {
            events.add({
              'type': 'client:error',
              'message': 'Неизвестное сообщение управления',
            });
          }
        },
        onDone: lost,
        onError: (_) => lost(),
        cancelOnError: true,
      );
    } catch (_) {
      lost();
    } finally {
      connecting = false;
    }
  }

  void hello() => send({
    'type': 'device:hello',
    'device_id': session.deviceId,
    'platform': 'tv',
    'device_label': 'MJAnime',
  });
  void send(Json data) {
    if (socket != null && (authenticated || data['type'] == 'auth')) {
      socket!.add(jsonEncode(data));
    }
  }

  void handle(Json event) {
    final type = event['type'];
    if (type == 'ready' || type == 'auth:ok' || type == 'auth_ok') {
      authenticated = true;
      hello();
      if (roomId != null) join(roomId!, chat: chatId);
    }
    if (type == 'room:master' || type == 'room:presence') {
      masterDeviceId = event['master_device_id']?.toString();
    }
    if (type == 'cast:invite') {
      final target = event['target_device_id']?.toString();
      if (target != null && target != session.deviceId) return;
      invited = true;
      roomId = number(event['room_id']);
      chatId = event['chat_id']?.toString();
    }
    if (invited &&
        ['watch:start', 'watch:state', 'watch:snapshot'].contains(type)) {
      lastState = {...lastState, ...object(event['state']), ...event};
      chatId = lastState['chat_id']?.toString() ?? chatId;
    }
    if (type == 'watch:end' || type == 'room:closed') {
      lastState = {};
      invited = false;
      roomId = null;
      masterDeviceId = null;
    }
  }

  void join(int room, {String? chat}) {
    roomId = room;
    chatId = chat ?? chatId;
    send({
      'type': 'room:join',
      'room_id': room,
      'device_id': session.deviceId,
      'platform': 'tv',
      'device_label': 'MJAnime',
    });
    if (chatId != null) send({'type': 'subscribe', 'chat_id': chatId});
  }

  void ready() {
    final uid = number(session.user['id']);
    if (invited && roomId != null && lastState.isNotEmpty && chatId != null) {
      send({
        'type': 'watch:accept',
        'chat_id': chatId,
        'accepted_user_ids': [uid],
      });
      send({
        'type': 'watch:ready',
        'chat_id': chatId,
        'ready_user_ids': [uid],
        'accepted_user_ids': [uid],
      });
      send({'type': 'watch:sync_request', 'chat_id': chatId});
    }
  }

  void position(double seconds, bool paused, double rate) {
    if (!invited ||
        lastState.isEmpty ||
        roomId == null ||
        chatId == null ||
        masterDeviceId != session.deviceId ||
        DateTime.now().difference(lastPosition).inMilliseconds < 800) {
      return;
    }
    lastPosition = DateTime.now();
    send({
      'type': 'watch:position',
      'chat_id': chatId,
      'position_seconds': seconds,
      'paused': paused,
      'playback_rate': rate,
      'phase': 'playing',
    });
  }

  void release() {
    if (roomId != null) {
      send({
        'type': 'cast:release',
        'room_id': roomId,
        if (chatId != null) 'chat_id': chatId,
      });
      send({'type': 'room:leave', 'room_id': roomId});
    }
    invited = false;
    masterDeviceId = null;
    roomId = null;
    chatId = null;
    lastState = {};
  }

  void lost() {
    socket = null;
    authenticated = false;
    if (disposed) return;
    retry?.cancel();
    attempt = (attempt + 1).clamp(1, 5);
    retry = Timer(Duration(seconds: 1 << (attempt - 1)), connect);
  }

  void dispose() {
    disposed = true;
    retry?.cancel();
    socket?.close();
    events.close();
  }
}
