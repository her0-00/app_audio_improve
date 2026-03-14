class AudioTrack {
  final String id;
  final String path;
  final String title;
  final String artist;
  final String album;
  final double duration;
  final String? artwork;

  AudioTrack({
    required this.id,
    required this.path,
    required this.title,
    this.artist = 'Artiste inconnu',
    this.album = 'Album inconnu',
    required this.duration,
    this.artwork,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'title': title,
    'artist': artist,
    'album': album,
    'duration': duration,
    'artwork': artwork,
  };

  factory AudioTrack.fromJson(Map<String, dynamic> json) => AudioTrack(
    id: json['id'],
    path: json['path'],
    title: json['title'],
    artist: json['artist'],
    album: json['album'],
    duration: json['duration'],
    artwork: json['artwork'],
  );

  AudioTrack copyWith({
    String? id,
    String? path,
    String? title,
    String? artist,
    String? album,
    double? duration,
    String? artwork,
  }) {
    return AudioTrack(
      id: id ?? this.id,
      path: path ?? this.path,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      artwork: artwork ?? this.artwork,
    );
  }
}

class Playlist {
  final String id;
  final String name;
  final List<String> trackIds;
  final DateTime createdAt;

  Playlist({
    required this.id,
    required this.name,
    required this.trackIds,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'trackIds': trackIds,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
    id: json['id'],
    name: json['name'],
    trackIds: List<String>.from(json['trackIds']),
    createdAt: DateTime.parse(json['createdAt']),
  );
}
