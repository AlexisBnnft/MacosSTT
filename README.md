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

## Requirements

- macOS (tested on Sonoma)
- Python 3.10+
- OpenAI API key

## License

MIT
