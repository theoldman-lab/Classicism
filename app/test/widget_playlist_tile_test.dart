import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:classicism/models/playlist.dart';
import 'package:classicism/ui/widgets/playlist_tile.dart';

import 'test_helpers.dart';

void main() {
  group('PlaylistTile', () {
    testWidgets('renders playlist name', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlaylistTile(playlist: testPlaylist))));
      expect(find.text('Test Playlist'), findsOneWidget);
    });

    testWidgets('renders track count', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlaylistTile(playlist: testPlaylist))));
      expect(find.textContaining('42首'), findsOneWidget);
    });

    testWidgets('renders play count formatted', (tester) async {
      final pl = Playlist(id: 1, name: 'PL', playCount: 15000);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlaylistTile(playlist: pl))));
      expect(find.textContaining('1.5万'), findsOneWidget);
    });

    testWidgets('renders creator name', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlaylistTile(playlist: testPlaylist))));
      expect(find.textContaining('Test Creator'), findsOneWidget);
    });

    testWidgets('renders cover image when URL present', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlaylistTile(playlist: testPlaylist))));
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('renders default icon when no cover', (tester) async {
      final pl = Playlist(id: 1, name: 'No Cover', coverImgUrl: null);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlaylistTile(playlist: pl))));
      expect(find.byIcon(Icons.queue_music), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PlaylistTile(playlist: testPlaylist, onTap: () => tapped = true)),
      ));
      await tester.tap(find.byType(ListTile));
      expect(tapped, isTrue);
    });

    testWidgets('hides creator when null', (tester) async {
      final pl = Playlist(id: 1, name: 'No Creator', creatorName: null);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlaylistTile(playlist: pl))));
      expect(find.text('No Creator'), findsOneWidget);
      // Should not show "by" prefix
      expect(find.textContaining('by'), findsNothing);
    });

    testWidgets('handles zero track count gracefully', (tester) async {
      final pl = Playlist(id: 1, name: 'Zero', trackCount: 0, playCount: 0);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlaylistTile(playlist: pl))));
      expect(find.text('Zero'), findsOneWidget);
    });
  });
}
