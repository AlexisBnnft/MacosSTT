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
import time
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
DOUBLE_TAP_THRESHOLD = 0.3  # seconds – max delay between two taps
HOLD_THRESHOLD = 0.25  # seconds – hold longer than this = push-to-talk
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
        self.last_tap_time = 0.0  # For double-tap detection
        self.key_held = False  # To ignore key-repeat events
        self.press_time = 0.0  # When the key was pressed down
        self.toggle_mode = False  # True = hands-free recording via double-tap

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

        print("WillowLike - Voice transcription")
        print("Hold Right Option = push-to-talk")
        print("Double-tap Right Option = hands-free toggle")
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
        if key != HOTKEY:
            return
        if self.key_held:
            return  # Ignore key-repeat from holding
        self.key_held = True
        self.press_time = time.time()

        # If in toggle mode and recording, a new press stops it
        if self.toggle_mode and self.recording:
            self.toggle_mode = False
            self.recording = False
            self.last_tap_time = 0.0
            set_state("processing")
            threading.Thread(target=self.transcribe_and_paste, daemon=True).start()
            return

        now = time.time()
        if now - self.last_tap_time < DOUBLE_TAP_THRESHOLD:
            # Double-tap detected → start hands-free toggle recording
            self.last_tap_time = 0.0
            self.toggle_mode = True
            self.recording = True
            self.audio_data = []
            set_state("recording")
        else:
            # First tap or push-to-talk — start recording immediately
            self.last_tap_time = now
            self.recording = True
            self.audio_data = []
            set_state("recording")

    def on_release(self, key):
        if key != HOTKEY:
            return
        self.key_held = False

        if self.toggle_mode:
            return  # In toggle mode, release does nothing

        # Push-to-talk: release stops recording & transcribes
        if self.recording:
            held = time.time() - self.press_time
            if held < DOUBLE_TAP_THRESHOLD:
                # Short tap — might be first tap of a double-tap, don't stop yet
                # Recording continues briefly; if no second tap comes, a timer stops it
                threading.Timer(DOUBLE_TAP_THRESHOLD, self._check_single_tap).start()
            else:
                # Long hold — classic push-to-talk release
                self.recording = False
                set_state("processing")
                threading.Thread(target=self.transcribe_and_paste, daemon=True).start()

    def _check_single_tap(self):
        """Called after timeout: if still recording and no double-tap happened, stop."""
        if self.recording and not self.toggle_mode:
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
