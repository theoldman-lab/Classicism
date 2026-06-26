import 'package:flutter/material.dart';

import '../../models/playlist.dart';

class PlaylistTile extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback? onTap;

  const PlaylistTile({
    super.key,
    required this.playlist,
    this.onTap,
  });

  String _formatCount(int count) {
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: playlist.coverImgUrl != null
            ? Image.network(
                playlist.coverImgUrl!,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _defaultIcon(theme),
              )
            : _defaultIcon(theme),
      ),
      title: Text(
        playlist.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge,
      ),
      subtitle: Text(
        [
          if (playlist.trackCount > 0) '${playlist.trackCount}首',
          if (playlist.playCount > 0) '播放${_formatCount(playlist.playCount)}',
          if (playlist.creatorName != null) 'by ${playlist.creatorName}',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
    );
  }

  Widget _defaultIcon(ThemeData theme) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.queue_music,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
