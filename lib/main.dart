import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

void main() => runApp(const CinemaAudioLuxeApp());

class CinemaAudioLuxeApp extends StatelessWidget {
  const CinemaAudioLuxeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cinema Audio Luxe',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        primaryColor: const Color(0xFFD4AF37),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFD4AF37),
          secondary: Color(0xFFC0C0C0),
        ),
      ),
      home: const ImportScreen(),
    );
  }
}

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  static const platform = MethodChannel('cinema.audio.luxe/audio');
  String? _currentFile;

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'flac', 'm4a'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      try {
        await platform.invokeMethod('loadAudio', {'path': path});
        setState(() => _currentFile = result.files.single.name);
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => PlayerScreen(fileName: _currentFile!)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A1A), Color(0xFF0A0A0A)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.theaters, size: 100, color: Color(0xFFD4AF37)),
              SizedBox(height: 30),
              Text(
                'CINEMA AUDIO LUXE',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 4,
                  color: Color(0xFFD4AF37),
                ),
              ),
              SizedBox(height: 60),
              ElevatedButton(
                onPressed: _pickFile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFD4AF37),
                  foregroundColor: Colors.black,
                  padding: EdgeInsets.symmetric(horizontal: 50, vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: Text('IMPORTER UN FICHIER', style: TextStyle(fontSize: 16, letterSpacing: 2)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  final String fileName;
  const PlayerScreen({super.key, required this.fileName});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const platform = MethodChannel('cinema.audio.luxe/audio');
  bool _isPlaying = false;
  double _position = 0.0;
  double _duration = 1.0;

  @override
  void initState() {
    super.initState();
    _getDuration();
  }

  Future<void> _getDuration() async {
    try {
      final duration = await platform.invokeMethod('getDuration');
      setState(() => _duration = duration.toDouble());
    } catch (e) {}
  }

  Future<void> _togglePlayPause() async {
    try {
      if (_isPlaying) {
        await platform.invokeMethod('pause');
      } else {
        await platform.invokeMethod('play');
      }
      setState(() => _isPlaying = !_isPlaying);
    } catch (e) {}
  }

  Future<void> _seek(double position) async {
    try {
      await platform.invokeMethod('seek', {'position': position});
      setState(() => _position = position);
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('LECTEUR VIP', style: TextStyle(letterSpacing: 3, fontSize: 16)),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A1A), Color(0xFF0A0A0A)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                color: Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Color(0xFFD4AF37), width: 2),
              ),
              child: Icon(Icons.music_note, size: 120, color: Color(0xFFD4AF37)),
            ),
            SizedBox(height: 40),
            Text(
              widget.fileName,
              style: TextStyle(fontSize: 18, color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 40),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Slider(
                value: _position,
                max: _duration,
                activeColor: Color(0xFFD4AF37),
                inactiveColor: Color(0xFF333333),
                onChanged: _seek,
              ),
            ),
            SizedBox(height: 20),
            IconButton(
              onPressed: _togglePlayPause,
              icon: Icon(_isPlaying ? Icons.pause_circle : Icons.play_circle),
              iconSize: 80,
              color: Color(0xFFD4AF37),
            ),
            SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => MixingConsoleScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFC0C0C0),
                foregroundColor: Colors.black,
                padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              ),
              child: Text('CONSOLE DE MIXAGE', style: TextStyle(letterSpacing: 2)),
            ),
          ],
        ),
      ),
    );
  }
}

class MixingConsoleScreen extends StatefulWidget {
  const MixingConsoleScreen({super.key});

  @override
  State<MixingConsoleScreen> createState() => _MixingConsoleScreenState();
}

class _MixingConsoleScreenState extends State<MixingConsoleScreen> {
  static const platform = MethodChannel('cinema.audio.luxe/audio');
  double _immersion = 0.15;
  double _subBass = 0.0;
  double _boostVolume = 0.0;

  Future<void> _updateEffect(String effect, double value) async {
    try {
      await platform.invokeMethod('setEffect', {'effect': effect, 'value': value});
    } catch (e) {}
  }

  Widget _buildSlider(String label, double value, Function(double) onChanged, {String unit = ''}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 16, color: Color(0xFFD4AF37), letterSpacing: 2),
        ),
        SizedBox(height: 10),
        Slider(
          value: value,
          min: 0.0,
          max: 1.0,
          activeColor: Color(0xFFD4AF37),
          inactiveColor: Color(0xFF333333),
          onChanged: onChanged,
        ),
        Text(
          '${(value * 100).toInt()}$unit',
          style: TextStyle(color: Colors.white54),
        ),
        SizedBox(height: 30),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('CONSOLE DE MIXAGE', style: TextStyle(letterSpacing: 3, fontSize: 16)),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A1A), Color(0xFF0A0A0A)],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 20),
              _buildSlider(
                'IMMERSION',
                _immersion,
                (value) {
                  setState(() => _immersion = value);
                  _updateEffect('reverb', value);
                },
                unit: '%',
              ),
              _buildSlider(
                'SUB-BASS',
                _subBass,
                (value) {
                  setState(() => _subBass = value);
                  _updateEffect('bass', value);
                },
                unit: '%',
              ),
              _buildSlider(
                'BOOST VOLUME',
                _boostVolume,
                (value) {
                  setState(() => _boostVolume = value);
                  _updateEffect('volume', value);
                },
                unit: '%',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
