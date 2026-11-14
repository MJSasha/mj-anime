import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:animetka_tv/api.dart';
import 'package:animetka_tv/cast.dart';
import 'package:animetka_tv/player.dart';

void main() {
  testWidgets(
    'Repeated Cast end events pop only the player, preserving the root',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final session = Session(await SharedPreferences.getInstance(), Api());
      final cast = CastTransport(session)..chatId = 'test-chat';
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                      session: session,
                      anime: {'id': 228, 'title': 'Test'},
                      playlist: {'list': []},
                      index: 0,
                      cast: cast,
                    ),
                  ),
                ),
                child: const Text('Root'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Root'));
      await tester.pumpAndSettle();
      cast.events.add({'type': 'watch:end', 'chat_id': 'test-chat'});
      cast.events.add({'type': 'watch:end', 'chat_id': 'test-chat'});
      await tester.pumpAndSettle();
      expect(find.text('Root'), findsOneWidget);
      expect(tester.takeException(), isNull);
      cast.dispose();
    },
  );
}
