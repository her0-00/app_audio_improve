# Système de Téléchargement Audio - Cinema Audio Luxe

## Architecture

```
iPhone XR (Flutter App)
    ↓ HTTP Requests
    ↓
Windows PC (Flask Server)
    ↓ yt-dlp
    ↓
YouTube / Sources Audio
    ↓ Download
    ↓
Server_Audio_Vault/ (Fichiers locaux)
    ↓ HTTP Response
    ↓
iPhone XR (Affichage + Lecture)
```

## Installation du Serveur

### 1. Prérequis
- Python 3.8+
- FFmpeg (pour la conversion audio)
- Connexion réseau (iPhone et PC sur le même réseau)

### 2. Installation des dépendances

```bash
cd app__audio_improve
pip install -r requirements.txt
```

### 3. Démarrage du serveur

**Windows :**
```bash
start_server.bat
```

**Mac/Linux :**
```bash
python server.py
```

Le serveur démarre sur `http://0.0.0.0:5000`

### 4. Configuration de l'adresse IP

Modifie `lib/main.dart` ligne 17 :
```dart
const String SERVER_URL = 'http://192.168.1.100:5000';
```

Remplace `192.168.1.100` par l'adresse IP de ton PC sur le réseau local.

**Pour trouver ton IP :**
- Windows : `ipconfig` → cherche "IPv4 Address"
- Mac/Linux : `ifconfig` → cherche "inet"

## Utilisation

### Écran d'accueil
1. **IMPORTER UN FICHIER** : Sélectionner un fichier audio local
2. **TÉLÉCHARGER** : Accéder au système de téléchargement

### Écran de téléchargement
1. Entrer un terme de recherche (artiste, titre, album)
2. Sélectionner le mode (Titre, Album, Live, Mix, Instrumental, Raretés)
3. Choisir le format audio (FLAC, MP3 320, AAC, OGG, OPUS)
4. Cliquer "RECHERCHER"
5. Cliquer "↓ FORMAT" pour télécharger

### Lecteur VIP
- **Play/Pause** : Bouton cercle doré
- **Barre de progression** : Glisser pour chercher
- **Temps** : Affichage MM:SS
- **CONSOLE DE MIXAGE** : Accéder aux effets DSP

## API REST

### POST /api/search
Recherche des fichiers audio

**Request :**
```json
{
  "query": "The Beatles",
  "mode": "titre"
}
```

**Response :**
```json
{
  "results": [
    {
      "title": "The Beatles - Hey Jude",
      "artist": "The Beatles",
      "url": "https://www.youtube.com/watch?v=...",
      "duration": "7:11",
      "type": "Track",
      "views": 1000000,
      "id": "..."
    }
  ]
}
```

### POST /api/download
Télécharge et convertit un fichier audio

**Request :**
```json
{
  "url": "https://www.youtube.com/watch?v=...",
  "title": "The Beatles - Hey Jude",
  "format": "FLAC"
}
```

**Response :**
```json
{
  "success": true,
  "file": "The Beatles - Hey Jude.flac",
  "path": "Server_Audio_Vault/The Beatles - Hey Jude.flac"
}
```

### GET /api/files
Liste tous les fichiers téléchargés

**Response :**
```json
{
  "files": [
    {
      "name": "The Beatles - Hey Jude.flac",
      "size": 45000000,
      "path": "Server_Audio_Vault/The Beatles - Hey Jude.flac"
    }
  ]
}
```

### GET /api/file/<filename>
Télécharge un fichier spécifique

## Formats Audio Supportés

| Format | Codec | Qualité | Extension |
|--------|-------|---------|-----------|
| FLAC | FLAC | Lossless | .flac |
| MP3 320 | MP3 | 320 kbps | .mp3 |
| AAC | AAC | 256 kbps | .aac |
| OGG | Vorbis | 9 | .ogg |
| OPUS | Opus | 0 | .opus |

## Modes de Recherche

| Mode | Suffixe | Résultats |
|------|---------|-----------|
| Titre | "official audio" | 25 |
| Album | "full album" | 12 |
| Live | "live concert" | 18 |
| Mix | "mix" | 15 |
| Instrumental | "instrumental version" | 20 |
| Raretés | "rare demo unreleased" | 15 |

## Dossier de Stockage

Les fichiers téléchargés sont stockés dans `Server_Audio_Vault/`

**Exemple :**
```
Server_Audio_Vault/
├── The Beatles - Hey Jude.flac
├── Pink Floyd - Comfortably Numb.mp3
├── David Bowie - Space Oddity.aac
└── ...
```

## Troubleshooting

### "Connection refused"
- Vérifier que le serveur est démarré
- Vérifier l'adresse IP dans `lib/main.dart`
- Vérifier que l'iPhone et le PC sont sur le même réseau

### "Download failed"
- Vérifier la connexion internet
- Vérifier que FFmpeg est installé
- Vérifier que yt-dlp est à jour : `pip install --upgrade yt-dlp`

### "File not found"
- Vérifier que le fichier existe dans `Server_Audio_Vault/`
- Vérifier les permissions du dossier

### Erreur FFmpeg
```bash
# Installer FFmpeg
# Windows : https://ffmpeg.org/download.html
# Mac : brew install ffmpeg
# Linux : sudo apt install ffmpeg
```

## Performance

- **Recherche** : ~2-5 secondes
- **Téléchargement** : Dépend de la qualité et de la connexion
  - FLAC : ~30-60 secondes (pour 3-5 min de musique)
  - MP3 320 : ~15-30 secondes
  - AAC : ~10-20 secondes

## Sécurité

- Le serveur n'accepte que les requêtes JSON
- Les noms de fichiers sont nettoyés (caractères spéciaux supprimés)
- Les fichiers sont stockés localement
- Pas de données sensibles transmises

## Limitations

- Pas de authentification (serveur local uniquement)
- Pas de limite de taille de fichier
- Pas de gestion des quotas
- Pas de suppression automatique des fichiers

## Support

Pour les problèmes :
1. Vérifier les logs du serveur Flask
2. Vérifier les logs Flutter : `flutter logs`
3. Vérifier la console Xcode (iOS)
