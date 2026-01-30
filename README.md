# macOS STT

Push-to-talk speech-to-text for macOS. Hold **Right Option**, speak, release to transcribe and paste.

Features a Willow-style audio-reactive indicator in the menu bar notch.

## Setup

```bash
# Install Python dependencies
pip install -r requirements.txt

# Build the indicator
swift build -c release

# Add your OpenAI API key
cp .env.example .env
# Edit .env with your key
```

## Run

```bash
./start.sh
```

Hold **Right Option** to record, release to transcribe. Text is automatically pasted at cursor.

## Keyboard Shortcut (⌘0)

Toggle the app with a global hotkey:

1. Open **Automator** → New **Quick Action**
2. Set "Workflow receives" to **no input**
3. Add **Run Shell Script** action
4. Paste:
   ```bash
   if pgrep -f "willow.py" > /dev/null; then
       pkill -f "willow.py"
       pkill -x "WillowIndicator"
   else
       /PATH/TO/MacosSTT/start.sh &
   fi
   ```
5. Save as "Toggle Willow"
6. **System Settings → Keyboard → Keyboard Shortcuts → Services** → Assign ⌘0

## Requirements

- macOS (tested on Sonoma)
- Python 3.10+
- OpenAI API key

## License

MIT
