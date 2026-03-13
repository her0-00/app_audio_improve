# Cinema Audio Luxe - Lecteur Audio Premium iOS

Application iOS de lecture audio avec traitement DSP "Cinéma de Luxe" (EQ, Reverb 3D, Compresseur, Limiter).

## Architecture

- **Frontend**: Flutter (Dart) - Interface luxe (thème sombre/doré)
- **Backend Audio**: Swift natif avec AVAudioEngine
- **Communication**: MethodChannel Flutter ↔ Swift

## Fonctionnalités

### 3 Écrans Principaux

1. **Importateur**: Sélection fichiers audio (MP3, WAV, FLAC, M4A)
2. **Lecteur VIP**: Play/Pause, barre de progression
3. **Console de Mixage**: 3 sliders de contrôle DSP

### Chaîne DSP (Swift)

```
Audio → EQ Paramétrique → Reverb 3D → Compresseur → Limiter → Sortie
```

- **EQ**: Boost sub-bass (40Hz), clarté voix (1kHz), brillance (8kHz)
- **Reverb**: Large Hall avec mix ajustable (0-100%)
- **Volume Boost**: Gain jusqu'à +200% avec protection limiter

## Compilation (Sans Mac)

### Avec Codemagic

1. Push le code sur GitHub
2. Connecter le repo à [Codemagic](https://codemagic.io)
3. Le fichier `codemagic.yaml` configure automatiquement le build
4. Télécharger le `.app` généré

### Commandes locales (si Mac disponible)

```bash
flutter pub get
flutter build ios --release
```

## Structure des Fichiers

```
app__audio_improve/
├── lib/
│   └── main.dart                    # UI Flutter (3 écrans)
├── ios/
│   └── Runner/
│       ├── AppDelegate.swift        # Moteur audio DSP
│       └── Info.plist               # Permissions iOS
├── pubspec.yaml                     # Dépendances Flutter
└── codemagic.yaml                   # CI/CD config
```

## Dépendances

- `file_picker`: Import fichiers audio
- `path_provider`: Gestion chemins iOS

## Permissions iOS

- Accès fichiers (UISupportsDocumentBrowser)
- Audio en arrière-plan (UIBackgroundModes: audio)
- Partage de fichiers (UIFileSharingEnabled)
