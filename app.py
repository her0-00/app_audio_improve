import streamlit as st
import yt_dlp
import os
import re

# --- CONFIGURATION DU DOSSIER SERVEUR ---
SERVER_VAULT = "Server_Audio_Vault"
if not os.path.exists(SERVER_VAULT):
    os.makedirs(SERVER_VAULT)

# --- CONFIGURATION PAGE ---
st.set_page_config(page_title="CINEMA AUDIO LUXE", page_icon="🎵", layout="centered")

# --- CSS LUXE (Design de l'interface) ---
st.markdown("""
    <style>
    .stApp { background-color: #050505; color: #FFFFFF; }
    h1, h2, h3 { color: #D4AF37 !important; text-align: center; font-family: 'Helvetica Neue', sans-serif; letter-spacing: 2px; }
    .stButton>button { background-color: #D4AF37; color: #000000; border-radius: 10px; font-weight: bold; width: 100%; border: none; transition: all 0.3s ease; }
    .stButton>button:hover { background-color: #FFDF00; color: black; box-shadow: 0px 0px 15px rgba(212, 175, 55, 0.5); }
    .stTextInput>div>div>input { background-color: #111111; color: #D4AF37; border: 1px solid #996515; border-radius: 10px; text-align: center; }
    .stTextInput>div>div>input:focus { border-color: #D4AF37; box-shadow: 0px 0px 5px #D4AF37; }
    .result-box { background-color: #111111; padding: 15px; border-radius: 10px; border: 1px solid #333333; margin-bottom: 10px; }
    </style>
""", unsafe_allow_html=True)

# --- MÉMOIRE DE L'APPLICATION (Session State) ---
# Nécessaire pour que l'app se souvienne des résultats entre chaque clic
if 'search_results' not in st.session_state:
    st.session_state.search_results = []
if 'ready_file_path' not in st.session_state:
    st.session_state.ready_file_path = None
if 'ready_file_name' not in st.session_state:
    st.session_state.ready_file_name = None

# --- FONCTIONS SYSTÈMES ---
def clean_filename(title):
    # Enlève les caractères qui font planter Windows/Linux
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
            'preferredcodec': 'flac', # C'est ici que la magie FLAC opère
            'preferredquality': '0',
        }],
        'outtmpl': file_path_template,
        'quiet': True,
    }
    
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        ydl.download([url])
    
    return f"{SERVER_VAULT}/{safe_title}.flac", f"{safe_title}.flac"

# --- INTERFACE VISUELLE ---
st.markdown("<h1>🎵<br>STUDIO CINÉMA</h1>", unsafe_allow_html=True)
st.markdown("<p style='text-align: center; color: #9E9E9E; font-size: 12px; letter-spacing: 4px;'>ULTRA LOSSLESS EXTRACTION</p>", unsafe_allow_html=True)
st.write("---")

query = st.text_input("Tapez un titre, une ambiance ou un artiste...", placeholder="Ex: Hans Zimmer Interstellar")

if st.button("RECHERCHER LE MORCEAU"):
    if query:
        with st.spinner("Recherche dans la base de données..."):
            st.session_state.search_results = search_youtube(query)
            st.session_state.ready_file_path = None # Réinitialise le téléchargement précédent
    else:
        st.warning("Veuillez entrer un terme de recherche.")

if st.session_state.search_results:
    st.markdown("<h3 style='font-size: 18px; text-align: left;'>RÉSULTATS :</h3>", unsafe_allow_html=True)
    
    for idx, res in enumerate(st.session_state.search_results):
        col1, col2 = st.columns([3, 1])
        with col1:
            st.markdown(f"<div class='result-box'><b>{res['title']}</b><br><span style='color: #9E9E9E; font-size: 12px;'>{res['artist']}</span></div>", unsafe_allow_html=True)
        with col2:
            st.write("") # Maintient l'alignement
            if st.button("📥 EXTRAIRE", key=f"btn_{idx}"):
                with st.spinner("Extraction du FLAC sur le serveur (Patientez quelques secondes)..."):
                    try:
                        file_path, file_name = process_download(res['url'], res['title'])
                        st.session_state.ready_file_path = file_path
                        st.session_state.ready_file_name = file_name
                        st.success("Extraction réussie !")
                    except Exception as e:
                        st.error(f"Erreur serveur FFmpeg : {e}")

# --- LE BOUTON DE TÉLÉCHARGEMENT FINAL ---
if st.session_state.ready_file_path and os.path.exists(st.session_state.ready_file_path):
    st.write("---")
    st.markdown("<h3 style='font-size: 18px; color: #00FF00;'>FICHIER PRÊT POUR VOTRE APPAREIL ✅</h3>", unsafe_allow_html=True)
    
    with open(st.session_state.ready_file_path, "rb") as file:
        file_bytes = file.read()
        
    st.download_button(
        label=f"💾 ENREGISTRER {st.session_state.ready_file_name} SUR MON APPAREIL",
        data=file_bytes,
        file_name=st.session_state.ready_file_name,
        mime="audio/flac"
    )
