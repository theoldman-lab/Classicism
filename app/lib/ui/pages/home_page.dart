import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../widgets/mini_player.dart';
import '../widgets/search_bar.dart';
import '../widgets/song_tile.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authProvider.notifier).initialize().catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);
    final recommendAsync = ref.watch(recommendSongsProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(theme),
            const SizedBox(height: 8),
            _buildQuickActions(theme, authState.status),
            const SizedBox(height: 12),
            Expanded(child: _buildContent(theme, recommendAsync, authState.status)),
          ],
        ),
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ClassicismSearchBar(
        hintText: '搜索歌曲、歌单',
        onSearch: (query) {
          ref.read(searchProvider.notifier).search(query);
          Navigator.pushNamed(context, '/search');
        },
      ),
    );
  }

  Widget _buildQuickActions(ThemeData theme, AuthStatus status) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(child: _buildActionCard(theme, Icons.auto_awesome, '每日推荐', () {
            Navigator.pushNamed(context, '/search');
          })),
          const SizedBox(width: 8),
          Expanded(child: _buildActionCard(theme, Icons.queue_music, '歌单', () {
            ref.read(searchProvider.notifier).search('热门歌单');
            Navigator.pushNamed(context, '/search');
          })),
          const SizedBox(width: 8),
          Expanded(
            child: _buildActionCard(
              theme,
              status == AuthStatus.loggedIn ? Icons.person : Icons.login,
              status == AuthStatus.loggedIn ? '已登录' : '登录',
              () => Navigator.pushNamed(context, '/login'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(ThemeData theme, IconData icon, String label, VoidCallback onTap) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: theme.colorScheme.primary),
              const SizedBox(height: 6),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
      ThemeData theme, AsyncValue<List> recommendAsync, AuthStatus status) {
    if (status == AuthStatus.uninitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('推荐歌曲', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 4),
        Expanded(child: _buildRecommendList(theme, recommendAsync, status)),
      ],
    );
  }

  Widget _buildRecommendList(
      ThemeData theme, AsyncValue<List> recommendAsync, AuthStatus status) {
    if (status != AuthStatus.loggedIn) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('登录后获取每日推荐', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/login'),
              icon: const Icon(Icons.login),
              label: const Text('立即登录'),
            ),
          ],
        ),
      );
    }

    return recommendAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('加载失败: $e', style: theme.textTheme.bodyMedium),
      ),
      data: (songs) {
        if (songs.isEmpty) {
          return Center(
            child: Text('暂无推荐', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
                      songs.cast(),
                      startIndex: index,
                    );
              },
            );
          },
        );
      },
    );
  }
}
