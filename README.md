# Cinema Audio Luxe - Lecteur Audio Premium iOS

Application iOS de lecture audio avec traitement DSP "Cinéma de Luxe" (EQ, Reverb 3D, Compresseur, Limiter).

**Compatible**: iOS 14+ | **Testé sur**: iPhone XR avec iOS 18

## Architecture

- **Frontend**: Flutter (Dart) - Interface luxe (thème sombre/doré)
- **Backend Audio**: Swift natif avec AVAudioEngine
- **Communication**: MethodChannel Flutter ↔ Swift

## Fonctionnalités

### 3 Écrans Principaux

1. **Importateur**: Sélection fichiers audio (MP3, WAV, FLAC, M4A)
2. **Lecteur VIP**: Play/Pause, barre de progression avec temps MM:SS
3. **Console de Mixage**: 3 sliders de contrôle DSP

### Chaîne DSP (Swift)

```
Audio → EQ Paramétrique → Reverb 3D → Compresseur → Limiter → Sortie
```

- **EQ**: Boost sub-bass (40Hz), clarté voix (1kHz), brillance (8kHz)
- **Reverb**: Large Hall avec mix ajustable (0-100%)
- **Compresseur**: Threshold -20dB, ratio 2:1, protection dynamique
- **Volume Boost**: Gain jusqu'à +200% avec protection limiter

## Installation & Build

### Prérequis

- Flutter SDK (3.0+)
- Xcode 15+ (pour iOS 18)
- CocoaPods
- Mac avec macOS 13+

### Build Local (Mac)

```bash
# 1. Cloner et installer
git clone <repo>
cd app__audio_improve
flutter pub get

# 2. Préparer iOS
cd ios
pod install --repo-update
cd ..

# 3. Build Release
flutter build ios --release

# 4. Ouvrir dans Xcode pour signing
open ios/Runner.xcworkspace
```

Dans Xcode:
- Sélectionner "Runner" → Signing & Capabilities
- Choisir votre Team ID
- Connecter iPhone XR en USB
- Build & Run (Cmd+R)

### Build avec Codemagic (Sans Mac)

1. **Push le code sur GitHub**
   ```bash
   git add .
   git commit -m "Cinema Audio Luxe iOS"
   git push origin main
   ```

2. **Connecter à Codemagic**
   - Aller sur [codemagic.io](https://codemagic.io)
   - Connecter votre repo GitHub
   - Sélectionner ce projet

3. **Configuration automatique**
   - Le fichier `codemagic.yaml` configure tout
   - Build démarre automatiquement
   - IPA généré et envoyé par email

4. **Installer sur iPhone XR**
   - Télécharger le `.ipa` depuis l'email
   - Utiliser Xcode ou Apple Configurator 2
   - Ou utiliser TestFlight pour distribution

## Structure des Fichiers

```
app__audio_improve/
├── lib/
│   └── main.dart                    # UI Flutter (3 écrans + position tracking)
├── ios/
│   └── Runner/
│       ├── AppDelegate.swift        # Moteur audio DSP complet
│       ├── Info.plist               # Permissions iOS 18
│       └── GeneratedPluginRegistrant.m
├── pubspec.yaml                     # Dépendances Flutter
├── codemagic.yaml                   # CI/CD config
├── build_ios.sh                     # Script build Mac/Linux
├── build_ios.bat                    # Script prep Windows
└── README.md                        # Ce fichier
```

## Dépendances

- `file_picker: ^5.5.0` - Import fichiers audio (version stable iOS)
- `path_provider: ^2.1.1` - Gestion chemins iOS

## Permissions iOS 18

Automatiquement configurées dans `Info.plist`:

- ✅ Accès fichiers (UISupportsDocumentBrowser)
- ✅ Audio en arrière-plan (UIBackgroundModes: audio)
- ✅ Partage de fichiers (UIFileSharingEnabled)
- ✅ Microphone (NSMicrophoneUsageDescription)
- ✅ Documents (NSDocumentsFolderUsageDescription)

## Utilisation

### Écran 1: Importateur
- Appuyer sur "IMPORTER UN FICHIER"
- Sélectionner un fichier audio (MP3, WAV, FLAC, M4A)
- Fichier chargé automatiquement

### Écran 2: Lecteur VIP
- **Play/Pause**: Bouton cercle doré
- **Barre de progression**: Glisser pour chercher
- **Temps**: Affichage MM:SS courant / total
- **Console de Mixage**: Bouton pour accéder aux effets

### Écran 3: Console de Mixage
- **IMMERSION (REVERB)**: 0-100% (Large Hall)
- **SUB-BASS (40Hz)**: 0-100% (Boost graves)
- **BOOST VOLUME**: 0-100% (+0 à +200%)
- **RETOUR**: Revenir au lecteur

## Troubleshooting

### L'app ne démarre pas
```bash
flutter clean
flutter pub get
cd ios && rm -rf Pods Podfile.lock && pod install --repo-update && cd ..
flutter run
```

### Erreur "Audio engine failed"
- Vérifier que le fichier audio est valide
- Vérifier les permissions dans Settings > Cinema Audio Luxe

### Pas de son
- Vérifier le volume de l'iPhone
- Vérifier que l'audio n'est pas en mode silencieux
- Redémarrer l'app

### Build Xcode échoue
```bash
cd ios
rm -rf Pods Podfile.lock .symlinks/ Flutter/Flutter.framework Flutter/Flutter.podspec
pod install --repo-update
cd ..
flutter build ios --release
```

### Codemagic build échoue
- Vérifier que file_picker version est ^5.5.0 (stable iOS)
- Vérifier que codemagic.yaml a le clean step
- Vérifier les logs Codemagic pour détails

## Spécifications Techniques

| Aspect | Détail |
|--------|--------|
| **Plateforme** | iOS 14+ (testé iOS 18) |
| **Appareils** | iPhone XR et supérieurs |
| **Formats Audio** | MP3, WAV, FLAC, M4A |
| **Fréquence Échantillonnage** | 44.1kHz - 48kHz |
| **Bandes EQ** | 3 (40Hz, 1kHz, 8kHz) |
| **Reverb** | Large Hall (AVAudioUnitReverb) |
| **Compresseur** | Threshold -20dB, Ratio 2:1 |
| **Latence Audio** | < 50ms |

## Développement

### Ajouter un nouvel effet DSP

1. **Ajouter dans AppDelegate.swift**:
```swift
private let newEffect = AVAudioUnit...()
engine.attach(newEffect)
engine.connect(..., to: newEffect, format: nil)
```

2. **Ajouter le case dans setEffect**:
```swift
case "newEffect":
  newEffect.property = value
```

3. **Ajouter le slider dans main.dart**:
```dart
_buildSlider('NEW EFFECT', _newEffect, (value) {
  setState(() => _newEffect = value);
  _updateEffect('newEffect', value);
})
```

## Corrections Appliquées

### Flutter UI (lib/main.dart)
- ✅ Position tracking en temps réel avec Timer
- ✅ Affichage temps MM:SS
- ✅ Vérification limites slider (.clamp)
- ✅ Bouton retour sur console de mixage
- ✅ Gestion erreurs améliorée

### Audio Engine (AppDelegate.swift)
- ✅ AVAudioSession setup correct
- ✅ AVAudioUnitCompressor ajouté
- ✅ Gestion erreurs avec try-catch
- ✅ Logging debug complet
- ✅ Validation frames seek

### iOS Configuration
- ✅ iOS 14.0 minimum (était 12.0)
- ✅ iOS 18 compatible
- ✅ Toutes permissions configurées
- ✅ Audio background mode activé

### Build System
- ✅ file_picker downgrade à 5.5.0 (stable iOS)
- ✅ Codemagic clean step ajouté
- ✅ Verbose build logging
- ✅ Podfile iOS 14.0

## Support

Pour les problèmes:
1. Vérifier les logs: `flutter logs`
2. Vérifier la console Xcode
3. Tester avec un fichier audio différent
4. Consulter la section Troubleshooting

## Licence

Propriétaire - Cinema Audio Luxe © 2024

## Auteur

Développé pour iOS 18 iPhone XR
