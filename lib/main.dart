import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'audio_library.dart';
import 'models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CinemaAudioLuxeApp());
}

// ─── Modèle piste ────────────────────────────────────────────────────────────
// Using AudioTrack from models.dart

// ─── État global partagé ─────────────────────────────────────────────────────
class AudioState extends ChangeNotifier {
  static const _ch = MethodChannel('cinema.audio.luxe/audio');
  final AudioLibrary _library = AudioLibrary();

  List<AudioTrack> get queue => _library.queue;
  int get currentIndex => _library.currentIndex;
  AudioTrack? get current => _library.currentTrack;
  bool isPlaying = false;
  double position = 0;
  double get duration => current != null ? current!.duration : 1;
  Timer? _posTimer;

  // New: presets, shuffle, repeat, device
  String currentPreset = "cinema";
  bool shuffleEnabled = false;
  int repeatMode = 0; // 0=off, 1=all, 2=one
  String currentDevice = "speaker";
  List<double> spectrumData = List.filled(32, 0.0); // For visualizer

  AudioState() {
    _ch.setMethodCallHandler(_onNativeCall);
    _library.loadLibrary(); // Load saved library
    _startSpectrumTimer();
  }

  void _startSpectrumTimer() {
    Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (isPlaying) {
        // Simulate spectrum data
        spectrumData = List.generate(32, (_) => (0.1 + 0.9 * (DateTime.now().millisecondsSinceEpoch % 1000) / 1000.0) * (0.3 + 0.7 * (DateTime.now().microsecondsSinceEpoch % 1000000) / 1000000.0));
        notifyListeners();
      }
    });
  }

  Future<void> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onTrackChanged':
        // currentIndex updated via library
        position = 0;
        isPlaying = true;
        notifyListeners();
        break;
      case 'onTrackFinished':
        isPlaying = false;
        position = 0;
        // Handle repeat/shuffle
        if (repeatMode == 2) { // repeat one
          playIndex(currentIndex);
        } else if (repeatMode == 1 || (repeatMode == 0 && _library.hasNext())) { // repeat all or next
          next();
        }
        notifyListeners();
        break;
      case 'onDeviceChanged':
        if (call.arguments is Map) {
          currentDevice = (call.arguments as Map)['device'] ?? "speaker";
          notifyListeners();
        }
        break;
      case 'onSpectrumData':
        if (call.arguments is List) {
          spectrumData = (call.arguments as List).map((e) => (e as num).toDouble()).toList();
          notifyListeners();
        }
        break;
    }
  }

  Future<void> addFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'flac', 'm4a', 'aac'],
      allowMultiple: true,
    );
    if (result == null) return;
    for (final f in result.files) {
      if (f.path != null) {
        final track = AudioTrack(
          id: DateTime.now().millisecondsSinceEpoch.toString() + f.name,
          path: f.path!,
          title: f.name.split('.').first,
          duration: 0, // Will be set when loaded
        );
        _library.addTrack(track);
      }
    }
    if (queue.isNotEmpty && current == null) {
      await _loadCurrent();
    } else {
      await _syncPlaylist();
    }
    notifyListeners();
  }

  Future<void> playIndex(int index) async {
    _library.jumpTo(index);
    await _syncPlaylist();
    await play();
  }

  Future<void> _loadCurrent() async {
    if (queue.isEmpty) return;
    await _ch.invokeMethod('loadAudio', {'path': current!.path});
    final dur = await _ch.invokeMethod<double>('getDuration') ?? 1.0;
    // Update duration in library
    if (current != null) {
      final updated = current!.copyWith(duration: dur);
      _library.updateTrack(updated);
    }
    position = 0;
    notifyListeners();
  }

  Future<void> _syncPlaylist() async {
    await _ch.invokeMethod('loadPlaylist', {
      'paths': queue.map((t) => t.path).toList(),
      'index': currentIndex,
    });
    final dur = await _ch.invokeMethod<double>('getDuration') ?? 1.0;
    if (current != null) {
      final updated = current!.copyWith(duration: dur);
      _library.updateTrack(updated);
    }
    position = 0;
    notifyListeners();
  }

  Future<void> play() async {
    if (queue.isEmpty) return;
    if (current == null) await _loadCurrent();
    await _ch.invokeMethod('play');
    isPlaying = true;
    _startTimer();
    notifyListeners();
  }

  Future<void> pause() async {
    await _ch.invokeMethod('pause');
    isPlaying = false;
    _posTimer?.cancel();
    notifyListeners();
  }

  Future<void> togglePlay() async => isPlaying ? pause() : play();

  Future<void> seek(double pos) async {
    await _ch.invokeMethod('seek', {'position': pos});
    position = pos;
    notifyListeners();
  }

  Future<void> next() async {
    if (shuffleEnabled) {
      // Shuffle logic
      if (_library.hasNext()) {
        _library.next();
        await _syncPlaylist();
        await play();
      }
    } else {
      await _ch.invokeMethod('next');
    }
  }

  Future<void> previous() async {
    if (shuffleEnabled) {
      if (_library.hasPrevious()) {
        _library.previous();
        await _syncPlaylist();
        await play();
      }
    } else {
      await _ch.invokeMethod('previous');
    }
  }

  Future<void> setPreset(String preset) async {
    currentPreset = preset;
    await _ch.invokeMethod('setPreset', {'preset': preset});
    notifyListeners();
  }

  Future<void> setShuffle(bool enabled) async {
    shuffleEnabled = enabled;
    await _ch.invokeMethod('setShuffle', {'enabled': enabled});
    if (enabled) {
      // Build shuffle order
    }
    notifyListeners();
  }

  Future<void> setRepeat(int mode) async {
    repeatMode = mode;
    await _ch.invokeMethod('setRepeat', {'mode': mode});
    notifyListeners();
  }

  Future<void> getDevice() async {
    currentDevice = await _ch.invokeMethod('getAudioDevice') ?? "speaker";
    notifyListeners();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _library.queue.removeAt(oldIndex);
    _library.queue.insert(newIndex, item);
    if (_library.currentIndex == oldIndex) {
      _library.jumpTo(newIndex);
    } else if (_library.currentIndex > oldIndex && _library.currentIndex <= newIndex) {
      _library.jumpTo(_library.currentIndex - 1);
    } else if (_library.currentIndex < oldIndex && _library.currentIndex >= newIndex) {
      _library.jumpTo(_library.currentIndex + 1);
    }
    notifyListeners();
  }

  void removeFromQueue(int index) {
    _library.removeFromQueue(index);
    notifyListeners();
  }

  void reorder(int oldIndex, int newIndex) => reorderQueue(oldIndex, newIndex);
  void removeTrack(int index) => removeFromQueue(index);

  void _startTimer() {
    _posTimer?.cancel();
    _posTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      if (!isPlaying) return;
      try {
        final pos = await _ch.invokeMethod<double>('getPosition') ?? position;
        position = pos.clamp(0.0, duration);
        notifyListeners();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _posTimer?.cancel();
    super.dispose();
  }
}

// ─── App ─────────────────────────────────────────────────────────────────────
class CinemaAudioLuxeApp extends StatelessWidget {
  const CinemaAudioLuxeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _audio,
      builder: (_, __) => MaterialApp(
        title: 'Cinema Audio Luxe',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF080808),
          primaryColor: _gold,
          colorScheme: const ColorScheme.dark(primary: _gold, secondary: Color(0xFFC0C0C0)),
          sliderTheme: SliderThemeData(
            activeTrackColor: _gold,
            inactiveTrackColor: const Color(0xFF2A2A2A),
            thumbColor: _gold,
            overlayColor: _gold.withOpacity(0.2),
          ),
        ),
        home: const MainShell(),
      ),
    );
  }
}

final _audio = AudioState();
const _gold = Color(0xFFD4AF37);
const _dark = Color(0xFF111111);

String _fmt(double s) {
  final m = s ~/ 60;
  final sec = s.toInt() % 60;
  return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}

// ─── Shell avec mini-player persistant ───────────────────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [const ImportScreen(), const PlayerScreen(), const QueueScreen(), const MixingConsoleScreen()];
    return Scaffold(
      body: pages[_tab],
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListenableBuilder(
            listenable: _audio,
            builder: (_, __) => _audio.current != null ? _MiniPlayer(onTap: () => setState(() => _tab = 1)) : const SizedBox.shrink(),
          ),
          NavigationBar(
            backgroundColor: const Color(0xFF0D0D0D),
            indicatorColor: _gold.withOpacity(0.2),
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.add_circle_outline), label: 'Importer'),
              NavigationDestination(icon: Icon(Icons.play_circle_outline), label: 'Lecteur'),
              NavigationDestination(icon: Icon(Icons.queue_music), label: 'File'),
              NavigationDestination(icon: Icon(Icons.tune), label: 'Console'),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Mini-player ─────────────────────────────────────────────────────────────
class _MiniPlayer extends StatelessWidget {
  final VoidCallback onTap;
  const _MiniPlayer({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: const Color(0xFF1A1A1A),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.music_note, color: _gold, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _audio.current?.title ?? '',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  LinearProgressIndicator(
                    value: _audio.duration > 0 ? (_audio.position / _audio.duration).clamp(0, 1) : 0,
                    backgroundColor: const Color(0xFF2A2A2A),
                    valueColor: const AlwaysStoppedAnimation(_gold),
                    minHeight: 2,
                  ),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.skip_previous, color: Colors.white70), onPressed: _audio.previous),
            IconButton(
              icon: Icon(_audio.isPlaying ? Icons.pause : Icons.play_arrow, color: _gold),
              onPressed: _audio.togglePlay,
            ),
            IconButton(icon: const Icon(Icons.skip_next, color: Colors.white70), onPressed: _audio.next),
          ],
        ),
      ),
    );
  }
}

// ─── Écran 1 : Import ─────────────────────────────────────────────────────────
class ImportScreen extends StatelessWidget {
  const ImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1C1600), Color(0xFF080808)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.theaters, size: 90, color: _gold),
                const SizedBox(height: 20),
                const Text('CINEMA AUDIO LUXE',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w300, letterSpacing: 5, color: _gold)),
                const SizedBox(height: 8),
                const Text('PATHÉ PALACE · DOLBY ATMOS',
                    style: TextStyle(fontSize: 10, letterSpacing: 3, color: Colors.white38)),
                const SizedBox(height: 60),
                _GoldButton(
                  label: '+ AJOUTER DES FICHIERS',
                  onPressed: () async {
                    await _audio.addFiles();
                    if (_audio.queue.isNotEmpty && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${_audio.queue.length} piste(s) dans la file'),
                          backgroundColor: const Color(0xFF1A1A1A),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 16),
                ListenableBuilder(
                  listenable: _audio,
                  builder: (_, __) => _audio.queue.isNotEmpty
                      ? Text('${_audio.queue.length} piste(s) chargée(s)',
                          style: const TextStyle(color: Colors.white54, fontSize: 13))
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Écran 2 : Lecteur ────────────────────────────────────────────────────────
class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1C1600), Color(0xFF080808)],
          ),
        ),
        child: SafeArea(
          child: ListenableBuilder(
            listenable: _audio,
            builder: (_, __) {
              final track = _audio.current;
              return Column(
                children: [
                  const SizedBox(height: 20),
                  // Artwork animé
                  AnimatedRotation(
                    turns: _audio.isPlaying ? 1.0 : 0.0,
                    duration: const Duration(seconds: 10),
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1500),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _gold, width: 1.5),
                        boxShadow: [BoxShadow(color: _gold.withOpacity(0.15), blurRadius: 40, spreadRadius: 5)],
                      ),
                      child: const Icon(Icons.music_note, size: 100, color: _gold),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Visualiseur de spectre
                  SizedBox(
                    height: 60,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(32, (i) {
                        return Container(
                          width: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 100),
                            height: (_audio.spectrumData[i] * 60).clamp(4, 60),
                            decoration: BoxDecoration(
                              color: _gold,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Indicateur périphérique
                  Text(
                    'Périphérique: ${_audio.currentDevice}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  // Titre
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      track?.title ?? 'Aucune piste',
                      style: const TextStyle(fontSize: 17, color: Colors.white, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                  if (_audio.queue.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${_audio.currentIndex + 1} / ${_audio.queue.length}',
                        style: const TextStyle(color: Colors.white38, fontSize: 12, letterSpacing: 2),
                      ),
                    ),
                  const SizedBox(height: 30),
                  // Barre de progression
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: Column(
                      children: [
                        Slider(
                          value: _audio.position.clamp(0.0, _audio.duration),
                          max: _audio.duration > 0 ? _audio.duration : 1.0,
                          onChanged: _audio.seek,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fmt(_audio.position), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            Text(_fmt(_audio.duration), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Contrôles
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded),
                        iconSize: 48,
                        color: Colors.white70,
                        onPressed: _audio.previous,
                      ),
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: _audio.togglePlay,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _gold,
                            boxShadow: [BoxShadow(color: _gold.withOpacity(0.4), blurRadius: 20)],
                          ),
                          child: Icon(
                            _audio.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            size: 40,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded),
                        iconSize: 48,
                        color: Colors.white70,
                        onPressed: _audio.next,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Sélecteur de preset avec animation
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _PresetButton(label: 'CINEMA', preset: 'cinema', isSelected: _audio.currentPreset == 'cinema'),
                      const SizedBox(width: 8),
                      _PresetButton(label: 'CONCERT', preset: 'concert', isSelected: _audio.currentPreset == 'concert'),
                      const SizedBox(width: 8),
                      _PresetButton(label: 'STUDIO', preset: 'studio', isSelected: _audio.currentPreset == 'studio'),
                      const SizedBox(width: 8),
                      _PresetButton(label: 'BASS+', preset: 'bassBoost', isSelected: _audio.currentPreset == 'bassBoost'),
                      const SizedBox(width: 8),
                      _PresetButton(label: 'VOCAL', preset: 'vocal', isSelected: _audio.currentPreset == 'vocal'),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Shuffle + Repeat
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(_audio.shuffleEnabled ? Icons.shuffle : Icons.shuffle_outlined, color: _audio.shuffleEnabled ? _gold : Colors.white54),
                        onPressed: () => _audio.setShuffle(!_audio.shuffleEnabled),
                      ),
                      const SizedBox(width: 20),
                      IconButton(
                        icon: Icon(
                          _audio.repeatMode == 0 ? Icons.repeat : _audio.repeatMode == 1 ? Icons.repeat_one : Icons.repeat,
                          color: _audio.repeatMode > 0 ? _gold : Colors.white54,
                        ),
                        onPressed: () => _audio.setRepeat((_audio.repeatMode + 1) % 3),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  final String label;
  final String preset;
  final bool isSelected;

  const _PresetButton({required this.label, required this.preset, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? _gold : Colors.transparent,
        border: Border.all(color: _gold, width: 1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: GestureDetector(
        onTap: () => _audio.setPreset(preset),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : _gold,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ─── Écran 3 : File d'attente / Playlist ─────────────────────────────────────
class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('FILE D\'ATTENTE', style: TextStyle(letterSpacing: 3, fontSize: 14, color: _gold)),
        actions: [
          TextButton.icon(
            onPressed: _audio.addFiles,
            icon: const Icon(Icons.add, color: _gold, size: 18),
            label: const Text('AJOUTER', style: TextStyle(color: _gold, fontSize: 11, letterSpacing: 1)),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _audio,
        builder: (_, __) {
          if (_audio.queue.isEmpty) {
            return const Center(
              child: Text('Aucune piste\nImportez des fichiers audio',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 14, height: 2)),
            );
          }
          return ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: _audio.queue.length,
            onReorder: _audio.reorder,
            itemBuilder: (_, i) {
              final t = _audio.queue[i];
              final isCurrent = i == _audio.currentIndex;
              return ListTile(
                key: ValueKey(t.path),
                leading: isCurrent
                    ? const Icon(Icons.equalizer, color: _gold)
                    : Text('${i + 1}', style: const TextStyle(color: Colors.white38, fontSize: 13)),
                title: Text(t.title,
                    style: TextStyle(
                      color: isCurrent ? _gold : Colors.white,
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.drag_handle, color: Colors.white24, size: 20),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                      onPressed: () => _audio.removeTrack(i),
                    ),
                  ],
                ),
                onTap: () => _audio.playIndex(i),
                tileColor: isCurrent ? _gold.withOpacity(0.08) : Colors.transparent,
              );
            },
          );
        },
      ),
    );
  }
}

// ─── Écran 4 : Console de mixage ─────────────────────────────────────────────
class MixingConsoleScreen extends StatefulWidget {
  const MixingConsoleScreen({super.key});
  @override
  State<MixingConsoleScreen> createState() => _MixingConsoleScreenState();
}

class _MixingConsoleScreenState extends State<MixingConsoleScreen> {
  static const _ch = MethodChannel('cinema.audio.luxe/audio');

  final Map<String, double> _fx = {
    'reverb': 0.25,
    'bass': 0.0,
    'volume': 0.0,
    'delay': 0.15,
    'spatial': 0.20,
    'warmth': 0.05,
    'clarity': 0.0,
    'presence': 0.0,
    'pitch': 0.5,
  };

  Future<void> _set(String key, double v) async {
    setState(() => _fx[key] = v);
    await _ch.invokeMethod('setEffect', {'effect': key, 'value': v});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('CONSOLE CINÉMA', style: TextStyle(letterSpacing: 3, fontSize: 14, color: _gold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('🎬 PATHÉ PALACE · DOLBY ATMOS'),
            _slider('🌊 IMMERSION (REVERB CATHÉDRALE)', 'reverb', '%'),
            _slider('🔊 SUB-BASS (32–125 Hz)', 'bass', '%'),
            _slider('⏱️ DELAY (ÉCHO SPATIAL)', 'delay', '%'),
            _slider('🌐 SPATIAL 3D', 'spatial', '%'),
            _sectionLabel('🎚️ TONALITÉ'),
            _slider('🔥 WARMTH (CHALEUR ANALOGIQUE)', 'warmth', '%'),
            _slider('💎 CLARITY (2–8 kHz)', 'clarity', '%'),
            _slider('🎤 PRÉSENCE (500–2 kHz)', 'presence', '%'),
            _pitchSlider(),
            _sectionLabel('🔈 VOLUME'),
            _slider('⚡ BOOST VOLUME (+200%)', 'volume', '%'),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(label, style: const TextStyle(color: _gold, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.bold)),
      );

  Widget _slider(String label, String key, String unit) {
    final v = _fx[key]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            Text('${(v * 100).toInt()}$unit', style: const TextStyle(color: _gold, fontSize: 12, fontFamily: 'monospace')),
          ],
        ),
        Slider(value: v, onChanged: (val) => _set(key, val)),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _pitchSlider() {
    final v = _fx['pitch']!;
    final cents = ((v - 0.5) * 400).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('🎵 PITCH', style: TextStyle(color: Colors.white70, fontSize: 13)),
            Text('${cents > 0 ? '+' : ''}$cents ¢', style: const TextStyle(color: _gold, fontSize: 12, fontFamily: 'monospace')),
          ],
        ),
        Slider(value: v, onChanged: (val) => _set('pitch', val)),
        const SizedBox(height: 4),
      ],
    );
  }
}

// ─── Bouton doré réutilisable ─────────────────────────────────────────────────
class _GoldButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _GoldButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: _gold,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        elevation: 8,
        shadowColor: _gold.withOpacity(0.4),
      ),
      child: Text(label, style: const TextStyle(fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.w600)),
    );
  }
}
