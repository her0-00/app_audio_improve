import streamlit as st
import yt_dlp
import os
import re
import json

# ── VAULT ──────────────────────────────────────────────────────────────
SERVER_VAULT = "Server_Audio_Vault"
os.makedirs(SERVER_VAULT, exist_ok=True)

# ── PAGE CONFIG ────────────────────────────────────────────────────────
st.set_page_config(
    page_title="ATELIER SONORE",
    page_icon="◈",
    layout="wide",
    initial_sidebar_state="collapsed"
)

# ── MASTER CSS ─────────────────────────────────────────────────────────
st.markdown("""
<style>
@import url('https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,300;0,400;0,600;1,300;1,400&family=Space+Mono:wght@400;700&family=Raleway:wght@200;300;400;600;700;900&display=swap');

:root {
  --gold:        #C9A84C;
  --gold-bright: #F0C862;
  --gold-dim:    #7A6128;
  --obsidian:    #07070A;
  --surface-1:   #0E0E14;
  --surface-2:   #141420;
  --surface-3:   #1C1C2E;
  --surface-4:   #24243A;
  --text-primary: #F0EDE6;
  --text-muted:   #6B6B8A;
  --text-subtle:  #3A3A5C;
  --accent-red:   #C0392B;
  --accent-teal:  #1ABC9C;
  --r:            16px;
}

* { box-sizing: border-box; }

/* ── GLOBAL ── */
.stApp {
  background: var(--obsidian) !important;
  font-family: 'Raleway', sans-serif !important;
  color: var(--text-primary) !important;
  min-height: 100vh;
  overflow-x: hidden;
}

/* animated grain overlay */
.stApp::before {
  content: '';
  position: fixed; inset: 0;
  background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 200 200' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.75' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)' opacity='1'/%3E%3C/svg%3E");
  opacity: 0.025;
  pointer-events: none;
  z-index: 0;
}

/* aurora background */
.stApp::after {
  content: '';
  position: fixed;
  top: -30%; left: -20%;
  width: 80vw; height: 80vh;
  background: radial-gradient(ellipse, rgba(201,168,76,0.06) 0%, transparent 70%);
  pointer-events: none;
  z-index: 0;
  animation: aurora 12s ease-in-out infinite alternate;
}
@keyframes aurora {
  0%   { transform: translate(0,0) scale(1); }
  50%  { transform: translate(15vw, 10vh) scale(1.2); }
  100% { transform: translate(-5vw, 20vh) scale(0.9); }
}

#MainMenu, footer, header { visibility: hidden !important; }
.block-container { padding: 0 !important; max-width: 100% !important; }
section[data-testid="stSidebar"] { display: none !important; }

/* ── HERO HEADER ── */
.hero {
  position: relative;
  text-align: center;
  padding: 56px 40px 36px;
  overflow: hidden;
}
.hero-eyebrow {
  font-family: 'Space Mono', monospace;
  font-size: 10px;
  color: var(--gold-dim);
  letter-spacing: 6px;
  text-transform: uppercase;
  margin-bottom: 16px;
}
.hero-title {
  font-family: 'Cormorant Garamond', serif;
  font-size: clamp(3.5rem, 8vw, 7rem);
  font-weight: 300;
  font-style: italic;
  color: var(--text-primary);
  line-height: 0.9;
  margin: 0;
  letter-spacing: -0.02em;
}
.hero-title span {
  color: var(--gold);
  font-weight: 600;
  font-style: normal;
}
.hero-sub {
  font-family: 'Space Mono', monospace;
  font-size: 9px;
  color: var(--text-muted);
  letter-spacing: 4px;
  text-transform: uppercase;
  margin-top: 18px;
}
.hero-line {
  width: 60px; height: 1px;
  background: linear-gradient(90deg, transparent, var(--gold), transparent);
  margin: 20px auto 0;
}

/* ── WAVEFORM ANIMATION ── */
.waveform {
  display: flex; align-items: center; justify-content: center;
  gap: 3px; height: 32px; margin: 8px 0;
}
.waveform-bar {
  width: 3px; border-radius: 2px;
  background: var(--gold);
  animation: wave 1.2s ease-in-out infinite;
  opacity: 0.5;
}
.waveform-bar:nth-child(1)  { height: 8px;  animation-delay: 0s; }
.waveform-bar:nth-child(2)  { height: 18px; animation-delay: 0.1s; }
.waveform-bar:nth-child(3)  { height: 26px; animation-delay: 0.2s; }
.waveform-bar:nth-child(4)  { height: 20px; animation-delay: 0.3s; }
.waveform-bar:nth-child(5)  { height: 14px; animation-delay: 0.4s; }
.waveform-bar:nth-child(6)  { height: 22px; animation-delay: 0.5s; }
.waveform-bar:nth-child(7)  { height: 28px; animation-delay: 0.6s; }
.waveform-bar:nth-child(8)  { height: 16px; animation-delay: 0.7s; }
.waveform-bar:nth-child(9)  { height: 10px; animation-delay: 0.8s; }
.waveform-bar:nth-child(10) { height: 20px; animation-delay: 0.9s; }
.waveform-bar:nth-child(11) { height: 26px; animation-delay: 1.0s; }
.waveform-bar:nth-child(12) { height: 12px; animation-delay: 1.1s; }
@keyframes wave {
  0%, 100% { transform: scaleY(0.5); opacity: 0.3; }
  50%       { transform: scaleY(1.3); opacity: 0.8; }
}

/* ── SEARCH ZONE ── */
.search-container {
  max-width: 720px;
  margin: 0 auto 8px;
  padding: 0 24px;
  position: relative;
  z-index: 10;
}
.stTextInput > div > div > input {
  background: var(--surface-2) !important;
  border: 1px solid var(--text-subtle) !important;
  border-radius: 60px !important;
  color: var(--text-primary) !important;
  font-family: 'Raleway', sans-serif !important;
  font-size: 15px !important;
  font-weight: 400 !important;
  padding: 18px 28px !important;
  text-align: center;
  letter-spacing: 0.5px;
  transition: all 0.4s cubic-bezier(0.16,1,0.3,1) !important;
  backdrop-filter: blur(20px);
}
.stTextInput > div > div > input:focus {
  border-color: var(--gold) !important;
  box-shadow: 0 0 0 1px var(--gold-dim), 0 8px 40px rgba(201,168,76,0.15) !important;
  background: var(--surface-3) !important;
}
.stTextInput > div > div > input::placeholder { color: var(--text-subtle) !important; }
.stTextInput > label { display: none !important; }

/* ── FILTER PILLS ── */
.filter-row {
  display: flex; gap: 8px; justify-content: center; flex-wrap: wrap;
  padding: 0 24px; margin-bottom: 32px;
}
.filter-pill {
  font-family: 'Space Mono', monospace;
  font-size: 9px; letter-spacing: 2px; text-transform: uppercase;
  padding: 7px 16px; border-radius: 20px; cursor: pointer;
  border: 1px solid var(--text-subtle);
  color: var(--text-muted);
  background: transparent;
  transition: all 0.25s ease;
}
.filter-pill.active, .filter-pill:hover {
  background: var(--gold); color: var(--obsidian);
  border-color: var(--gold); font-weight: 700;
}

/* ── TABS ── */
.stTabs [data-baseweb="tab-list"] {
  background: transparent !important;
  border-bottom: 1px solid var(--text-subtle) !important;
  gap: 0 !important; padding: 0 40px !important;
  justify-content: flex-start !important;
}
.stTabs [data-baseweb="tab"] {
  background: transparent !important;
  border-bottom: 2px solid transparent !important;
  border-radius: 0 !important;
  color: var(--text-muted) !important;
  font-family: 'Space Mono', monospace !important;
  font-size: 9px !important; letter-spacing: 2px !important;
  text-transform: uppercase !important;
  padding: 12px 24px !important;
  margin-bottom: -1px !important;
  transition: all 0.2s !important;
}
.stTabs [aria-selected="true"] {
  color: var(--gold) !important;
  border-bottom: 2px solid var(--gold) !important;
}
.stTabs [data-baseweb="tab-border"] { display: none !important; }
.stTabs [data-baseweb="tab-panel"] { padding: 0 !important; }

/* ── RESULTS LAYOUT ── */
.results-wrap {
  padding: 0 32px;
  max-width: 1400px;
  margin: 0 auto;
}
.results-meta {
  font-family: 'Space Mono', monospace;
  font-size: 9px; letter-spacing: 3px; text-transform: uppercase;
  color: var(--text-subtle); margin-bottom: 20px; padding: 0 4px;
}
.results-meta b { color: var(--gold); }

/* ── TRACK CARD ── */
.track-card {
  display: grid;
  grid-template-columns: 28px 1fr auto;
  align-items: center;
  gap: 16px;
  padding: 14px 20px;
  border-radius: 10px;
  background: transparent;
  border: 1px solid transparent;
  transition: all 0.3s cubic-bezier(0.16,1,0.3,1);
  cursor: pointer;
  margin-bottom: 2px;
  position: relative;
  overflow: hidden;
}
.track-card::before {
  content: '';
  position: absolute; left: 0; top: 0; bottom: 0; width: 0;
  background: linear-gradient(90deg, rgba(201,168,76,0.08), transparent);
  transition: width 0.3s ease;
}
.track-card:hover {
  background: var(--surface-2);
  border-color: var(--text-subtle);
}
.track-card:hover::before { width: 100%; }
.track-num {
  font-family: 'Space Mono', monospace;
  font-size: 11px; color: var(--text-subtle); text-align: center;
}
.track-info { min-width: 0; }
.track-title {
  font-family: 'Raleway', sans-serif;
  font-size: 14px; font-weight: 600;
  color: var(--text-primary);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  margin-bottom: 3px;
}
.track-artist {
  font-family: 'Space Mono', monospace;
  font-size: 9px; letter-spacing: 1.5px; text-transform: uppercase;
  color: var(--text-muted);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.track-right {
  display: flex; align-items: center; gap: 12px; flex-shrink: 0;
}
.track-duration {
  font-family: 'Space Mono', monospace;
  font-size: 10px; color: var(--text-muted); letter-spacing: 1px;
  min-width: 38px; text-align: right;
}
.track-badge {
  font-family: 'Space Mono', monospace;
  font-size: 8px; letter-spacing: 1.5px; text-transform: uppercase;
  padding: 3px 8px; border-radius: 4px;
  border: 1px solid;
}
.badge-track    { color: var(--gold);       border-color: var(--gold-dim);       background: rgba(201,168,76,0.06); }
.badge-album    { color: #9B59B6;            border-color: rgba(155,89,182,0.4);  background: rgba(155,89,182,0.06); }
.badge-live     { color: var(--accent-red);  border-color: rgba(192,57,43,0.4);   background: rgba(192,57,43,0.06); }
.badge-mix      { color: var(--accent-teal); border-color: rgba(26,188,156,0.4);  background: rgba(26,188,156,0.06); }
.badge-long     { color: #E67E22;            border-color: rgba(230,126,34,0.4);  background: rgba(230,126,34,0.06); }
.badge-default  { color: var(--text-muted);  border-color: var(--text-subtle);    background: transparent; }

/* ── BUTTONS ── */
.stButton > button {
  font-family: 'Space Mono', monospace !important;
  font-size: 9px !important; letter-spacing: 2.5px !important;
  text-transform: uppercase !important;
  border-radius: 6px !important;
  padding: 9px 14px !important;
  width: 100%; border: none !important;
  transition: all 0.25s cubic-bezier(0.16,1,0.3,1) !important;
  position: relative !important; overflow: hidden !important;
}
/* primary = search */
div[data-testid="stButton"]:has(button[kind="primary"]) button,
.stButton > button[kind="primary"] {
  background: var(--gold) !important;
  color: var(--obsidian) !important; font-weight: 700 !important;
}
.stButton > button {
  background: var(--surface-3) !important;
  color: var(--gold) !important;
  border: 1px solid var(--gold-dim) !important;
}
.stButton > button:hover {
  background: var(--gold) !important;
  color: var(--obsidian) !important;
  transform: translateY(-1px) !important;
  box-shadow: 0 6px 24px rgba(201,168,76,0.3) !important;
}

/* ── SECTION DIVIDER ── */
.section-divider {
  display: flex; align-items: center; gap: 16px;
  padding: 24px 40px 16px;
}
.divider-label {
  font-family: 'Space Mono', monospace;
  font-size: 9px; letter-spacing: 4px; text-transform: uppercase;
  color: var(--text-subtle); white-space: nowrap;
}
.divider-line {
  flex: 1; height: 1px;
  background: linear-gradient(90deg, var(--text-subtle), transparent);
}

/* ── DOWNLOAD MASTERWORK ── */
.masterwork-zone {
  margin: 48px 32px 40px;
  padding: 40px;
  border-radius: 20px;
  background: linear-gradient(135deg,
    rgba(201,168,76,0.06) 0%,
    rgba(201,168,76,0.02) 50%,
    rgba(14,14,20,0.8) 100%
  );
  border: 1px solid rgba(201,168,76,0.2);
  text-align: center;
  position: relative; overflow: hidden;
}
.masterwork-zone::before {
  content: '◈';
  position: absolute; top: 20px; right: 32px;
  font-size: 60px; color: rgba(201,168,76,0.04);
  font-family: 'Cormorant Garamond', serif;
}
.masterwork-title {
  font-family: 'Cormorant Garamond', serif;
  font-size: 2rem; font-weight: 300; font-style: italic;
  color: var(--text-primary); margin-bottom: 6px;
}
.masterwork-sub {
  font-family: 'Space Mono', monospace;
  font-size: 9px; letter-spacing: 3px; text-transform: uppercase;
  color: var(--gold); margin-bottom: 28px;
}
.stDownloadButton > button {
  background: linear-gradient(135deg, var(--gold) 0%, var(--gold-dim) 100%) !important;
  color: var(--obsidian) !important;
  font-family: 'Space Mono', monospace !important;
  font-size: 10px !important; letter-spacing: 3px !important;
  text-transform: uppercase !important; font-weight: 700 !important;
  border-radius: 60px !important; border: none !important;
  padding: 16px 48px !important;
  transition: all 0.3s ease !important;
  box-shadow: 0 4px 30px rgba(201,168,76,0.25) !important;
}
.stDownloadButton > button:hover {
  transform: translateY(-2px) !important;
  box-shadow: 0 12px 40px rgba(201,168,76,0.45) !important;
}

/* ── SPINNER / PROGRESS ── */
.stSpinner > div { border-top-color: var(--gold) !important; }

/* ── TOAST ── */
[data-testid="stToast"] {
  background: var(--surface-3) !important;
  border: 1px solid var(--gold-dim) !important;
  border-radius: 12px !important;
  font-family: 'Raleway', sans-serif !important;
  color: var(--text-primary) !important;
}

/* ── COLUMNS ALIGNMENT ── */
[data-testid="stHorizontalBlock"] { align-items: center !important; }

/* ── STATS BAR ── */
.stats-bar {
  display: flex; justify-content: center; gap: 48px;
  padding: 20px 40px 0;
  margin-bottom: 32px;
}
.stat-item { text-align: center; }
.stat-value {
  font-family: 'Cormorant Garamond', serif;
  font-size: 2rem; font-weight: 600;
  color: var(--gold); line-height: 1;
}
.stat-label {
  font-family: 'Space Mono', monospace;
  font-size: 8px; letter-spacing: 2px; text-transform: uppercase;
  color: var(--text-subtle); margin-top: 4px;
}

/* ── FORMAT SELECTOR ── */
.format-selector {
  display: flex; gap: 6px; justify-content: center;
  margin-bottom: 24px;
}
.stRadio > div {
  display: flex !important; gap: 6px !important; justify-content: center !important;
  flex-direction: row !important;
}
.stRadio [data-testid="stMarkdownContainer"] p {
  font-family: 'Space Mono', monospace !important;
  font-size: 9px !important; letter-spacing: 2px !important;
  text-transform: uppercase !important;
}
.stRadio > div > label {
  background: var(--surface-2) !important;
  border: 1px solid var(--text-subtle) !important;
  border-radius: 6px !important; padding: 7px 14px !important;
  cursor: pointer !important; transition: all 0.2s !important;
}
.stRadio > div > label:has(input:checked) {
  background: var(--gold) !important;
  border-color: var(--gold) !important;
  color: var(--obsidian) !important;
}
.stRadio > div > label > div:first-child { display: none !important; }

/* scrollbar */
::-webkit-scrollbar { width: 3px; height: 3px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: var(--text-subtle); border-radius: 2px; }
::-webkit-scrollbar-thumb:hover { background: var(--gold-dim); }
</style>
""", unsafe_allow_html=True)

# ── SESSION STATE ──────────────────────────────────────────────────────
defaults = {
    'results': [],
    'active_mode': 0,
    'ready_path': None,
    'ready_name': None,
    'total_downloads': 0,
}
for k, v in defaults.items():
    if k not in st.session_state:
        st.session_state[k] = v

# ── UTILITIES ──────────────────────────────────────────────────────────
def clean(title):
    return re.sub(r'[\\/*?:"<>|]', "", title)

def fmt_dur(sec):
    if not sec:
        return "—"
    try:
        s = int(sec); m, s = divmod(s, 60); h, m = divmod(m, 60)
        return f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"
    except:
        return "—"

def badge_class(entry_type):
    return {
        "Track": "badge-track",
        "Album": "badge-album",
        "Live":  "badge-live",
        "Mix":   "badge-mix",
        "Long":  "badge-long",
    }.get(entry_type, "badge-default")

def detect_type(entry):
    t = (entry.get('title') or '').lower()
    d = entry.get('duration') or 0
    if any(k in t for k in ['full album', 'album complet', 'complete album']): return 'Album'
    if any(k in t for k in ['live', 'concert', 'session', 'festival']):       return 'Live'
    if any(k in t for k in ['mix', 'playlist', 'compilation', 'best of', 'dj set']): return 'Mix'
    if d > 1800: return 'Album'
    if d > 1200: return 'Long'
    return 'Track'

# ── SEARCH ENGINE ──────────────────────────────────────────────────────
SEARCH_MODES = {
    "titre":        {"label": "◈ Titre",        "suffix": "official audio",       "n": 25},
    "album":        {"label": "◎ Album",         "suffix": "full album",           "n": 12},
    "live":         {"label": "◉ Live",          "suffix": "live concert",         "n": 18},
    "mix":          {"label": "⊕ Mix / DJ",      "suffix": "mix",                  "n": 15},
    "instrumental": {"label": "◌ Instrumental",  "suffix": "instrumental version", "n": 20},
    "rarities":     {"label": "◇ Raretés",       "suffix": "rare demo unreleased", "n": 15},
}

def search(query: str, mode: str) -> list:
    cfg = SEARCH_MODES.get(mode, SEARCH_MODES["titre"])
    q = f"ytsearch{cfg['n']}:{query} {cfg['suffix']}"
    opts = {'extract_flat': True, 'quiet': True, 'no_warnings': True}
    results = []
    with yt_dlp.YoutubeDL(opts) as ydl:
        try:
            info = ydl.extract_info(q, download=False)
            for e in (info.get('entries') or []):
                if not e: continue
                results.append({
                    'title':    e.get('title', '—'),
                    'artist':   e.get('uploader', '—'),
                    'url':      e.get('url') or e.get('webpage_url', ''),
                    'dur':      fmt_dur(e.get('duration')),
                    'type':     detect_type(e),
                    'views':    e.get('view_count', 0),
                    'id':       e.get('id', ''),
                })
        except Exception as ex:
            st.error(f"Erreur de recherche : {ex}")
    return results

def download(url: str, title: str, fmt: str) -> tuple:
    safe = clean(title)
    codec_map   = {'FLAC': 'flac', 'MP3 320': 'mp3', 'AAC': 'aac', 'OGG': 'vorbis', 'OPUS': 'opus'}
    quality_map = {'FLAC': '0',    'MP3 320': '320', 'AAC': '256', 'OGG': '9',       'OPUS': '0'}
    ext_map     = {'FLAC': 'flac', 'MP3 320': 'mp3', 'AAC': 'aac', 'OGG': 'ogg',     'OPUS': 'opus'}
    mime_map    = {'flac': 'audio/flac', 'mp3': 'audio/mpeg', 'aac': 'audio/aac',
                   'ogg': 'audio/ogg',   'opus': 'audio/opus'}

    codec   = codec_map.get(fmt, 'flac')
    quality = quality_map.get(fmt, '0')
    ext     = ext_map.get(fmt, 'flac')
    tpl     = f"{SERVER_VAULT}/{safe}.%(ext)s"

    # ── FFmpeg args anti-glitch ──────────────────────────────────────────
    # Cause principale des "sauts" : flux DASH fragmenté mal reconstitué,
    # ou ré-échantillonnage approximatif lors de la conversion.
    # Solutions :
    # 1. Priorité au flux opus/m4a continu (non-DASH) → évite les segments
    # 2. aresample=resampler=swr → ré-échantillonnage haute qualité
    # 3. 48000 Hz → fréquence native YouTube, zéro conversion approximative
    # 4. retries/fragment_retries élevés → pas de segments corrompus
    # 5. skip_unavailable_fragments=False → on refuse les fichiers incomplets

    ffmpeg_extra = ['-af', 'aresample=resampler=swr', '-ar', '48000']
    if codec == 'flac':
        ffmpeg_extra += ['-compression_level', '8']
    if codec == 'mp3':
        ffmpeg_extra += ['-joint_stereo', '1', '-id3v2_version', '3']

    opts = {
        'format': (
            'bestaudio[ext=webm][acodec=opus]'
            '/bestaudio[ext=m4a]'
            '/bestaudio/best'
        ),
        'retries': 10,
        'fragment_retries': 10,
        'skip_unavailable_fragments': False,
        'postprocessors': [{
            'key': 'FFmpegExtractAudio',
            'preferredcodec': codec,
            'preferredquality': quality,
        }],
        'postprocessor_args': {
            'ffmpeg': ffmpeg_extra,
        },
        'outtmpl': tpl,
        'quiet': True,
        'no_warnings': True,
    }

    with yt_dlp.YoutubeDL(opts) as ydl:
        ydl.download([url])

    path = f"{SERVER_VAULT}/{safe}.{ext}"
    return path, f"{safe}.{ext}", mime_map.get(ext, 'audio/flac')

# ── HERO ───────────────────────────────────────────────────────────────
st.markdown("""
<div class="hero">
  <div class="hero-eyebrow">Atelier Sonore · Ultra Haute Fidélité</div>
  <h1 class="hero-title">Studio<br><span>Cinéma</span></h1>
  <div class="waveform">
    <div class="waveform-bar"></div><div class="waveform-bar"></div>
    <div class="waveform-bar"></div><div class="waveform-bar"></div>
    <div class="waveform-bar"></div><div class="waveform-bar"></div>
    <div class="waveform-bar"></div><div class="waveform-bar"></div>
    <div class="waveform-bar"></div><div class="waveform-bar"></div>
    <div class="waveform-bar"></div><div class="waveform-bar"></div>
  </div>
  <div class="hero-sub">Extraction · Mastering · Lossless</div>
  <div class="hero-line"></div>
</div>
""", unsafe_allow_html=True)

# ── SEARCH ZONE ────────────────────────────────────────────────────────
with st.container():
    c1, c2, c3 = st.columns([1, 5, 1])
    with c2:
        query = st.text_input("", placeholder="Artiste, titre, album, ambiance, époque...", label_visibility="collapsed")

# ── FORMAT SELECTOR ────────────────────────────────────────────────────
with st.container():
    fc1, fc2, fc3 = st.columns([1, 4, 1])
    with fc2:
        audio_format = st.radio(
            "Format",
            ["FLAC", "MP3 320", "AAC", "OGG", "OPUS"],
            horizontal=True,
            label_visibility="collapsed",
            index=0,
        )

# ── TABS / MODES ───────────────────────────────────────────────────────
mode_keys   = list(SEARCH_MODES.keys())
mode_labels = [SEARCH_MODES[k]["label"] for k in mode_keys]
tabs = st.tabs(mode_labels)

for i, (tab, mode_key) in enumerate(zip(tabs, mode_keys)):
    with tab:
        # padding around results
        p1, content_col, p2 = st.columns([1, 20, 1])
        with content_col:
            bc1, bc2, bc3 = st.columns([1, 2, 1])
            with bc2:
                if st.button("RECHERCHER", key=f"srch_{mode_key}"):
                    if query.strip():
                        with st.spinner("Analyse des sources sonores…"):
                            st.session_state.results  = search(query.strip(), mode_key)
                            st.session_state.active_mode = i
                            st.session_state.ready_path  = None
                    else:
                        st.toast("Entrez un terme de recherche", icon="⚠️")

            results = st.session_state.results
            is_active = st.session_state.active_mode == i

            if results and is_active:
                st.markdown(f"""
                    <div style="height:24px"></div>
                    <div class="results-meta">
                        <b>{len(results)}</b> œuvres trouvées · {SEARCH_MODES[mode_key]['label']}
                    </div>
                """, unsafe_allow_html=True)

                # column headers
                hc = st.columns([0.4, 6, 1.2, 1.2, 1.5])
                hc[0].markdown("<span style='font-family:Space Mono,monospace;font-size:8px;color:var(--text-subtle,#3A3A5C);letter-spacing:2px'>#</span>", unsafe_allow_html=True)
                hc[1].markdown("<span style='font-family:Space Mono,monospace;font-size:8px;color:var(--text-subtle,#3A3A5C);letter-spacing:2px'>TITRE</span>", unsafe_allow_html=True)
                hc[3].markdown("<span style='font-family:Space Mono,monospace;font-size:8px;color:var(--text-subtle,#3A3A5C);letter-spacing:2px'>DURÉE</span>", unsafe_allow_html=True)

                st.markdown("<div style='height:8px'></div>", unsafe_allow_html=True)

                for idx, r in enumerate(results):
                    badge = badge_class(r['type'])
                    col_n, col_info, col_type, col_dur, col_btn = st.columns([0.4, 6, 1.2, 1.2, 1.5])

                    with col_n:
                        st.markdown(f"<div style='font-family:Space Mono,monospace;font-size:10px;color:#3A3A5C;padding:14px 0;text-align:center'>{idx+1:02d}</div>", unsafe_allow_html=True)

                    with col_info:
                        st.markdown(f"""
                            <div style="padding:10px 0">
                                <div style="font-family:Raleway,sans-serif;font-size:13px;font-weight:600;color:#F0EDE6;
                                            white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-bottom:3px">
                                    {r['title']}
                                </div>
                                <div style="font-family:Space Mono,monospace;font-size:9px;letter-spacing:1.5px;
                                            text-transform:uppercase;color:#6B6B8A;
                                            white-space:nowrap;overflow:hidden;text-overflow:ellipsis">
                                    {r['artist']}
                                </div>
                            </div>
                        """, unsafe_allow_html=True)

                    with col_type:
                        st.markdown(f"""
                            <div style="padding:14px 0">
                                <span class="track-badge {badge}">{r['type']}</span>
                            </div>
                        """, unsafe_allow_html=True)

                    with col_dur:
                        st.markdown(f"<div style='font-family:Space Mono,monospace;font-size:10px;color:#6B6B8A;padding:14px 0'>{r['dur']}</div>", unsafe_allow_html=True)

                    with col_btn:
                        if st.button(f"↓ {audio_format}", key=f"dl_{mode_key}_{idx}"):
                            st.toast(f"Extraction en cours…", icon="⏳")
                            with st.spinner(f"Masterisation {audio_format}…"):
                                try:
                                    path, name, mime = download(r['url'], r['title'], audio_format)
                                    st.session_state.ready_path = path
                                    st.session_state.ready_name = name
                                    st.session_state.ready_mime = mime
                                    st.session_state.total_downloads += 1
                                    st.toast("Master prêt ✓", icon="✅")
                                    st.rerun()
                                except Exception as ex:
                                    st.error(f"Erreur : {ex}")

# ── DOWNLOAD MASTERWORK ────────────────────────────────────────────────
rp = st.session_state.get('ready_path')
rn = st.session_state.get('ready_name')
rm = st.session_state.get('ready_mime', 'audio/flac')

if rp and os.path.exists(rp):
    st.markdown("""
        <div class="masterwork-zone">
            <div class="masterwork-title">Votre Master est Prêt</div>
            <div class="masterwork-sub">Qualité lossless · Extraction complète</div>
        </div>
    """, unsafe_allow_html=True)

    # center the download button
    dc1, dc2, dc3 = st.columns([2, 3, 2])
    with dc2:
        with open(rp, "rb") as fh:
            st.download_button(
                label=f"◈  TÉLÉCHARGER  {rn.split('.')[-1].upper()}",
                data=fh.read(),
                file_name=rn,
                mime=rm,
            )

# ── STATS BAR (bottom) ────────────────────────────────────────────────
st.markdown("<div style='height:60px'></div>", unsafe_allow_html=True)
st.markdown(f"""
<div class="stats-bar">
  <div class="stat-item">
    <div class="stat-value">25</div>
    <div class="stat-label">Résultats max</div>
  </div>
  <div class="stat-item">
    <div class="stat-value">6</div>
    <div class="stat-label">Modes</div>
  </div>
  <div class="stat-item">
    <div class="stat-value">5</div>
    <div class="stat-label">Formats</div>
  </div>
  <div class="stat-item">
    <div class="stat-value">{st.session_state.total_downloads}</div>
    <div class="stat-label">Maîtres extraits</div>
  </div>
</div>
""", unsafe_allow_html=True)

st.markdown("""
<div style="text-align:center; padding:32px 0 24px; font-family:'Space Mono',monospace;
            font-size:8px; letter-spacing:3px; color:#24243A; text-transform:uppercase">
  Atelier Sonore · Studio Cinéma · Ultra Haute Fidélité
</div>
""", unsafe_allow_html=True)