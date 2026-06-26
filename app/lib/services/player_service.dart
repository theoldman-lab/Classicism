import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../api/music_api.dart';
import '../models/song.dart';

enum PlayMode { sequential, shuffle, singleRepeat }

class PlayerService {
  final MusicApi _api;
  final AudioPlayer _player;

  List<Song> _playlist = [];
  PlayMode _playMode = PlayMode.sequential;

  final _currentSongController = StreamController<Song?>.broadcast();

  StreamSubscription? _indexSub;

  PlayerService({required MusicApi api})
      : _api = api,
        _player = AudioPlayer() {
    _indexSub = _player.currentIndexStream.listen((_) {
      _currentSongController.add(currentSong);
    });
  }

  // ============================================================
  // Streams
  // ============================================================

  Stream<Duration> get positionStream => _player.positionStream;

  Stream<Duration?> get durationStream => _player.durationStream;

  Stream<bool> get playingStream => _player.playingStream;

  Stream<Song?> get currentSongStream => _currentSongController.stream;

  // ============================================================
  // Getters
  // ============================================================

  Song? get currentSong {
    final seq = _player.sequence;
    final idx = _player.currentIndex;
    if (seq == null || idx == null || idx < 0 || idx >= seq.length) {
      return null;
    }
    return seq[idx].tag as Song?;
  }

  List<Song> get playlist => List.unmodifiable(_playlist);

  int get currentIndex => _player.currentIndex ?? -1;

  PlayMode get playMode => _playMode;

  bool get isPlaying => _player.playing;

  // ============================================================
  // Playback Controls
  // ============================================================

  Future<void> playSong(Song song) async {
    await playSongs([song]);
  }

  Future<void> playSongs(List<Song> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) return;

    _playlist = List.from(songs);

    final ids = songs.map((s) => s.id).toList();
    final urls = await _api.getSongUrls(ids);

    final sources = <AudioSource>[];
    int adjustedStartIndex = 0;
    int count = 0;

    for (int i = 0; i < songs.length; i++) {
      final song = songs[i];
      final urlEntry = urls.cast<Map<String, dynamic>?>().firstWhere(
            (u) => u != null && u['id'] == song.id,
            orElse: () => null,
          );

      final url = urlEntry?['url'] as String?;
      if (url != null && url.isNotEmpty) {
        sources.add(AudioSource.uri(Uri.parse(url), tag: song));
        if (i == startIndex) {
          adjustedStartIndex = count;
        }
        count++;
      }
    }

    if (sources.isEmpty) return;

    await _player.setAudioSource(
      ConcatenatingAudioSource(children: sources),
      initialIndex: adjustedStartIndex,
    );

    _updatePlayMode();
    await _player.play();
    _currentSongController.add(currentSong);
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> next() async {
    await _player.seekToNext();
  }

  Future<void> previous() async {
    await _player.seekToPrevious();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  void setPlayMode(PlayMode mode) {
    _playMode = mode;
    _updatePlayMode();
  }

  void _updatePlayMode() {
    switch (_playMode) {
      case PlayMode.sequential:
        _player.setLoopMode(LoopMode.off);
        _player.setShuffleModeEnabled(false);
      case PlayMode.shuffle:
        _player.setLoopMode(LoopMode.off);
        _player.setShuffleModeEnabled(true);
      case PlayMode.singleRepeat:
        _player.setLoopMode(LoopMode.one);
        _player.setShuffleModeEnabled(false);
    }
  }

  void dispose() {
    _indexSub?.cancel();
    _currentSongController.close();
    _player.dispose();
  }
}
