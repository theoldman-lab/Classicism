class Lyric {
  final String lrc;
  final String? tlyric;

  const Lyric({required this.lrc, this.tlyric});

  factory Lyric.fromJson(Map<String, dynamic> json) {
    final lrcObj = json['lrc'] as Map<String, dynamic>?;
    final tlyricObj = json['tlyric'] as Map<String, dynamic>?;
    return Lyric(
      lrc: lrcObj?['lyric'] as String? ?? '',
      tlyric: tlyricObj?['lyric'] as String?,
    );
  }
}
