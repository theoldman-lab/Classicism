import 'package:flutter/material.dart';

class LyricView extends StatelessWidget {
  final String lrcText;
  final Duration position;
  final Duration duration;

  const LyricView({
    super.key,
    required this.lrcText,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  static List<(Duration, String)> parse(String lrc) {
    final lines = <(Duration, String)>[];
    final regex = RegExp(r'\[(\d{2}):(\d{2})[.:](\d{1,3})\]');

    for (final line in lrc.split('\n')) {
      final matches = regex.allMatches(line).toList();
      if (matches.isEmpty) continue;

      final text = line.substring(matches.last.end).trim();
      if (text.isEmpty) continue;

      for (final match in matches) {
        final min = int.parse(match.group(1)!);
        final sec = int.parse(match.group(2)!);
        final msStr = match.group(3)!;
        final ms = int.parse(msStr);
        final actualMs = msStr.length == 3 ? ms : ms * 10;

        final time = Duration(
          minutes: min,
          seconds: sec,
          milliseconds: actualMs,
        );
        lines.add((time, text));
      }
    }

    lines.sort((a, b) => a.$1.compareTo(b.$1));
    return lines;
  }

  int _findCurrentLineIndex(List<(Duration, String)> lines) {
    if (lines.isEmpty) return -1;
    for (int i = lines.length - 1; i >= 0; i--) {
      if (position >= lines[i].$1) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = parse(lrcText);

    if (lines.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final currentIndex = _findCurrentLineIndex(lines);

    return ListView.builder(
      itemCount: lines.length,
      padding: EdgeInsets.symmetric(
        vertical: MediaQuery.of(context).size.height * 0.25,
      ),
      itemBuilder: (context, index) {
        final isCurrent = index == currentIndex;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(
            lines[index].$2,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: isCurrent
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              fontSize: isCurrent ? 18 : 15,
            ),
          ),
        );
      },
    );
  }
}
