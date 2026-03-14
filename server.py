from flask import Flask, jsonify, request, send_file
from flask_cors import CORS
import yt_dlp
import os
import json
import re
from pathlib import Path

app = Flask(__name__)
CORS(app)

VAULT = "Server_Audio_Vault"
os.makedirs(VAULT, exist_ok=True)

def clean(title):
    return re.sub(r'[\\//*?:"<>|]', "", title)

def fmt_dur(sec):
    if not sec:
        return "—"
    try:
        s = int(sec)
        m, s = divmod(s, 60)
        h, m = divmod(m, 60)
        return f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"
    except:
        return "—"

def detect_type(entry):
    t = (entry.get('title') or '').lower()
    d = entry.get('duration') or 0
    if any(k in t for k in ['full album', 'album complet', 'complete album']):
        return 'Album'
    if any(k in t for k in ['live', 'concert', 'session', 'festival']):
        return 'Live'
    if any(k in t for k in ['mix', 'playlist', 'compilation', 'best of', 'dj set']):
        return 'Mix'
    if d > 1800:
        return 'Album'
    if d > 1200:
        return 'Long'
    return 'Track'

SEARCH_MODES = {
    "titre": {"suffix": "official audio", "n": 25},
    "album": {"suffix": "full album", "n": 12},
    "live": {"suffix": "live concert", "n": 18},
    "mix": {"suffix": "mix", "n": 15},
    "instrumental": {"suffix": "instrumental version", "n": 20},
    "rarities": {"suffix": "rare demo unreleased", "n": 15},
}

@app.route('/api/search', methods=['POST'])
def search():
    data = request.json
    query = data.get('query', '').strip()
    mode = data.get('mode', 'titre')
    
    if not query:
        return jsonify({'error': 'Query required'}), 400
    
    cfg = SEARCH_MODES.get(mode, SEARCH_MODES["titre"])
    q = f"ytsearch{cfg['n']}:{query} {cfg['suffix']}"
    opts = {'extract_flat': True, 'quiet': True, 'no_warnings': True}
    results = []
    
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(q, download=False)
            for e in (info.get('entries') or []):
                if not e:
                    continue
                results.append({
                    'title': e.get('title', '—'),
                    'artist': e.get('uploader', '—'),
                    'url': e.get('url') or e.get('webpage_url', ''),
                    'duration': fmt_dur(e.get('duration')),
                    'type': detect_type(e),
                    'views': e.get('view_count', 0),
                    'id': e.get('id', ''),
                })
    except Exception as ex:
        return jsonify({'error': str(ex)}), 500
    
    return jsonify({'results': results})

@app.route('/api/download', methods=['POST'])
def download():
    data = request.json
    url = data.get('url', '')
    title = data.get('title', 'audio')
    fmt = data.get('format', 'FLAC')
    
    if not url:
        return jsonify({'error': 'URL required'}), 400
    
    print(f"Download request: {title} - Format: {fmt}")
    
    safe = clean(title)
    codec_map = {'FLAC': 'flac', 'MP3 320': 'mp3', 'AAC': 'aac', 'OGG': 'vorbis', 'OPUS': 'opus'}
    quality_map = {'FLAC': '0', 'MP3 320': '320', 'AAC': '256', 'OGG': '9', 'OPUS': '0'}
    ext_map = {'FLAC': 'flac', 'MP3 320': 'mp3', 'AAC': 'aac', 'OGG': 'ogg', 'OPUS': 'opus'}
    
    codec = codec_map.get(fmt, 'flac')
    quality = quality_map.get(fmt, '0')
    ext = ext_map.get(fmt, 'flac')
    tpl = f"{VAULT}/{safe}.%(ext)s"
    
    ffmpeg_extra = ['-af', 'aresample=resampler=swr', '-ar', '48000']
    if codec == 'flac':
        ffmpeg_extra += ['-compression_level', '8']
    if codec == 'mp3':
        ffmpeg_extra += ['-joint_stereo', '1', '-id3v2_version', '3']
    
    opts = {
        'format': 'bestaudio[ext=webm][acodec=opus]/bestaudio[ext=m4a]/bestaudio/best',
        'retries': 10,
        'fragment_retries': 10,
        'skip_unavailable_fragments': False,
        'postprocessors': [{
            'key': 'FFmpegExtractAudio',
            'preferredcodec': codec,
            'preferredquality': quality,
        }],
        'postprocessor_args': {'ffmpeg': ffmpeg_extra},
        'outtmpl': tpl,
        'quiet': False,
        'no_warnings': False,
        'http_headers': {
            'User-Agent': 'com.google.ios.youtube/19.09.3 (iPhone14,3; U; CPU iOS 15_6 like Mac OS X)',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'en-us,en;q=0.5',
            'Sec-Fetch-Mode': 'navigate',
        },
        'extractor_args': {
            'youtube': {
                'player_client': ['ios', 'android', 'web'],
                'player_skip': ['webpage', 'configs'],
            }
        },
    }
    
    try:
        print(f"Starting download: {url}")
        with yt_dlp.YoutubeDL(opts) as ydl:
            ydl.download([url])
        
        path = f"{VAULT}/{safe}.{ext}"
        if os.path.exists(path):
            print(f"Download successful: {path}")
            return jsonify({'success': True, 'file': f"{safe}.{ext}", 'path': path})
        else:
            print(f"File not found after download: {path}")
            return jsonify({'error': 'Download failed - file not found'}), 500
    except Exception as ex:
        print(f"Download error: {ex}")
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(ex)}), 500

@app.route('/api/file/<filename>', methods=['GET'])
def get_file(filename):
    safe = clean(filename)
    path = os.path.join(VAULT, safe)
    
    if os.path.exists(path):
        return send_file(path, as_attachment=True, download_name=safe)
    return jsonify({'error': 'File not found'}), 404

@app.route('/api/files', methods=['GET'])
def list_files():
    files = []
    if os.path.exists(VAULT):
        for f in os.listdir(VAULT):
            fpath = os.path.join(VAULT, f)
            if os.path.isfile(fpath):
                files.append({
                    'name': f,
                    'size': os.path.getsize(fpath),
                    'path': fpath
                })
    return jsonify({'files': files})

if __name__ == '__main__':
    print("=" * 60)
    print("Cinema Audio Luxe - Server Flask")
    print("=" * 60)
    print(f"Vault: {os.path.abspath(VAULT)}")
    print("Formats: FLAC, MP3 320, AAC, OGG, OPUS")
    print("=" * 60)
    app.run(host='0.0.0.0', port=8501, debug=True)
