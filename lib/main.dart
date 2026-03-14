import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:io';
import 'audio_library.dart';
import 'models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CinemaAudioLuxeApp());
}

// ─── État global partagé ─────────────────────────────────────────────────────
class AudioState extends ChangeNotifier {
  static const _ch = MethodChannel('cinema.audio.luxe/audio');
  final AudioLibrary _library = AudioLibrary();

  List<AudioTrack> get queue => _library.queue;
  int get currentIndex => _library.currentIndex;
  AudioTrack? get current => _library.currentTrack;
  bool isPlaying = false;
  double position = 0;
  double get duration => (current?.duration ?? 0) > 0 ? current!.duration : 1;
  Timer? _posTimer;
  Timer? _spectrumTimer;

  String currentPreset = 'cinema';
  bool shuffleEnabled = false;
  int repeatMode = 0;
  String currentDevice = 'speaker';
  String selectedOutput = 'default';
  List<Map<String, String>> availableOutputs = [];
  List<double> spectrumData = List.filled(32, 0.0);

  // Messages d'état affichés à l'utilisateur (Import / Erreurs)
  String importStatus = '';

  AudioState() {
    _ch.setMethodCallHandler(_onNativeCall);
    _library.loadLibrary();
    _startSpectrumTimer();
    refreshOutputDevices();
  }

  void _startSpectrumTimer() {
    _spectrumTimer?.cancel();
    _spectrumTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!isPlaying) return;
      final t = DateTime.now().millisecondsSinceEpoch;
      spectrumData = List.generate(32, (i) {
        final v = ((t + i * 137) % 1000) / 1000.0;
        return (0.1 + 0.9 * v).clamp(0.0, 1.0);
      });
      notifyListeners();
    });
  }

  Future<void> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onTrackChanged':
        position = 0;
        isPlaying = true;
        notifyListeners();
        break;
      case 'onTrackFinished':
        isPlaying = false;
        position = 0;
        _posTimer?.cancel();
        notifyListeners();
        break;
      case 'onDeviceChanged':
        if (call.arguments is Map) {
          currentDevice = (call.arguments as Map)['device']?.toString() ?? 'speaker';
          notifyListeners();
        }
        break;
      case 'onUnknownDevice':
        // Appareil Bluetooth inconnu → on applique le profil générique sans crash
        if (call.arguments is Map) {
          currentDevice = (call.arguments as Map)['name']?.toString() ?? 'bluetooth';
          notifyListeners();
        }
        break;
      case 'onSpectrumData':
        if (call.arguments is List) {
          spectrumData = (call.arguments as List)
              .map((e) => (e as num).toDouble())
              .toList();
          notifyListeners();
        }
        break;
    }
  }

  Future<void> refreshOutputDevices() async {
    try {
      final result = await _ch.invokeMethod<List>('getOutputDevices');
      if (result != null) {
        availableOutputs = result
            .cast<Map>()
            .map((m) => {
                  'portType': m['portType']?.toString() ?? '',
                  'portName': m['portName']?.toString() ?? '',
                })
            .toList();
      }
      final current = await _ch.invokeMethod<String>('getAudioDevice');
      selectedOutput = current ?? selectedOutput;
    } catch (e) {
      debugPrint('refreshOutputDevices error: $e');
    }
    notifyListeners();
  }

  Future<bool> setOutputDevice(String portType) async {
    try {
      final success = await _ch.invokeMethod<bool>('setOutputDevice', {'portType': portType});
      if (success == true) {
        selectedOutput = portType;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('setOutputDevice error: $e');
    }
    return false;
  }

  // ── Ajout de fichiers ───────────────────────────────────────────────────────
  // CORRECTION PRINCIPALE : chaque opération native est isolée dans son propre
  // try/catch pour éviter qu'une erreur sur un seul fichier ferme l'app.

  Future<void> addFiles() async {
    importStatus = 'Sélecteur de fichiers ouvert…';
    notifyListeners();

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg', 'opus'],
        allowMultiple: true,
      );
      importStatus = 'Sélection : ${result?.files.length ?? 0} fichier(s)';
      notifyListeners();
    } catch (e) {
      importStatus = 'Erreur FilePicker : $e';
      notifyListeners();
      return;
    }
    if (result == null) {
      importStatus = 'Import annulé';
      notifyListeners();
      return;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory('${docsDir.path}/Media');
    if (!await mediaDir.exists()) await mediaDir.create(recursive: true);

    int addedCount = 0;
    for (final f in result.files) {
      final path = f.path;
      final originalName = f.name;
      print('📁 Fichier importé: $originalName, path: $path');
      if (path == null) {
        print('⚠️ Path null pour $originalName');
        continue;
      }

      final sourceFile = File(path);
      if (!await sourceFile.exists()) {
        print('❌ Fichier introuvable: $path');
        continue;
      }

      // Copie le fichier dans le répertoire Documents/Media de l'application.
      // Cela permet de s'assurer qu'il est conservé et accessible même après
      // que le fichier d'origine ait été supprimé ou désactivé par iOS.
      String fileName = sourceFile.uri.pathSegments.last;
      final extIndex = fileName.lastIndexOf('.');
      final baseName = extIndex > 0 ? fileName.substring(0, extIndex) : fileName;
      final ext = extIndex > 0 ? fileName.substring(extIndex) : '';

      String destPath = '${mediaDir.path}/$fileName';
      int counter = 1;
      while (await File(destPath).exists()) {
        destPath = '${mediaDir.path}/${baseName}_$counter$ext';
        counter++;
      }

      try {
        await sourceFile.copy(destPath);
        print('✅ Copie réussie dans app: $destPath');
      } catch (e) {
        print('❌ Échec copie: $e');
        continue;
      }

      final track = AudioTrack(
        id: '${DateTime.now().microsecondsSinceEpoch}_$fileName',
        path: destPath,
        title: baseName,
        duration: 0,
      );
      _library.addTrack(track);
      _library.addToQueue(track);
      print('✅ Track ajouté et mise en file : ${track.title}');
      addedCount++;
    }

    importStatus = 'Total ajouté : $addedCount piste(s)';
    notifyListeners();

    if (addedCount == 0) {
      importStatus = 'Aucune piste importée (vérifiez les permissions)';
      notifyListeners();
      return;
    }

    try {
      print('🔄 Sync playlist...');
      await _syncPlaylist();
      print('✅ Playlist synced');
    } catch (e) {
      print('❌ Erreur sync playlist: $e');
      try {
        await _loadCurrent();
      } catch (e2) {
        print('❌ Erreur load current: $e2');
        isPlaying = false;
        position = 0;
      }
    }

    print('🔔 notifyListeners');
    notifyListeners();
  }


  Future<void> playIndex(int index) async {
    _library.jumpTo(index);
    try {
      await _syncPlaylist();
      await play();
    } catch (e) {
      debugPrint('playIndex error: $e');
      isPlaying = false;
      notifyListeners();
    }
  }

  // CORRECTION : getDuration retourne 0.0 en cas d'erreur, jamais d'exception
  Future<void> _loadCurrent() async {
    if (queue.isEmpty || current == null) return;
    try {
      await _ch.invokeMethod('loadAudio', {'path': current!.path});
    } catch (e) {
      debugPrint('loadAudio error: $e');
      // Si le fichier ne se charge pas, on skip au suivant
      if (_library.hasNext()) {
        _library.next();
        await _loadCurrent();
      }
      return;
    }

    try {
      final dur = await _ch.invokeMethod<double>('getDuration') ?? 0.0;
      if (dur > 0 && current != null) {
        _library.updateTrack(current!.copyWith(duration: dur));
      }
    } catch (e) {
      debugPrint('getDuration error: $e'); // Non bloquant
    }
    position = 0;
    notifyListeners();
  }

  // CORRECTION : _syncPlaylist ne propage plus d'exception vers addFiles
  Future<void> _syncPlaylist() async {
    if (queue.isEmpty) return;
    try {
      await _ch.invokeMethod('loadPlaylist', {
        'paths': queue.map((t) => t.path).toList(),
        'index': currentIndex,
      });
    } catch (e) {
      debugPrint('loadPlaylist error: $e');
      // Fallback sur loadAudio simple
      await _loadCurrent();
      return;
    }

    try {
      final dur = await _ch.invokeMethod<double>('getDuration') ?? 0.0;
      if (dur > 0 && current != null) {
        _library.updateTrack(current!.copyWith(duration: dur));
      }
    } catch (e) {
      debugPrint('getDuration error: $e'); // Non bloquant
    }
    position = 0;
    notifyListeners();
  }

  Future<void> play() async {
    if (queue.isEmpty) return;
    if (current == null) {
      try { await _loadCurrent(); } catch (e) { return; }
    }
    try {
      await _ch.invokeMethod('play');
      isPlaying = true;
      _startTimer();
    } catch (e) {
      debugPrint('play error: $e');
      isPlaying = false;
    }
    notifyListeners();
  }

  Future<void> pause() async {
    try {
      await _ch.invokeMethod('pause');
    } catch (e) {
      debugPrint('pause error: $e');
    }
    isPlaying = false;
    _posTimer?.cancel();
    notifyListeners();
  }

  Future<void> togglePlay() async => isPlaying ? pause() : play();

  Future<void> seek(double pos) async {
    try {
      await _ch.invokeMethod('seek', {'position': pos});
      position = pos;
    } catch (e) {
      debugPrint('seek error: $e');
    }
    notifyListeners();
  }

  Future<void> next() async {
    try {
      await _ch.invokeMethod('next');
    } catch (e) {
      debugPrint('next error: $e');
    }
  }

  Future<void> previous() async {
    try {
      await _ch.invokeMethod('previous');
    } catch (e) {
      debugPrint('previous error: $e');
    }
  }

  Future<void> setPreset(String preset) async {
    currentPreset = preset;
    try {
      await _ch.invokeMethod('setPreset', {'preset': preset});
    } catch (e) {
      debugPrint('setPreset error: $e');
    }
    notifyListeners();
  }

  Future<void> setShuffle(bool enabled) async {
    shuffleEnabled = enabled;
    try {
      await _ch.invokeMethod('setShuffle', {'enabled': enabled});
    } catch (e) {
      debugPrint('setShuffle error: $e');
    }
    notifyListeners();
  }

  Future<void> setRepeat(int mode) async {
    repeatMode = mode;
    try {
      await _ch.invokeMethod('setRepeat', {'mode': mode});
    } catch (e) {
      debugPrint('setRepeat error: $e');
    }
    notifyListeners();
  }

  Future<void> getDevice() async {
    try {
      currentDevice = await _ch.invokeMethod('getAudioDevice') ?? 'speaker';
    } catch (e) {
      debugPrint('getDevice error: $e');
    }
    notifyListeners();
  }

  // Associer un appareil inconnu à un profil EQ depuis Flutter
  Future<void> bindDeviceProfile(String deviceName, String profile) async {
    try {
      await _ch.invokeMethod('bindDeviceProfile', {
        'name': deviceName,
        'profile': profile,
      });
    } catch (e) {
      debugPrint('bindDeviceProfile error: $e');
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
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
    _spectrumTimer?.cancel();
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
          colorScheme: const ColorScheme.dark(
            primary: _gold,
            secondary: Color(0xFFC0C0C0),
          ),
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

// ─── Shell ───────────────────────────────────────────────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const ImportScreen(),
      const PlayerScreen(),
      const QueueScreen(),
      const MixingConsoleScreen(),
    ];
    return Scaffold(
      body: pages[_tab],
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListenableBuilder(
            listenable: _audio,
            builder: (_, __) => _audio.current != null
                ? _MiniPlayer(onTap: () => setState(() => _tab = 1))
                : const SizedBox.shrink(),
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
                    value: _audio.duration > 0
                        ? (_audio.position / _audio.duration).clamp(0.0, 1.0)
                        : 0.0,
                    backgroundColor: const Color(0xFF2A2A2A),
                    valueColor: const AlwaysStoppedAnimation(_gold),
                    minHeight: 2,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.skip_previous, color: Colors.white70),
              onPressed: _audio.previous,
            ),
            IconButton(
              icon: Icon(
                _audio.isPlaying ? Icons.pause : Icons.play_arrow,
                color: _gold,
              ),
              onPressed: _audio.togglePlay,
            ),
            IconButton(
              icon: const Icon(Icons.skip_next, color: Colors.white70),
              onPressed: _audio.next,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Écran 1 : Import ────────────────────────────────────────────────────────
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
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 5,
                      color: _gold,
                    )),
                const SizedBox(height: 8),
                const Text('PATHÉ PALACE · DOLBY ATMOS',
                    style: TextStyle(fontSize: 10, letterSpacing: 3, color: Colors.white38)),
                const SizedBox(height: 60),
                _GoldButton(
                  label: '+ AJOUTER DES FICHIERS',
                  onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Ouverture du sélecteur...'),
                        duration: Duration(seconds: 1),
                        backgroundColor: Color(0xFF1A1A1A),
                      ),
                    );
                    await _audio.addFiles();
                    if (!context.mounted) return;
                    if (_audio.queue.isNotEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✅ ${_audio.queue.length} piste(s) ajoutée(s)'),
                          backgroundColor: Colors.green.shade800,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('❌ Aucun fichier importé. Vérifiez les permissions.'),
                          backgroundColor: Colors.red,
                          duration: Duration(seconds: 4),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 16),
                ListenableBuilder(
                  listenable: _audio,
                  builder: (_, __) => Column(
                    children: [
                      if (_audio.importStatus.isNotEmpty)
                        Text(_audio.importStatus,
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      if (_audio.importStatus.isNotEmpty)
                        const SizedBox(height: 8),
                      if (_audio.queue.isNotEmpty)
                        Text('${_audio.queue.length} piste(s) chargée(s)',
                            style: const TextStyle(color: Colors.white54, fontSize: 13)),
                      if (_audio.queue.isNotEmpty)
                        const SizedBox(height: 8),
                      if (_audio.queue.isNotEmpty)
                        Text('🎵 Allez dans "File" pour voir la liste',
                            style: const TextStyle(color: _gold, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Écran 2 : Lecteur ───────────────────────────────────────────────────────
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
                  // Artwork
                  Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1500),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _gold, width: 1.5),
                      boxShadow: [
                        BoxShadow(color: _gold.withOpacity(0.15), blurRadius: 40, spreadRadius: 5),
                      ],
                    ),
                    child: const Icon(Icons.music_note, size: 90, color: _gold),
                  ),
                  const SizedBox(height: 16),
                  // Visualiseur spectre
                  SizedBox(
                    height: 50,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(32, (i) {
                        return Container(
                          width: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 100),
                            height: (_audio.spectrumData[i] * 50).clamp(3.0, 50.0),
                            decoration: BoxDecoration(
                              color: _gold,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Périphérique actif + sélection de sortie
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '🎧 ${_audio.currentDevice}',
                        style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () async {
                          await _audio.refreshOutputDevices();
                          if (!context.mounted) return;
                          final choice = await showDialog<String>(
                            context: context,
                            builder: (dialogContext) {
                              return SimpleDialog(
                                title: const Text('Sortie audio'),
                                children: [
                                  SimpleDialogOption(
                                    onPressed: () => Navigator.pop(dialogContext, 'default'),
                                    child: const Text('Système (automatique)'),
                                  ),
                                  ..._audio.availableOutputs.map((o) {
                                    final name = o['portName'] ?? o['portType'] ?? 'Inconnu';
                                    final portType = o['portType'] ?? '';
                                    return SimpleDialogOption(
                                      onPressed: () => Navigator.pop(dialogContext, portType),
                                      child: Text(name),
                                    );
                                  }),
                                ],
                              );
                            },
                          );
                          if (choice != null) {
                            await _audio.setOutputDevice(choice);
                          }
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: _gold,
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        child: const Text('Changer'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Titre
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      track?.title ?? 'Aucune piste',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
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
                        style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2),
                      ),
                    ),
                  const SizedBox(height: 16),
                  // Barre de progression
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
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
                            Text(_fmt(_audio.position),
                                style: const TextStyle(color: Colors.white54, fontSize: 11)),
                            Text(_fmt(_audio.duration),
                                style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Contrôles
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded),
                        iconSize: 44,
                        color: Colors.white70,
                        onPressed: _audio.previous,
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _audio.togglePlay,
                        child: Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _gold,
                            boxShadow: [
                              BoxShadow(color: _gold.withOpacity(0.4), blurRadius: 20),
                            ],
                          ),
                          child: Icon(
                            _audio.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            size: 38,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded),
                        iconSize: 44,
                        color: Colors.white70,
                        onPressed: _audio.next,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Presets
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        _PresetButton(label: 'CINEMA',  preset: 'cinema',    isSelected: _audio.currentPreset == 'cinema'),
                        const SizedBox(width: 6),
                        _PresetButton(label: 'CONCERT', preset: 'concert',   isSelected: _audio.currentPreset == 'concert'),
                        const SizedBox(width: 6),
                        _PresetButton(label: 'STUDIO',  preset: 'studio',    isSelected: _audio.currentPreset == 'studio'),
                        const SizedBox(width: 6),
                        _PresetButton(label: 'BASS+',   preset: 'bassBoost', isSelected: _audio.currentPreset == 'bassBoost'),
                        const SizedBox(width: 6),
                        _PresetButton(label: 'VOCAL',   preset: 'vocal',     isSelected: _audio.currentPreset == 'vocal'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Shuffle + Repeat
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(
                          _audio.shuffleEnabled ? Icons.shuffle : Icons.shuffle_outlined,
                          color: _audio.shuffleEnabled ? _gold : Colors.white54,
                        ),
                        onPressed: () => _audio.setShuffle(!_audio.shuffleEnabled),
                      ),
                      const SizedBox(width: 20),
                      IconButton(
                        icon: Icon(
                          _audio.repeatMode == 2 ? Icons.repeat_one : Icons.repeat,
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
    return GestureDetector(
      onTap: () => _audio.setPreset(preset),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? _gold : Colors.transparent,
          border: Border.all(color: _gold, width: 1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : _gold,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ─── Écran 3 : File d'attente ────────────────────────────────────────────────
class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("FILE D'ATTENTE",
            style: TextStyle(letterSpacing: 3, fontSize: 14, color: _gold)),
        actions: [
          TextButton.icon(
            onPressed: _audio.addFiles,
            icon: const Icon(Icons.add, color: _gold, size: 18),
            label: const Text('AJOUTER',
                style: TextStyle(color: _gold, fontSize: 11, letterSpacing: 1)),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _audio,
        builder: (_, __) {
          if (_audio.queue.isEmpty) {
            return const Center(
              child: Text(
                'Aucune piste\nImportez des fichiers audio',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 14, height: 2),
              ),
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
                key: ValueKey(t.id),
                leading: isCurrent
                    ? const Icon(Icons.equalizer, color: _gold)
                    : Text('${i + 1}',
                        style: const TextStyle(color: Colors.white38, fontSize: 13)),
                title: Text(
                  t.title,
                  style: TextStyle(
                    color: isCurrent ? _gold : Colors.white,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
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
    'reverb':   0.25,
    'bass':     0.0,
    'volume':   0.0,
    'delay':    0.15,
    'warmth':   0.05,
    'clarity':  0.0,
    'presence': 0.0,
    'pitch':    0.5,
    'crossfeed': 0.0,
    'exciter':  0.0,
    'compress': 0.5,
  };

  Future<void> _set(String key, double v) async {
    setState(() => _fx[key] = v);
    try {
      await _ch.invokeMethod('setEffect', {'effect': key, 'value': v});
    } catch (e) {
      debugPrint('setEffect error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('CONSOLE CINÉMA',
            style: TextStyle(letterSpacing: 3, fontSize: 14, color: _gold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('🎬 PATHÉ PALACE · DOLBY ATMOS'),
            _slider('🌊 IMMERSION (REVERB)', 'reverb', '%'),
            _slider('🔊 SUB-BASS (32–125 Hz)', 'bass', '%'),
            _slider('⏱️ DELAY (ÉCHO SPATIAL)', 'delay', '%'),
            _slider('🔀 CROSSFEED STÉRÉO', 'crossfeed', '%'),
            _sectionLabel('🎚️ TONALITÉ'),
            _slider('🔥 WARMTH (CHALEUR ANALOGIQUE)', 'warmth', '%'),
            _slider('💎 CLARITY (2–8 kHz)', 'clarity', '%'),
            _slider('🎤 PRÉSENCE (500–2 kHz)', 'presence', '%'),
            _slider('✨ EXCITER HARMONIQUE', 'exciter', '%'),
            _pitchSlider(),
            _sectionLabel('⚙️ DYNAMIQUE'),
            _slider('🗜️ COMPRESSEUR', 'compress', '%'),
            _sectionLabel('🔈 VOLUME'),
            _slider('⚡ BOOST VOLUME', 'volume', '%'),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(label,
            style: const TextStyle(
              color: _gold,
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
            )),
      );

  Widget _slider(String label, String key, String unit) {
    final v = _fx[key] ?? 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  overflow: TextOverflow.ellipsis),
            ),
            Text('${(v * 100).toInt()}$unit',
                style: const TextStyle(
                  color: _gold,
                  fontSize: 12,
                  fontFamily: 'monospace',
                )),
          ],
        ),
        Slider(value: v, onChanged: (val) => _set(key, val)),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _pitchSlider() {
    final v = _fx['pitch'] ?? 0.5;
    final cents = ((v - 0.5) * 400).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('🎵 PITCH', style: TextStyle(color: Colors.white70, fontSize: 13)),
            Text('${cents > 0 ? '+' : ''}$cents ¢',
                style: const TextStyle(color: _gold, fontSize: 12, fontFamily: 'monospace')),
          ],
        ),
        Slider(value: v, onChanged: (val) => _set('pitch', val)),
        const SizedBox(height: 4),
      ],
    );
  }
}

// ─── Bouton doré ─────────────────────────────────────────────────────────────
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
      child: Text(label,
          style: const TextStyle(fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.w600)),
    );
  }
}