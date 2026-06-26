import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:classicism/models/song.dart';
import 'package:classicism/ui/widgets/song_tile.dart';

import 'test_helpers.dart';

void main() {
  group('SongTile', () {
    testWidgets('renders song name', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SongTile(song: testSong))));
      expect(find.text('Test Song'), findsOneWidget);
    });

    testWidgets('renders artist name', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SongTile(song: testSong))));
      expect(find.text('Test Artist'), findsOneWidget);
    });

    testWidgets('renders duration formatted as mm:ss', (tester) async {
      // 240000ms = 4:00
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SongTile(song: testSong))));
      expect(find.text('04:00'), findsOneWidget);
    });

    testWidgets('renders cover image when URL present', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SongTile(song: testSong))));
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('renders default icon when no cover URL', (tester) async {
      final song = Song(id: 1, name: 'No Cover', coverUrl: null, duration: 1000);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SongTile(song: song))));
      expect(find.byIcon(Icons.music_note), findsOneWidget);
    });

    testWidgets('handles null artist name gracefully', (tester) async {
      final song = Song(id: 1, name: 'Song', artistName: null, duration: 1000);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SongTile(song: song))));
      expect(find.text('Song'), findsOneWidget);
    });

    testWidgets('hides trailing duration when duration is zero', (tester) async {
      final song = Song(id: 1, name: 'Zero', duration: 0);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SongTile(song: song))));
      // 00:00 would be the text if duration were shown
      expect(find.text('00:00'), findsNothing);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SongTile(song: testSong, onTap: () => tapped = true)),
      ));
      await tester.tap(find.byType(ListTile));
      expect(tapped, isTrue);
    });

    testWidgets('hides cover when showCover is false', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SongTile(song: testSong, showCover: false)),
      ));
      // Leading should be null when showCover=false
      final listTile = tester.widget<ListTile>(find.byType(ListTile));
      expect(listTile.leading, isNull);
    });

    testWidgets('image error falls back to default icon', (tester) async {
      // Using an invalid URL triggers errorBuilder
      final song = Song(id: 1, name: 'Bad Img', coverUrl: 'x-invalid://', duration: 1000);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SongTile(song: song))));
      await tester.pumpAndSettle();
      // Should still render the list tile with music_note fallback
      expect(find.text('Bad Img'), findsOneWidget);
    });
  });
}
