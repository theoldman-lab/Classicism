import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/playlist.dart';
import '../../state/providers.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_tile.dart';

class PlaylistPage extends ConsumerStatefulWidget {
  const PlaylistPage({super.key});

  @override
  ConsumerState<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends ConsumerState<PlaylistPage> {
  Playlist? _playlist;
  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fetchPlaylist();
  }

  Future<void> _fetchPlaylist() async {
    final id = ModalRoute.of(context)?.settings.arguments;
    if (id is! int || id <= 0) {
      setState(() {
        _error = '无效的歌单ID';
        _loading = false;
      });
      return;
    }

    try {
      final musicApi = ref.read(musicApiProvider);
      setState(() {
        _loading = true;
        _error = null;
      });

      final playlist = await musicApi.getPlaylistDetail(id);
      if (!mounted) return;

      setState(() {
        _playlist = playlist;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _playAll() {
    final tracks = _playlist?.tracks;
    if (tracks != null && tracks.isNotEmpty) {
      ref.read(playerProvider.notifier).playSongs(tracks);
    }
  }

  String _formatCount(int count) {
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: _buildBody(theme),
      bottomNavigationBar: const MiniPlayer(),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('歌单')),
        body: Center(child: Text(_error!, style: theme.textTheme.bodyLarge)),
      );
    }

    final playlist = _playlist;
    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('歌单')),
        body: Center(
          child: Text('歌单不存在', style: theme.textTheme.bodyLarge),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 240,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            background: Stack(
              fit: StackFit.expand,
              children: [
                if (playlist.coverImgUrl != null)
                  Image.network(playlist.coverImgUrl!, fit: BoxFit.cover)
                else
                  Container(color: theme.colorScheme.surfaceContainerHighest),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        theme.colorScheme.surface.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (playlist.creatorName != null) ...[
                      Icon(Icons.person, size: 16, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(playlist.creatorName!, style: theme.textTheme.bodyMedium),
                      const SizedBox(width: 16),
                    ],
                    Icon(Icons.music_note, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text('${playlist.trackCount}首', style: theme.textTheme.bodyMedium),
                    const SizedBox(width: 16),
                    Icon(Icons.play_circle_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text('${_formatCount(playlist.playCount)}次播放', style: theme.textTheme.bodyMedium),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: (playlist.tracks?.isNotEmpty ?? false) ? _playAll : null,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('播放全部'),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (playlist.tracks != null && playlist.tracks!.isNotEmpty)
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final song = playlist.tracks![index];
                return SongTile(
                  song: song,
                  showCover: false,
                  onTap: () {
                    ref.read(playerProvider.notifier).playSongs(
                          playlist.tracks!,
                          startIndex: index,
                        );
                  },
                );
              },
              childCount: playlist.tracks!.length,
            ),
          )
        else
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text('暂无歌曲', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            ),
          ),
      ],
    );
  }
}
