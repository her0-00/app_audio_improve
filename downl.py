import streamlit as st
import yt_dlp
import os
import re

# --- CONFIGURATION DU DOSSIER SERVEUR ---
SERVER_VAULT = "Server_Audio_Vault"
if not os.path.exists(SERVER_VAULT):
    os.makedirs(SERVER_VAULT)

# --- CONFIGURATION PAGE SOTA ---
# Obligatoire en tout premier
st.set_page_config(page_title="STUDIO CINÉMA", page_icon="💽", layout="centered")

# --- CSS ULTRA LUXE (Glassmorphism & Polices) ---
st.markdown("""
    <style>
    /* Importation des polices Google */
    @import url('https://fonts.googleapis.com/css2?family=Cinzel:wght@600;800&family=Montserrat:wght@300;500;700&display=swap');
    
    /* Fond de l'application et police globale */
    .stApp {
        background: radial-gradient(circle at 50% 0%, #1a1a1a 0%, #050505 100%);
        color: #FFFFFF;
        font-family: 'Montserrat', sans-serif;
    }
    
    /* Cacher les traces de Streamlit pour faire "App Native" */
    #MainMenu {visibility: hidden;}
    footer {visibility: hidden;}
    header {visibility: hidden;}

    /* Titres Luxe */
    h1 {
        font-family: 'Cinzel', serif !important;
        color: #D4AF37 !important;
        text-align: center;
        text-shadow: 0px 4px 20px rgba(212, 175, 55, 0.4);
        font-size: 3rem !important;
        margin-bottom: 0px !important;
    }
    .subtitle {
        text-align: center;
        color: #888;
        font-size: 0.8rem;
        letter-spacing: 5px;
        margin-bottom: 40px;
        text-transform: uppercase;
    }

    /* Barre de recherche SOTA */
    .stTextInput>div>div>input {
        background: rgba(20, 20, 20, 0.6) !important;
        backdrop-filter: blur(10px);
        color: #D4AF37 !important;
        border: 1px solid #333 !important;
        border-radius: 30px !important;
        text-align: center;
        padding: 15px !important;
        font-size: 16px !important;
        transition: all 0.3s ease !important;
    }
    .stTextInput>div>div>input:focus {
        border-color: #D4AF37 !important;
        box-shadow: 0px 0px 15px rgba(212, 175, 55, 0.3) !important;
    }

    /* Boutons SOTA (Dégradés et ombres) */
    .stButton>button {
        background: linear-gradient(135deg, #D4AF37 0%, #996515 100%) !important;
        color: #000000 !important;
        border-radius: 30px !important;
        font-weight: 800 !important;
        letter-spacing: 1px !important;
        width: 100%;
        border: none !important;
        padding: 10px 0px !important;
        transition: all 0.3s ease !important;
    }
    .stButton>button:hover {
        transform: translateY(-2px);
        box-shadow: 0px 8px 20px rgba(212, 175, 55, 0.4) !important;
        color: #FFFFFF !important;
    }

    /* Cartes de résultats (Glassmorphism) */
    .result-card {
        background: rgba(30, 30, 30, 0.4);
        backdrop-filter: blur(10px);
        border-left: 4px solid #D4AF37;
        padding: 15px 20px;
        border-radius: 12px;
        margin-bottom: 5px;
        transition: all 0.3s ease;
    }
    .result-card:hover {
        background: rgba(40, 40, 40, 0.8);
        border-left: 4px solid #FFDF00;
    }
    .result-title {
        font-weight: 700;
        font-size: 15px;
        color: #FFF;
        margin-bottom: 4px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
    }
    .result-artist {
        font-size: 11px;
        color: #9E9E9E;
        text-transform: uppercase;
        letter-spacing: 1px;
    }

    /* Zone de Téléchargement VIP */
    .download-zone {
        margin-top: 40px;
        padding: 30px;
        border-radius: 20px;
        background: rgba(212, 175, 55, 0.05);
        border: 1px solid rgba(212, 175, 55, 0.2);
        text-align: center;
    }
    </style>
""", unsafe_allow_html=True)

# --- MÉMOIRE DE L'APPLICATION ---
if 'search_results' not in st.session_state:
    st.session_state.search_results = []
if 'ready_file_path' not in st.session_state:
    st.session_state.ready_file_path = None
if 'ready_file_name' not in st.session_state:
    st.session_state.ready_file_name = None

# --- MOTEUR AUDIO ---
def clean_filename(title):
    return re.sub(r'[\\/*?:"<>|]', "", title)

def search_youtube(query):
    ydl_opts = {'extract_flat': True, 'quiet': True, 'no_warnings': True}
    results = []
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(f"ytsearch5:{query} official audio", download=False)
        if 'entries' in info:
            for entry in info['entries']:
                results.append({
                    'title': entry.get('title', 'Titre inconnu'),
                    'artist': entry.get('uploader', 'Artiste inconnu'),
                    'url': entry.get('url')
                })
    return results

def process_download(url, title):
    safe_title = clean_filename(title)
    file_path_template = f'{SERVER_VAULT}/{safe_title}.%(ext)s'
    
    ydl_opts = {
        'format': 'bestaudio/best',
        'postprocessors': [{
            'key': 'FFmpegExtractAudio',
            'preferredcodec': 'flac',
            'preferredquality': '0',
        }],
        'outtmpl': file_path_template,
        'quiet': True,
    }
    
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        ydl.download([url])
    
    return f"{SERVER_VAULT}/{safe_title}.flac", f"{safe_title}.flac"

# --- INTERFACE UTILISATEUR ---
st.markdown("<h1>STUDIO CINÉMA</h1>", unsafe_allow_html=True)
st.markdown("<div class='subtitle'>Ultra Lossless Extraction</div>", unsafe_allow_html=True)

query = st.text_input("", placeholder="🔍 Tapez un titre, une ambiance ou un artiste...", label_visibility="collapsed")

if st.button("RECHERCHER L'ŒUVRE"):
    if query:
        with st.spinner("Analyse des fréquences et recherche en cours..."):
            st.session_state.search_results = search_youtube(query)
            st.session_state.ready_file_path = None 
    else:
        st.toast("⚠️ Veuillez entrer un terme de recherche", icon="⚠️")

if st.session_state.search_results:
    st.write("") # Espacement
    
    for idx, res in enumerate(st.session_state.search_results):
        col1, col2 = st.columns([3, 1], gap="medium")
        with col1:
            # Rendu de la carte SOTA
            st.markdown(f"""
                <div class='result-card'>
                    <div class='result-title'>🎵 {res['title']}</div>
                    <div class='result-artist'>{res['artist']}</div>
                </div>
            """, unsafe_allow_html=True)
        with col2:
            st.write("") # Alignement vertical
            if st.button("📥 FLAC", key=f"btn_{idx}"):
                # Notification Toast élégante au lieu d'un gros bloc
                st.toast(f"Extraction de '{res['title']}' en cours...", icon="⏳")
                with st.spinner("Création du Master Audio..."):
                    try:
                        file_path, file_name = process_download(res['url'], res['title'])
                        st.session_state.ready_file_path = file_path
                        st.session_state.ready_file_name = file_name
                        st.toast("Master FLAC prêt !", icon="✅")
                    except Exception as e:
                        st.error(f"Erreur d'encodage : {e}")

# --- ZONE DE TÉLÉCHARGEMENT VIP ---
if st.session_state.ready_file_path and os.path.exists(st.session_state.ready_file_path):
    st.markdown("<div class='download-zone'>", unsafe_allow_html=True)
    st.markdown("<h3 style='font-family: Montserrat, sans-serif !important; color: #FFF !important; font-size: 16px; margin-bottom: 20px;'>✨ VOTRE MASTER EST PRÊT ✨</h3>", unsafe_allow_html=True)
    
    with open(st.session_state.ready_file_path, "rb") as file:
        file_bytes = file.read()
        
    st.download_button(
        label=f"💾 SAUVEGARDER DANS MES FICHIERS",
        data=file_bytes,
        file_name=st.session_state.ready_file_name,
        mime="audio/flac"
    )
    st.markdown("</div>", unsafe_allow_html=True)