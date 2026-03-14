import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class AudioLibrary {
  static final AudioLibrary _instance = AudioLibrary._internal();
  factory AudioLibrary() => _instance;
  AudioLibrary._internal();

  List<AudioTrack> _tracks = [];
  List<Playlist> _playlists = [];
  List<AudioTrack> _queue = [];
  int _currentIndex = 0;

  List<AudioTrack> get tracks => _tracks;
  List<Playlist> get playlists => _playlists;
  List<AudioTrack> get queue => _queue;
  int get currentIndex => _currentIndex;
  AudioTrack? get currentTrack => _queue.isNotEmpty && _currentIndex < _queue.length ? _queue[_currentIndex] : null;

  Future<void> loadLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Charger les pistes
    final tracksJson = prefs.getString('tracks');
    if (tracksJson != null) {
      final List<dynamic> decoded = jsonDecode(tracksJson);
      _tracks = decoded.map((t) => AudioTrack.fromJson(t)).toList();
    }

    // Charger les playlists
    final playlistsJson = prefs.getString('playlists');
    if (playlistsJson != null) {
      final List<dynamic> decoded = jsonDecode(playlistsJson);
      _playlists = decoded.map((p) => Playlist.fromJson(p)).toList();
    }

    // Charger la file d'attente
    final queueJson = prefs.getString('queue');
    if (queueJson != null) {
      final List<dynamic> decoded = jsonDecode(queueJson);
      _queue = decoded.map((t) => AudioTrack.fromJson(t)).toList();
    }

    _currentIndex = prefs.getInt('currentIndex') ?? 0;
  }

  Future<void> saveLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tracks', jsonEncode(_tracks.map((t) => t.toJson()).toList()));
    await prefs.setString('playlists', jsonEncode(_playlists.map((p) => p.toJson()).toList()));
    await prefs.setString('queue', jsonEncode(_queue.map((t) => t.toJson()).toList()));
    await prefs.setInt('currentIndex', _currentIndex);
  }

  void addTrack(AudioTrack track) {
    _tracks.add(track);
    saveLibrary();
  }

  void updateTrack(AudioTrack updatedTrack) {
    final index = _tracks.indexWhere((t) => t.id == updatedTrack.id);
    if (index != -1) {
      _tracks[index] = updatedTrack;
      saveLibrary();
    }
  }

  void createPlaylist(String name) {
    final playlist = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      trackIds: [],
      createdAt: DateTime.now(),
    );
    _playlists.add(playlist);
    saveLibrary();
  }

  void addToPlaylist(String playlistId, String trackId) {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId, orElse: () => throw Exception('Playlist not found'));
    if (!playlist.trackIds.contains(trackId)) {
      playlist.trackIds.add(trackId);
      saveLibrary();
    }
  }

  void removeFromPlaylist(String playlistId, String trackId) {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId, orElse: () => throw Exception('Playlist not found'));
    playlist.trackIds.remove(trackId);
    saveLibrary();
  }

  void deletePlaylist(String id) {
    _playlists.removeWhere((p) => p.id == id);
    saveLibrary();
  }

  void setQueue(List<AudioTrack> tracks, {int startIndex = 0}) {
    _queue = tracks;
    _currentIndex = startIndex;
    saveLibrary();
  }

  void addToQueue(AudioTrack track) {
    _queue.add(track);
    saveLibrary();
  }

  void removeFromQueue(int index) {
    _queue.removeAt(index);
    if (_currentIndex >= _queue.length) {
      _currentIndex = _queue.length - 1;
    }
    saveLibrary();
  }

  void clearQueue() {
    _queue.clear();
    _currentIndex = 0;
    saveLibrary();
  }

  bool hasNext() => _currentIndex < _queue.length - 1;
  bool hasPrevious() => _currentIndex > 0;

  AudioTrack? next() {
    if (hasNext()) {
      _currentIndex++;
      saveLibrary();
      return currentTrack;
    }
    return null;
  }

  AudioTrack? previous() {
    if (hasPrevious()) {
      _currentIndex--;
      saveLibrary();
      return currentTrack;
    }
    return null;
  }

  void jumpTo(int index) {
    if (index >= 0 && index < _queue.length) {
      _currentIndex = index;
      saveLibrary();
    }
  }

  List<AudioTrack> getPlaylistTracks(String playlistId) {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId, orElse: () => throw Exception('Playlist not found'));
    return playlist.trackIds
        .map((id) => _tracks.cast<AudioTrack?>().firstWhere((t) => t?.id == id, orElse: () => null))
        .whereType<AudioTrack>()
        .toList();
  }
}
