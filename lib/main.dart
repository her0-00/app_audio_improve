import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_library.dart';
import 'models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Logger interne pour afficher les erreurs sur l'appareil (sans console)
  AppLogger.init();

  // Capture des erreurs non gérées pour éviter les plantages brutaux.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger.log('Unhandled Flutter error: ${details.exception}');
  };

  runZonedGuarded(() {
    runApp(const CinemaAudioLuxeApp());
  }, (error, stack) {
    AppLogger.log('Unhandled zone error: $error');
    AppLogger.log(stack.toString());
  });
}

/// Logger en mémoire pour visualiser les erreurs directement dans l'app.
class AppLogger {
  static final List<String> _logs = [];

  static void init() {
    _logs.clear();
    log('--- AppLogger initialized');
  }

  static void log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final entry = '[$timestamp] $message';
    _logs.add(entry);
    if (_logs.length > 200) _logs.removeAt(0);
    debugPrint(entry);
  }

  static List<String> get logs => List.unmodifiable(_logs);
  static void clear() => _logs.clear();
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
  double get duration => current?.duration ?? 0.0;
  Timer? _posTimer;
  Timer? _spectrumTimer;
  bool _isUserSeeking = false; // Flag to prevent timer interference during seeking

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
    _initializeState();
  }

  Future<void> _initializeState() async {
    try {
      await _library.loadLibrary();
    } catch (e) {
      AppLogger.log('❌ Library load error: $e - Resetting library');
      // Si la bibliothèque est corrompue, la réinitialiser
      await _library.clearAll();
    }
    await _loadAudioSettings();
    _startSpectrumTimer();
    await refreshOutputDevices();
    await _syncInitialState();
  }

  Future<void> _loadAudioSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      shuffleEnabled = prefs.getBool('shuffleEnabled') ?? false;
      repeatMode = prefs.getInt('repeatMode') ?? 0;
      currentPreset = prefs.getString('currentPreset') ?? 'cinema';
    } catch (e) {
      debugPrint('Error loading audio settings: $e');
    }
  }

  Future<void> _saveAudioSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('shuffleEnabled', shuffleEnabled);
      await prefs.setInt('repeatMode', repeatMode);
      await prefs.setString('currentPreset', currentPreset);
    } catch (e) {
      debugPrint('Error saving audio settings: $e');
    }
  }

  Future<void> _syncInitialState() async {
    try {
      print('🔄 Starting initial state sync...');
      print('📋 Queue length: ${queue.length}');

      // Identifier les pistes valides et manquantes
      final validTracks = <AudioTrack>[];
      final missingTracks = <AudioTrack>[];

      for (final track in queue) {
        final file = File(track.path);
        final exists = await file.exists();
        if (exists) {
          validTracks.add(track);
          print('✅ Track exists: ${track.title}');
        } else {
          missingTracks.add(track);
          print('❌ Track missing: ${track.title} - ${track.path}');
        }
      }

      if (missingTracks.isNotEmpty) {
        print('⚠️ Found ${missingTracks.length} missing tracks');
        importStatus = '${missingTracks.length} piste(s) manquante(s) - Réimportez les fichiers';
        notifyListeners();
      }

      // Synchroniser seulement les pistes valides avec le code natif
      if (validTracks.isNotEmpty) {
        print('📤 Syncing playlist with ${validTracks.length} valid tracks...');

        // Envoyer seulement les pistes valides au code natif
        try {
          final validPaths = validTracks.map((t) => t.path).toList();
          print('📂 Valid paths: $validPaths');
          await _ch.invokeMethod('loadPlaylist', {
            'paths': validPaths,
            'index': 0, // Commencer par la première piste valide
          });
          print('✅ Valid playlist synced with native code');
        } catch (e) {
          print('❌ Error syncing valid playlist: $e');
        }

        // Charger la première piste valide
        print('🎵 Loading first valid track...');
        // Créer temporairement une queue avec seulement les pistes valides pour le chargement
        final tempCurrent = validTracks.first;
        try {
          await _ch.invokeMethod('loadAudio', {'path': tempCurrent.path});
          print('✅ First valid track loaded');

          // Récupérer la durée
          final dur = await _ch.invokeMethod<double>('getDuration') ?? 0.0;
          print('⏱️ Duration: $dur');
          if (dur > 0) {
            _library.updateTrack(tempCurrent.copyWith(duration: dur));
          }
        } catch (e) {
          print('❌ Error loading first valid track: $e');
        }

        position = 0;
      } else {
        print('⚠️ No valid tracks found');
        importStatus = 'Aucune piste valide trouvée - Importez des fichiers audio';
        notifyListeners();
      }

      // Appliquer les paramètres sauvegardés au code natif
      print('⚙️ Applying saved settings...');
      await _ch.invokeMethod('setShuffle', {'enabled': shuffleEnabled});
      await _ch.invokeMethod('setRepeat', {'mode': repeatMode});
      await _ch.invokeMethod('setPreset', {'preset': currentPreset});
      print('✅ Settings applied');

      // Nettoyer les pistes manquantes
      await _cleanupMissingTracks();

      print('🎉 Initial state sync completed');
      notifyListeners();
    } catch (e) {
      print('❌ Error syncing initial state: $e');
      debugPrint('Error syncing initial state: $e');
    }
  }

  /// Nettoie les pistes manquantes de la bibliothèque
  Future<void> _cleanupMissingTracks() async {
    print('🧹 Cleaning up missing tracks...');
    final initialCount = queue.length;
    final validTracks = queue.where((track) => File(track.path).existsSync()).toList();

    if (validTracks.length < initialCount) {
      print('🗑️ Removing ${initialCount - validTracks.length} missing tracks');
      _library.clearQueue();
      for (final track in validTracks) {
        _library.addTrack(track);
      }
      await _library.saveLibrary();
      print('✅ Cleanup completed. ${validTracks.length} tracks remaining.');
    } else {
      print('✅ No missing tracks found');
    }
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
    try {
      switch (call.method) {
        case 'onTrackChanged':
          if (call.arguments is Map) {
            final newIndex = (call.arguments as Map)['index'] as int?;
            if (newIndex != null && newIndex >= 0 && newIndex < queue.length) {
              _library.jumpTo(newIndex);
              AppLogger.log('✅ Track changed to index $newIndex');
            }
          }
          position = 0;
          isPlaying = true;
          notifyListeners();
          break;
        case 'onTrackFinished':
          AppLogger.log('🏁 Track finished');
          isPlaying = false;
          position = 0;
          _posTimer?.cancel();
          notifyListeners();
          break;
        case 'onDeviceChanged':
          if (call.arguments is Map) {
            currentDevice = (call.arguments as Map)['device']?.toString() ?? 'speaker';
            AppLogger.log('🎧 Device changed to: $currentDevice');
            notifyListeners();
          }
          break;
        case 'onUnknownDevice':
          if (call.arguments is Map) {
            currentDevice = (call.arguments as Map)['name']?.toString() ?? 'bluetooth';
            AppLogger.log('❓ Unknown device: $currentDevice');
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
        case 'log':
          if (call.arguments is String) {
            AppLogger.log(call.arguments as String);
          }
          break;
      }
    } catch (e, stack) {
      AppLogger.log('❌ CRASH _onNativeCall: $e');
      AppLogger.log(stack.toString());
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
      notifyListeners();
    } catch (e, stack) {
      AppLogger.log('❌ refreshOutputDevices error: $e');
      AppLogger.log(stack.toString());
    }
  }

  Future<bool> setOutputDevice(String portType) async {
    try {
      final success = await _ch.invokeMethod<bool>('setOutputDevice', {'portType': portType});
      if (success == true) {
        selectedOutput = portType;
        AppLogger.log('✅ Output device changed to: $portType');
        notifyListeners();
        return true;
      }
      return false;
    } catch (e, stack) {
      AppLogger.log('❌ setOutputDevice error: $e');
      AppLogger.log(stack.toString());
      return false;
    }
  }

  // ── Ajout de fichiers ───────────────────────────────────────────────────────
  // CORRECTION PRINCIPALE : chaque opération native est isolée dans son propre
  // try/catch pour éviter qu'une erreur sur un seul fichier ferme l'app.

  Future<void> addFiles() async {
    try {
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
        AppLogger.log('❌ FilePicker error: $e');
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
        try {
          final path = f.path;
          final originalName = f.name;
          AppLogger.log('📁 Fichier: $originalName');
          if (path == null) {
            AppLogger.log('⚠️ Path null');
            continue;
          }

          final sourceFile = File(path);
          if (!await sourceFile.exists()) {
            AppLogger.log('❌ Fichier introuvable');
            continue;
          }

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

          await sourceFile.copy(destPath);
          AppLogger.log('✅ Copié: $destPath');

          final track = AudioTrack(
            id: '${DateTime.now().microsecondsSinceEpoch}_$fileName',
            path: destPath,
            title: baseName,
            duration: 0,
          );
          _library.addTrack(track);
          _library.addToQueue(track);
          addedCount++;
        } catch (e) {
          AppLogger.log('❌ Erreur fichier: $e');
        }
      }

      importStatus = 'Total ajouté : $addedCount piste(s)';
      notifyListeners();

      if (addedCount == 0) {
        importStatus = 'Aucune piste importée';
        notifyListeners();
        return;
      }

      try {
        AppLogger.log('🔄 Syncing ${addedCount} new tracks with Swift...');
        await _syncPlaylist();
        AppLogger.log('✅ Sync OK');
      } catch (e) {
        AppLogger.log('❌ Sync error: $e');
        try {
          await _loadCurrent();
        } catch (e2) {
          AppLogger.log('❌ Load error: $e2');
          isPlaying = false;
          position = 0;
        }
      }
      notifyListeners();
    } catch (e, stack) {
      AppLogger.log('❌ CRASH addFiles: $e');
      AppLogger.log(stack.toString());
      importStatus = 'ERREUR: $e';
      notifyListeners();
    }
  }


  Future<void> playIndex(int index) async {
    // Vérifier si la piste demandée existe
    if (index < 0 || index >= queue.length) {
      print('❌ Invalid index: $index');
      return;
    }

    final track = queue[index];
    final file = File(track.path);
    final exists = await file.exists();

    if (!exists) {
      print('❌ Track file missing: ${track.title}');
      // Trouver la prochaine piste valide
      for (int i = index + 1; i < queue.length; i++) {
        final nextTrack = queue[i];
        final nextFile = File(nextTrack.path);
        if (await nextFile.exists()) {
          print('✅ Found next valid track at index $i: ${nextTrack.title}');
          _library.jumpTo(i);
          await _playValidTrack();
          return;
        }
      }
      // Si aucune piste valide trouvée après, chercher avant
      for (int i = index - 1; i >= 0; i--) {
        final prevTrack = queue[i];
        final prevFile = File(prevTrack.path);
        if (await prevFile.exists()) {
          print('✅ Found previous valid track at index $i: ${prevTrack.title}');
          _library.jumpTo(i);
          await _playValidTrack();
          return;
        }
      }
      // Aucune piste valide trouvée
      print('❌ No valid tracks found');
      importStatus = 'Aucune piste jouable trouvée - Réimportez des fichiers';
      notifyListeners();
      return;
    }

    // La piste existe, la jouer
    _library.jumpTo(index);
    await _playValidTrack();
  }

  Future<void> _playValidTrack() async {
    try {
      // Synchroniser seulement la piste actuelle avec le code natif
      final currentTrack = this.current;
      if (currentTrack == null) return;

      await _ch.invokeMethod('loadAudio', {'path': currentTrack.path});
      await _ch.invokeMethod('play');

      // Récupérer la durée
      final dur = await _ch.invokeMethod<double>('getDuration') ?? 0.0;
      if (dur > 0) {
        _library.updateTrack(currentTrack.copyWith(duration: dur));
      }

      isPlaying = true;
      position = 0;
      notifyListeners();
    } catch (e) {
      print('❌ Error playing valid track: $e');
      debugPrint('play error: $e');
      isPlaying = false;
      notifyListeners();
    }
  }

  // CORRECTION : getDuration retourne 0.0 en cas d'erreur, jamais d'exception
  Future<void> _loadCurrent() async {
    if (queue.isEmpty || current == null) {
      print('⚠️ Cannot load current: queue empty or no current track');
      return;
    }
    print('🎵 Loading current track: ${current!.title} at ${current!.path}');
    try {
      await _ch.invokeMethod('loadAudio', {'path': current!.path});
      print('✅ loadAudio successful');
    } catch (e) {
      print('❌ loadAudio error: $e');
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
      print('⏱️ Duration: $dur');
      if (dur > 0 && current != null) {
        _library.updateTrack(current!.copyWith(duration: dur));
      }
    } catch (e) {
      print('❌ getDuration error: $e');
      debugPrint('getDuration error: $e'); // Non bloquant
    }
    position = 0;
    notifyListeners();
  }

  Future<void> _syncPlaylist() async {
    if (queue.isEmpty) return;
    try {
      AppLogger.log('📤 Calling loadPlaylist with ${queue.length} tracks');
      final paths = queue.map((t) => t.path).toList();
      AppLogger.log('📂 Paths: ${paths.join(", ")}');
      await _ch.invokeMethod('loadPlaylist', {
        'paths': paths,
        'index': currentIndex,
      });
      AppLogger.log('✅ loadPlaylist completed - Swift now has ${queue.length} tracks');
    } catch (e) {
      AppLogger.log('❌ loadPlaylist error: $e');
      debugPrint('loadPlaylist error: $e');
      await _loadCurrent();
      return;
    }

    try {
      final dur = await _ch.invokeMethod<double>('getDuration') ?? 0.0;
      AppLogger.log('⏱️ Duration received: $dur');
      if (dur > 0 && current != null) {
        _library.updateTrack(current!.copyWith(duration: dur));
      }
    } catch (e) {
      AppLogger.log('❌ getDuration error: $e');
      debugPrint('getDuration error: $e');
    }
    position = 0;
    notifyListeners();
  }

  Future<void> play() async {
    try {
      if (queue.isEmpty) return;
      if (current == null) {
        try { await _loadCurrent(); } catch (e) { 
          AppLogger.log('❌ loadCurrent: $e');
          return; 
        }
      }
      try {
        await _ch.invokeMethod('play');
        isPlaying = true;
        _startTimer();
      } catch (e) {
        AppLogger.log('❌ play: $e');
        isPlaying = false;
      }
      notifyListeners();
    } catch (e, stack) {
      AppLogger.log('❌ CRASH play: $e');
      AppLogger.log(stack.toString());
    }
  }

  Future<void> pause() async {
    try {
      await _ch.invokeMethod('pause');
      isPlaying = false;
      _posTimer?.cancel();
      notifyListeners();
    } catch (e, stack) {
      AppLogger.log('❌ CRASH pause: $e');
      AppLogger.log(stack.toString());
    }
  }

  Future<void> togglePlay() async => isPlaying ? pause() : play();

  Future<void> seek(double pos) async {
    _isUserSeeking = true;
    try {
      if (duration <= 0) {
        AppLogger.log('⚠️ Cannot seek: duration is 0');
        _isUserSeeking = false;
        return;
      }
      final maxPos = duration * 0.95;
      final clampedPos = pos.clamp(0.0, maxPos);
      AppLogger.log('🎯 Seeking to $clampedPos (max: $maxPos)');
      await _ch.invokeMethod('seek', {'position': clampedPos});
      position = clampedPos;
      // NE PAS appeler notifyListeners ici - ça déclenche next()
    } catch (e, stack) {
      AppLogger.log('❌ CRASH seek: $e');
      AppLogger.log(stack.toString());
    } finally {
      Future.delayed(const Duration(milliseconds: 500), () {
        _isUserSeeking = false;
      });
    }
  }

  Future<void> next() async {
    try {
      if (queue.length <= 1) {
        AppLogger.log('⚠️ Next: only 1 track in queue');
        return;
      }
      await _ch.invokeMethod('next');
    } catch (e, stack) {
      AppLogger.log('❌ CRASH next: $e');
      AppLogger.log(stack.toString());
    }
  }

  Future<void> previous() async {
    try {
      if (queue.length <= 1) {
        AppLogger.log('⚠️ Previous: only 1 track in queue');
        // Si 1 seule piste, revenir au début
        await seek(0);
        return;
      }
      await _ch.invokeMethod('previous');
    } catch (e, stack) {
      AppLogger.log('❌ CRASH previous: $e');
      AppLogger.log(stack.toString());
    }
  }

  Future<void> setPreset(String preset) async {
    try {
      AppLogger.log('🎵 Changing preset to: $preset');
      currentPreset = preset;
      await _saveAudioSettings();
      await _ch.invokeMethod('setPreset', {'preset': preset});
      AppLogger.log('✅ Preset changed successfully');
      notifyListeners();
    } catch (e, stack) {
      AppLogger.log('❌ CRASH setPreset: $e');
      AppLogger.log(stack.toString());
    }
  }

  Future<void> setShuffle(bool enabled) async {
    try {
      if (enabled && queue.isEmpty) {
        importStatus = 'Importez des fichiers audio avant d\'activer le mode aléatoire';
        notifyListeners();
        return;
      }

      shuffleEnabled = enabled;
      await _saveAudioSettings();
      await _ch.invokeMethod('setShuffle', {'enabled': enabled});
      AppLogger.log('✅ Shuffle ${enabled ? "enabled" : "disabled"}');
      notifyListeners();
    } catch (e, stack) {
      AppLogger.log('❌ CRASH setShuffle: $e');
      AppLogger.log(stack.toString());
    }
  }

  Future<void> setRepeat(int mode) async {
    try {
      if (mode > 0 && queue.isEmpty) {
        importStatus = 'Importez des fichiers audio avant d\'activer la répétition';
        notifyListeners();
        return;
      }

      repeatMode = mode;
      await _saveAudioSettings();
      await _ch.invokeMethod('setRepeat', {'mode': mode});
      AppLogger.log('✅ Repeat mode: $mode');
      notifyListeners();
    } catch (e, stack) {
      AppLogger.log('❌ CRASH setRepeat: $e');
      AppLogger.log(stack.toString());
    }
  }

  Future<void> getDevice() async {
    try {
      currentDevice = await _ch.invokeMethod('getAudioDevice') ?? 'speaker';
      AppLogger.log('🎧 Current device: $currentDevice');
      notifyListeners();
    } catch (e, stack) {
      AppLogger.log('❌ getDevice error: $e');
      AppLogger.log(stack.toString());
    }
  }

  Future<void> bindDeviceProfile(String deviceName, String profile) async {
    try {
      await _ch.invokeMethod('bindDeviceProfile', {
        'name': deviceName,
        'profile': profile,
      });
      AppLogger.log('✅ Device profile bound: $deviceName -> $profile');
    } catch (e, stack) {
      AppLogger.log('❌ bindDeviceProfile error: $e');
      AppLogger.log(stack.toString());
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    try {
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
      AppLogger.log('✅ Queue reordered: $oldIndex -> $newIndex');
      notifyListeners();
    } catch (e, stack) {
      AppLogger.log('❌ reorderQueue error: $e');
      AppLogger.log(stack.toString());
    }
  }

  void removeFromQueue(int index) {
    try {
      if (index < 0 || index >= queue.length) {
        AppLogger.log('⚠️ Invalid remove index: $index');
        return;
      }
      final track = queue[index];
      _library.removeFromQueue(index);
      AppLogger.log('✅ Removed from queue: ${track.title}');
      notifyListeners();
    } catch (e, stack) {
      AppLogger.log('❌ removeFromQueue error: $e');
      AppLogger.log(stack.toString());
    }
  }

  void reorder(int oldIndex, int newIndex) => reorderQueue(oldIndex, newIndex);
  void removeTrack(int index) => removeFromQueue(index);

  void _startTimer() {
    try {
      _posTimer?.cancel();
      _posTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
        if (!isPlaying || _isUserSeeking) return;
        try {
          final pos = await _ch.invokeMethod<double>('getPosition') ?? position;
          position = pos.clamp(0.0, duration);
          notifyListeners();
        } catch (_) {}
      });
    } catch (e, stack) {
      AppLogger.log('❌ _startTimer error: $e');
      AppLogger.log(stack.toString());
    }
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
  if (s <= 0) return '--:--';
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
      floatingActionButton: FloatingActionButton(
        backgroundColor: _gold,
        child: const Icon(Icons.bug_report),
        tooltip: 'Afficher le journal de debug',
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DebugLogScreen()));
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
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
                          value: _audio.position.clamp(0.0, _audio.duration > 0 ? _audio.duration : 1.0),
                          max: _audio.duration > 0 ? _audio.duration : 1.0,
                          min: 0.0,
                          onChangeStart: (_) {
                            _audio._isUserSeeking = true;
                          },
                          onChangeEnd: (_) {
                            Future.delayed(const Duration(milliseconds: 500), () {
                              _audio._isUserSeeking = false;
                            });
                          },
                          onChanged: (value) {
                            // Update position immediately for visual feedback
                            _audio.position = value.clamp(0.0, _audio.duration);
                            // Seek to the position (seek method handles notifyListeners)
                            _audio.seek(value);
                          },
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fmt(_audio.position),
                                style: const TextStyle(color: Colors.white54, fontSize: 11)),
                            Text(_audio.duration > 0 ? _fmt(_audio.duration) : '--:--',
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
                        onPressed: _audio.queue.isNotEmpty
                            ? () => _audio.setShuffle(!_audio.shuffleEnabled)
                            : null,
                      ),
                      const SizedBox(width: 20),
                      IconButton(
                        icon: Icon(
                          _audio.repeatMode == 2 ? Icons.repeat_one : Icons.repeat,
                          color: _audio.repeatMode > 0 ? _gold : Colors.white54,
                        ),
                        onPressed: _audio.queue.isNotEmpty
                            ? () => _audio.setRepeat((_audio.repeatMode + 1) % 3)
                            : null,
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
            onPressed: () async {
              await _audio._cleanupMissingTracks();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Pistes manquantes nettoyées'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            icon: const Icon(Icons.cleaning_services, color: Colors.orange, size: 18),
            label: const Text('NETTOYER',
                style: TextStyle(color: Colors.orange, fontSize: 11, letterSpacing: 1)),
          ),
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

              // Vérifier si le fichier existe (on pourrait mettre ça en cache pour éviter les appels répétés)
              final fileExists = File(t.path).existsSync();
              final isMissing = !fileExists;

              return ListTile(
                key: ValueKey(t.id),
                leading: isCurrent
                    ? const Icon(Icons.equalizer, color: _gold)
                    : isMissing
                        ? const Icon(Icons.error_outline, color: Colors.red)
                        : Text('${i + 1}',
                            style: const TextStyle(color: Colors.white38, fontSize: 13)),
                title: Text(
                  t.title,
                  style: TextStyle(
                    color: isCurrent ? _gold : isMissing ? Colors.red : Colors.white,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 14,
                    decoration: isMissing ? TextDecoration.lineThrough : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: isMissing
                    ? const Text('Fichier manquant - Réimportez',
                        style: TextStyle(color: Colors.red, fontSize: 10))
                    : null,
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

  // Configuration par défaut
  final Map<String, double> _defaultConfig = {
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

  List<String> _savedPresets = [];
  String? _currentPresetName;

  @override
  void initState() {
    super.initState();
    _loadSavedPresets();
  }

  Future<void> _loadSavedPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final presets = prefs.getStringList('custom_presets') ?? [];
      setState(() {
        _savedPresets = presets;
      });
    } catch (e) {
      debugPrint('Error loading presets: $e');
      setState(() {});
    }
  }

  Future<void> _savePreset(String name) async {
    if (name.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final presetData = _fx.entries.map((e) => '${e.key}:${e.value}').join(',');
      await prefs.setString('preset_$name', presetData);

      if (!_savedPresets.contains(name)) {
        _savedPresets.add(name);
        await prefs.setStringList('custom_presets', _savedPresets);
      }

      setState(() => _currentPresetName = name);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Configuration "$name" sauvegardée'),
            backgroundColor: const Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving preset: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur lors de la sauvegarde'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadPreset(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final presetData = prefs.getString('preset_$name');
      if (presetData == null) return;

      final newFx = Map<String, double>.from(_fx);
      final entries = presetData.split(',');
      for (final entry in entries) {
        final parts = entry.split(':');
        if (parts.length == 2) {
          final key = parts[0];
          final value = double.tryParse(parts[1]) ?? 0.0;
          if (newFx.containsKey(key)) {
            newFx[key] = value;
          }
        }
      }

      // Appliquer la configuration
      for (final entry in newFx.entries) {
        await _ch.invokeMethod('setEffect', {'effect': entry.key, 'value': entry.value});
      }

      setState(() {
        _fx.clear();
        _fx.addAll(newFx);
        _currentPresetName = name;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Configuration "$name" chargée'),
            backgroundColor: const Color(0xFF1565C0),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error loading preset: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur lors du chargement'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deletePreset(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('preset_$name');
      _savedPresets.remove(name);
      await prefs.setStringList('custom_presets', _savedPresets);

      if (_currentPresetName == name) {
        setState(() => _currentPresetName = null);
      }

      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Configuration "$name" supprimée'),
            backgroundColor: const Color(0xFFEF6C00),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error deleting preset: $e');
    }
  }

  Future<void> _resetToDefault() async {
    try {
      AppLogger.log('🔄 Resetting to default config...');
      // Appliquer la configuration par défaut
      for (final entry in _defaultConfig.entries) {
        await _ch.invokeMethod('setEffect', {'effect': entry.key, 'value': entry.value});
      }

      setState(() {
        _fx.clear();
        _fx.addAll(_defaultConfig);
        _currentPresetName = null;
      });

      AppLogger.log('✅ Default config restored');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuration par défaut restaurée'),
            backgroundColor: Color(0xFF424242),
          ),
        );
      }
    } catch (e, stack) {
      AppLogger.log('❌ CRASH resetToDefault: $e');
      AppLogger.log(stack.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur lors de la réinitialisation'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _set(String key, double v) async {
    setState(() => _fx[key] = v);
    try {
      await _ch.invokeMethod('setEffect', {'effect': key, 'value': v});
    } catch (e, stack) {
      AppLogger.log('❌ setEffect($key, $v) error: $e');
      AppLogger.log(stack.toString());
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
            // Section de gestion des presets
            _sectionLabel('💾 CONFIGURATIONS'),
            if (_currentPresetName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Actuel: $_currentPresetName',
                  style: const TextStyle(color: _gold, fontSize: 12),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final name = await _showPresetNameDialog(context, 'Sauvegarder la configuration');
                      if (name != null) {
                        await _savePreset(name);
                      }
                    },
                    icon: const Icon(Icons.save, size: 16),
                    label: const Text('SAUVEGARDER'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: Colors.black,
                      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _resetToDefault,
                    icon: const Icon(Icons.restore, size: 16),
                    label: const Text('DÉFAUT'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF424242),
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
            if (_savedPresets.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Configurations sauvegardées:',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _savedPresets.map((preset) => _presetChip(preset)).toList(),
              ),
            ],
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

  Widget _presetChip(String presetName) {
    final isCurrent = _currentPresetName == presetName;
    return GestureDetector(
      onTap: () => _loadPreset(presetName),
      onLongPress: () => _showDeletePresetDialog(context, presetName),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isCurrent ? _gold : const Color(0xFF424242),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _gold, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              presetName,
              style: TextStyle(
                color: isCurrent ? Colors.black : Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (isCurrent) ...[
              const SizedBox(width: 4),
              Icon(Icons.check, size: 12, color: Colors.black),
            ],
          ],
        ),
      ),
    );
  }

  Future<String?> _showPresetNameDialog(BuildContext context, String title) async {
    String name = '';
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          onChanged: (value) => name = value,
          decoration: const InputDecoration(
            hintText: 'Nom de la configuration',
            border: OutlineInputBorder(),
          ),
          maxLength: 20,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ANNULER'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, name.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeletePresetDialog(BuildContext context, String presetName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la configuration?'),
        content: Text('Voulez-vous supprimer "$presetName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ANNULER'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('SUPPRIMER'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _deletePreset(presetName);
    }
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

// ─── Écran de logs intégré (accessible via le bouton "bug" en bas à droite)
class DebugLogScreen extends StatelessWidget {
  const DebugLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final logs = AppLogger.logs.reversed.toList();
    return Scaffold(
      backgroundColor: _dark,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        title: const Text('Journal de debug'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copier dans le presse-papiers',
            onPressed: () {
              final text = logs.join('\n');
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logs copiés dans le presse-papiers')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Sauvegarder dans un fichier',
            onPressed: () async {
              try {
                final text = logs.join('\n');
                final dir = await getApplicationDocumentsDirectory();
                final file = File('${dir.path}/debug_logs_${DateTime.now().millisecondsSinceEpoch}.txt');
                await file.writeAsString(text);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Logs sauvegardés: ${file.path}')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Erreur sauvegarde: $e')),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Effacer le journal',
            onPressed: () {
              AppLogger.clear();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: Container(
        color: const Color(0xFF101010),
        child: logs.isEmpty
            ? const Center(
                child: Text('Aucun log disponible',
                    style: TextStyle(color: Colors.white54, fontSize: 14)),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: logs.length,
                itemBuilder: (_, i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      logs[i],
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
