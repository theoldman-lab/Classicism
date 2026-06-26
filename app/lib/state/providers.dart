import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/auth_api.dart';
import '../api/music_api.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../services/auth_service.dart';
import '../services/player_service.dart';

// ============================================================
// Service Providers
// ============================================================

final musicApiProvider = Provider<MusicApi>((ref) {
  throw UnimplementedError('Override in main.dart');
});

final authServiceProvider = Provider<AuthService>((ref) {
  throw UnimplementedError('Override in main.dart');
});

final playerServiceProvider = Provider<PlayerService>((ref) {
  throw UnimplementedError('Override in main.dart');
});

// ============================================================
// Auth State
// ============================================================

enum AuthStatus { uninitialized, guest, loggedIn }

class AuthState {
  final AuthStatus status;
  final String? unikey;

  const AuthState({this.status = AuthStatus.uninitialized, this.unikey});

  AuthState copyWith({AuthStatus? status, String? unikey}) {
    return AuthState(
      status: status ?? this.status,
      unikey: unikey,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;

  AuthNotifier(this._authService)
      : super(const AuthState(status: AuthStatus.uninitialized));

  Future<void> initialize() async {
    await _authService.initialize();
    state = state.copyWith(status: AuthStatus.guest);
  }

  Future<LoginResult> loginWithPassword(String phone, String password) async {
    final result = await _authService.loginWithPassword(phone, password);
    if (result.isSuccess) {
      state = state.copyWith(status: AuthStatus.loggedIn);
    }
    return result;
  }

  Future<void> logout() async {
    await _authService.logout();
    state = state.copyWith(status: AuthStatus.guest);
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authServiceProvider));
});

// ============================================================
// Player State
// ============================================================

class PlayerState {
  final Song? currentSong;
  final List<Song> playlist;
  final int currentIndex;
  final PlayMode playMode;
  final bool isPlaying;
  final Duration position;
  final Duration duration;

  const PlayerState({
    this.currentSong,
    this.playlist = const [],
    this.currentIndex = -1,
    this.playMode = PlayMode.sequential,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  PlayerState copyWith({
    Song? currentSong,
    List<Song>? playlist,
    int? currentIndex,
    PlayMode? playMode,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
  }) {
    return PlayerState(
      currentSong: currentSong ?? this.currentSong,
      playlist: playlist ?? this.playlist,
      currentIndex: currentIndex ?? this.currentIndex,
      playMode: playMode ?? this.playMode,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
    );
  }
}

class PlayerNotifier extends StateNotifier<PlayerState> {
  final PlayerService _playerService;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _songSub;
  StreamSubscription? _playingSub;

  PlayerNotifier(this._playerService) : super(const PlayerState()) {
    _posSub = _playerService.positionStream.listen((pos) {
      if (mounted) state = state.copyWith(position: pos);
    });
    _durSub = _playerService.durationStream.listen((dur) {
      if (mounted) state = state.copyWith(duration: dur ?? Duration.zero);
    });
    _songSub = _playerService.currentSongStream.listen((song) {
      if (mounted) {
        state = state.copyWith(
          currentSong: song,
          playlist: _playerService.playlist,
          currentIndex: _playerService.currentIndex,
        );
      }
    });
    _playingSub = _playerService.playingStream.listen((playing) {
      if (mounted) state = state.copyWith(isPlaying: playing);
    });
  }

  Future<void> playSong(Song song) => _playerService.playSong(song);

  Future<void> playSongs(List<Song> songs, {int startIndex = 0}) =>
      _playerService.playSongs(songs, startIndex: startIndex);

  Future<void> togglePlayPause() => _playerService.togglePlayPause();

  Future<void> next() => _playerService.next();

  Future<void> previous() => _playerService.previous();

  Future<void> seek(Duration position) => _playerService.seek(position);

  void setPlayMode(PlayMode mode) {
    _playerService.setPlayMode(mode);
    if (mounted) state = state.copyWith(playMode: mode);
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _songSub?.cancel();
    _playingSub?.cancel();
    super.dispose();
  }
}

final playerProvider =
    StateNotifierProvider<PlayerNotifier, PlayerState>((ref) {
  return PlayerNotifier(ref.watch(playerServiceProvider));
});

// ============================================================
// Search State
// ============================================================

class SearchState {
  final String query;
  final List<Song> songs;
  final List<Playlist> playlists;
  final bool isLoading;
  final String? error;

  const SearchState({
    this.query = '',
    this.songs = const [],
    this.playlists = const [],
    this.isLoading = false,
    this.error,
  });

  SearchState copyWith({
    String? query,
    List<Song>? songs,
    List<Playlist>? playlists,
    bool? isLoading,
    String? error,
  }) {
    return SearchState(
      query: query ?? this.query,
      songs: songs ?? this.songs,
      playlists: playlists ?? this.playlists,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class SearchNotifier extends StateNotifier<SearchState> {
  final MusicApi _musicApi;

  SearchNotifier(this._musicApi) : super(const SearchState());

  Future<void> search(String query) async {
    if (query.trim().isEmpty) return;
    state = state.copyWith(query: query, isLoading: true, error: null);

    try {
      final results = await Future.wait([
        _musicApi.searchSongs(query),
        _musicApi.searchPlaylists(query),
      ]);

      if (mounted) {
        state = state.copyWith(
          songs: results[0] as List<Song>,
          playlists: results[1] as List<Playlist>,
          isLoading: false,
        );
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(isLoading: false, error: e.toString());
      }
    }
  }

  void clear() {
    state = const SearchState();
  }
}

final searchProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier(ref.watch(musicApiProvider));
});

// ============================================================
// Home / Recommendations (FutureProvider)
// ============================================================

final recommendSongsProvider = FutureProvider<List<Song>>((ref) async {
  final musicApi = ref.watch(musicApiProvider);
  return musicApi.getRecommendSongs();
});
