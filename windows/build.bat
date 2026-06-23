@echo off
echo Installing requirements...
python -m pip install -r requirements.txt
python -m pip install pyinstaller

echo Building executable...
python -m PyInstaller --onefile --noconsole --name "GyroWheel_Receiver" receiver.py

echo Done! The executable is located in the 'dist' folder.
pause
