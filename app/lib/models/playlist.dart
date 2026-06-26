import 'song.dart';

class Playlist {
  final int id;
  final String name;
  final String? coverImgUrl;
  final int trackCount;
  final int playCount;
  final String? creatorName;
  final List<Song>? tracks;

  const Playlist({
    required this.id,
    required this.name,
    this.coverImgUrl,
    this.trackCount = 0,
    this.playCount = 0,
    this.creatorName,
    this.tracks,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final creator = json['creator'] as Map<String, dynamic>?;
    final tracksJson = json['tracks'] as List<dynamic>?;
    return Playlist(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      coverImgUrl: json['coverImgUrl'] as String?,
      trackCount: json['trackCount'] as int? ?? 0,
      playCount: json['playCount'] as int? ?? 0,
      creatorName: creator?['nickname'] as String?,
      tracks: tracksJson
          ?.map((t) => Song.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }
}
