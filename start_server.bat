@echo off
echo Installation des dépendances...
pip install -r requirements.txt

echo.
echo Démarrage du serveur Flask...
echo Le serveur sera accessible à http://172.20.10.3:8501
echo.
python server.py
pause
