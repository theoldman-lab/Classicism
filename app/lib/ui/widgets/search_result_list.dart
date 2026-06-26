import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song.dart';
import '../../state/providers.dart';
import '../widgets/song_tile.dart';
import '../widgets/playlist_tile.dart';

class SearchResultList extends ConsumerWidget {
  const SearchResultList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchState = ref.watch(searchProvider);

    if (searchState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (searchState.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 8),
            Text('搜索出错了', style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      );
    }

    if (searchState.query.isEmpty) {
      return Center(
        child: Text(
          '输入关键词搜索',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    if (searchState.songs.isEmpty && searchState.playlists.isEmpty) {
      return Center(
        child: Text(
          '没有找到相关内容',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: '歌曲${searchState.songs.isNotEmpty ? ' (${searchState.songs.length})' : ''}'),
              Tab(text: '歌单${searchState.playlists.isNotEmpty ? ' (${searchState.playlists.length})' : ''}'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildSongList(context, ref, searchState.songs),
                _buildPlaylistList(context, ref, searchState.playlists),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongList(
      BuildContext context, WidgetRef ref, List<Song> songs) {
    if (songs.isEmpty) {
      return Center(
        child: Text('暂无歌曲结果',
            style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    return ListView.builder(
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        return SongTile(
          song: song,
          onTap: () {
            ref.read(playerProvider.notifier).playSongs(
                  songs,
                  startIndex: index,
                );
          },
        );
      },
    );
  }

  Widget _buildPlaylistList(
      BuildContext context, WidgetRef ref, List playlists) {
    if (playlists.isEmpty) {
      return Center(
        child: Text('暂无歌单结果',
            style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    return ListView.builder(
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return PlaylistTile(
          playlist: playlist,
          onTap: () {
            Navigator.pushNamed(
              context,
              '/playlist',
              arguments: playlist.id,
            );
          },
        );
      },
    );
  }
}
