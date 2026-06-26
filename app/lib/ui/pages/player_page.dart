import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/lyric.dart';
import '../../models/song.dart';
import '../../services/player_service.dart';
import '../../state/providers.dart';
import '../widgets/lyric_view.dart';

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  Lyric? _lyric;
  int _lastSongId = -1;

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final song = playerState.currentSong;

    if (song != null && song.id != _lastSongId) {
      _lastSongId = song.id;
      _fetchLyric(song);
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackground(context, song),
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(context, song),
                const Spacer(),
                _buildAlbumArt(context, song),
                const Spacer(),
                _buildSongInfo(context, song, playerState),
                const SizedBox(height: 16),
                _buildProgressBar(context, playerState),
                const SizedBox(height: 8),
                _buildControls(context, playerState),
                const SizedBox(height: 16),
                Expanded(
                  flex: 2,
                  child: _buildLyric(context, playerState),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground(BuildContext context, Song? song) {
    if (song?.coverUrl == null) {
      return Container(color: Theme.of(context).colorScheme.surface);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          song!.coverUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              Container(color: Theme.of(context).colorScheme.surface),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppBar(BuildContext context, Song? song) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          if (song != null)
            Text(
              song.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildAlbumArt(BuildContext context, Song? song) {
    return Container(
      width: 280,
      height: 280,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: song?.coverUrl != null
            ? Image.network(song!.coverUrl!, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _defaultArt(context))
            : _defaultArt(context),
      ),
    );
  }

  Widget _defaultArt(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.music_note,
          size: 80, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }

  Widget _buildSongInfo(
      BuildContext context, Song? song, PlayerState playerState) {
    final theme = Theme.of(context);

    if (song == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          children: [
            Text('未在播放', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('选择一首歌曲开始播放',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            song.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            song.artistName ?? '未知歌手',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context, PlayerState playerState) {
    final theme = Theme.of(context);
    final position = playerState.position;
    final duration = playerState.duration;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: theme.colorScheme.primary,
              inactiveTrackColor: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              thumbColor: theme.colorScheme.primary,
            ),
            child: Slider(
              value: duration.inMilliseconds > 0
                  ? position.inMilliseconds.clamp(0, duration.inMilliseconds)
                      .toDouble()
                  : 0,
              max: duration.inMilliseconds > 0
                  ? duration.inMilliseconds.toDouble()
                  : 1,
              onChanged: (value) {
                ref
                    .read(playerProvider.notifier)
                    .seek(Duration(milliseconds: value.toInt()));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(position), style: theme.textTheme.bodySmall),
                Text(_formatDuration(duration), style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context, PlayerState playerState) {
    final playMode = playerState.playMode;

    IconData modeIcon;
    switch (playMode) {
      case PlayMode.shuffle:
        modeIcon = Icons.shuffle_rounded;
      case PlayMode.singleRepeat:
        modeIcon = Icons.repeat_one_rounded;
      case PlayMode.sequential:
        modeIcon = Icons.repeat_rounded;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: Icon(modeIcon),
            iconSize: 28,
            color: playMode != PlayMode.sequential
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
            onPressed: () {
              final nextMode = PlayMode.values[
                  (playMode.index + 1) % PlayMode.values.length];
              ref.read(playerProvider.notifier).setPlayMode(nextMode);
            },
          ),
          IconButton(
            icon: const Icon(Icons.skip_previous_rounded),
            iconSize: 44,
            onPressed: () => ref.read(playerProvider.notifier).previous(),
          ),
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primary,
            ),
            child: IconButton(
              icon: Icon(
                playerState.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 40,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
              onPressed: () =>
                  ref.read(playerProvider.notifier).togglePlayPause(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.skip_next_rounded),
            iconSize: 44,
            onPressed: () => ref.read(playerProvider.notifier).next(),
          ),
          IconButton(
            icon: const Icon(Icons.lyrics_rounded),
            iconSize: 28,
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildLyric(BuildContext context, PlayerState playerState) {
    if (_lyric == null) {
      return Center(
        child: Text('加载歌词中...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }

    return LyricView(
      lrcText: _lyric!.lrc,
      position: playerState.position,
      duration: playerState.duration,
    );
  }

  Future<void> _fetchLyric(Song song) async {
    try {
      final musicApi = ref.read(musicApiProvider);
      final lyric = await musicApi.getLyric(song.id);
      if (mounted) {
        setState(() => _lyric = lyric);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _lyric = null);
      }
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
