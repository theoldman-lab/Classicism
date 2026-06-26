class Song {
  final int id;
  final String name;
  final String? artistName;
  final String? albumName;
  final String? coverUrl;
  final int duration;
  final int fee;

  const Song({
    required this.id,
    required this.name,
    this.artistName,
    this.albumName,
    this.coverUrl,
    required this.duration,
    this.fee = 0,
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    final ar = json['ar'] as List<dynamic>?;
    final al = json['al'] as Map<String, dynamic>?;
    return Song(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      artistName: ar != null && ar.isNotEmpty ? (ar.first as Map<String, dynamic>)['name'] as String? : null,
      albumName: al?['name'] as String?,
      coverUrl: al?['picUrl'] as String?,
      duration: json['dt'] as int? ?? 0,
      fee: json['fee'] as int? ?? 0,
    );
  }
}
