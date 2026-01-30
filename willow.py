#!/usr/bin/env python3
"""
WillowLike - Minimal push-to-talk voice transcription
Hold Right Option to record, release to transcribe and paste.

Requires the WillowIndicator Swift app running for the visual indicator.
"""

import atexit
import io
import signal
import subprocess
import sys
import threading
import wave
from pathlib import Path
from dotenv import load_dotenv
import numpy as np
import sounddevice as sd
from pynput import keyboard
from openai import OpenAI

load_dotenv()

# Config
SAMPLE_RATE = 16000
HOTKEY = keyboard.Key.alt_r
STATE_FILE = Path("/tmp/willow_state")


def set_state(state: str, level: float = 0.0):
    """Update the state file for the Swift indicator app."""
    if state == "recording":
        STATE_FILE.write_text(f"recording:{level:.3f}")
    else:
        print(f"[STATE] -> {state}")
        STATE_FILE.write_text(state)


class WillowApp:
    def __init__(self):
        self.client = OpenAI()
        self.recording = False
        self.audio_data = []
        self.audio_level = 0.0
        self.level_smooth = 0.0  # Smoothed level for organic feel

        # Initialize state
        set_state("idle")

        # Start audio stream
        self.stream = sd.InputStream(
            samplerate=SAMPLE_RATE,
            channels=1,
            callback=self.audio_callback
        )
        self.stream.start()

        # Start keyboard listener
        self.listener = keyboard.Listener(
            on_press=self.on_press,
            on_release=self.on_release
        )

        print("WillowLike - Push-to-talk transcription")
        print("Hold Right Option to record, release to transcribe")
        print("Make sure WillowIndicator is running for visual feedback")

    def audio_callback(self, indata, frames, time, status):
        if self.recording:
            self.audio_data.append(indata.copy())

            # Calculate RMS level for visualization
            rms = np.sqrt(np.mean(indata**2))
            # Normalize and apply curve for better visual response
            level = min(1.0, rms * 8)  # Scale up quiet sounds
            level = level ** 0.6  # Compress dynamic range

            # Smooth the level for organic animation
            self.level_smooth = self.level_smooth * 0.7 + level * 0.3

            # Update state with level
            set_state("recording", self.level_smooth)

    def on_press(self, key):
        if key == HOTKEY and not self.recording:
            self.recording = True
            self.audio_data = []
            set_state("recording")

    def on_release(self, key):
        if key == HOTKEY and self.recording:
            self.recording = False
            set_state("processing")
            threading.Thread(target=self.transcribe_and_paste, daemon=True).start()

    def transcribe_and_paste(self):
        if not self.audio_data:
            set_state("idle")
            return

        audio = np.concatenate(self.audio_data)
        self.audio_data = []

        buffer = io.BytesIO()
        with wave.open(buffer, 'wb') as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(SAMPLE_RATE)
            wf.writeframes((audio * 32767).astype(np.int16).tobytes())
        buffer.seek(0)
        buffer.name = "audio.wav"

        try:
            result = self.client.audio.transcriptions.create(
                model="whisper-1",
                file=buffer,
                response_format="text"
            )
            text = result.strip()
            if text:
                subprocess.run(['pbcopy'], input=text.encode(), check=True)
                subprocess.run([
                    'osascript', '-e',
                    'tell application "System Events" to keystroke "v" using command down'
                ], check=True)
                print(f"✓ {text}")
        except Exception as e:
            print(f"✗ {e}")

        set_state("idle")

    def run(self):
        with self.listener:
            self.listener.join()


def cleanup():
    """Clean exit: kill indicator and reset state."""
    subprocess.run(['pkill', '-f', 'WillowIndicator'], capture_output=True)
    try:
        STATE_FILE.unlink()
    except:
        pass
    print("\nBye!")

if __name__ == "__main__":
    atexit.register(cleanup)
    signal.signal(signal.SIGINT, lambda s, f: sys.exit(0))
    signal.signal(signal.SIGTERM, lambda s, f: sys.exit(0))

    app = WillowApp()
    app.run()
