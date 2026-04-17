# WillowLike

Minimal voice transcription for macOS with two recording modes: push-to-talk and hands-free double-tap toggle.

## Features

- **Push-to-talk**: Hold Right Option to record, release to transcribe
- **Double-tap toggle**: Tap Right Option twice quickly to start hands-free recording, tap again to stop
- Visual indicator dot near the notch (grey=idle, red=recording, orange=processing)
- Uses OpenAI Whisper for transcription
- Auto-pastes transcribed text

## Requirements

- macOS with Apple Silicon
- Python 3.9+
- Xcode Command Line Tools (`xcode-select --install`)
- OpenAI API key

## Setup

### Quick start

```bash
./setup
```

Installs Python deps, builds the Swift indicator, and prompts for your OpenAI API key. Then grant permissions (step 2 below) and run `./start.sh`.

### Manual setup

<details>
<summary>Prefer to do it by hand</summary>

#### 1. Install Python dependencies

```bash
pip install -r requirements.txt
```

#### 2. Configure API key

Create `.env` file:
```
OPENAI_API_KEY=sk-your-key-here
```

#### 3. Build the indicator

```bash
cd WillowIndicator
swift build -c release
cd ..
```

</details>

### Grant permissions

In System Settings > Privacy & Security:
- **Accessibility**: Add Terminal (or your terminal app)
- **Microphone**: Allow Terminal access

## Usage

```bash
./start.sh
```

**Push-to-talk:**
- Hold **Right Option** to record (dot turns red)
- Release to transcribe (dot turns orange)
- Text is auto-pasted at cursor

**Hands-free (double-tap toggle):**
- Tap **Right Option** twice quickly (< 0.3s) to start recording
- Tap **Right Option** again to stop and transcribe

Press **Ctrl+C** to exit cleanly.

## Architecture

```
WillowLike/
├── willow.py              # Main Python app (keyboard, audio, transcription)
├── WillowIndicator/       # Swift app for visual indicator
│   ├── Package.swift
│   └── Sources/main.swift
├── setup                  # One-shot installer (deps + build + API key prompt)
├── start.sh               # Launch script
├── requirements.txt
└── .env                   # API key (not committed)
```

### How it works

1. **willow.py** listens for Right Option key using `pynput`
2. Detects hold (push-to-talk) vs double-tap (toggle mode)
3. Starts recording audio via `sounddevice`
4. Writes state to `/tmp/willow_state` (idle/recording/processing)
5. **WillowIndicator** polls this file every 100ms and updates dot color
6. On stop, sends audio to Whisper API
7. Pastes result using `pbcopy` + AppleScript keystroke

## Customization

### Change hotkey

In `willow.py`, modify:
```python
HOTKEY = keyboard.Key.alt_r  # Change to any pynput key
DOUBLE_TAP_THRESHOLD = 0.3   # Adjust double-tap speed (seconds)
```

### Move indicator position

In `WillowIndicator/Sources/main.swift`, adjust:
```swift
let x = screenFrame.midX + 100  // Horizontal offset from center
```

Then rebuild: `cd WillowIndicator && swift build -c release`

### Change colors

In `main.swift`, modify the `IndicatorState.color` property.
