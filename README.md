# macOS STT Indicator

A minimal, Willow-style microphone indicator for macOS. Shows a pulsing dot in the menu bar that reacts to your voice in real-time.

![Demo](demo.gif)

## Features

- Organic, audio-reactive pulse animation
- Sits cleanly in the menu bar
- Tiny footprint, pure Swift
- Toggle with a keyboard shortcut

## Build

```bash
swift build -c release
```

## Run

```bash
./.build/release/WillowIndicator
```

Or use the helper script:
```bash
./start.sh
```

## Keyboard Shortcut (⌘0)

Set up a global hotkey to toggle the indicator:

1. Open **Automator** → New **Quick Action**
2. Set "Workflow receives" to **no input**
3. Add **Run Shell Script** action
4. Paste:
   ```bash
   if pgrep -x "WillowIndicator" > /dev/null; then
       pkill -x "WillowIndicator"
   else
       /PATH/TO/WillowIndicator/.build/release/WillowIndicator &
   fi
   ```
5. Save as "Toggle Willow Indicator"
6. **System Settings → Keyboard → Keyboard Shortcuts → Services**
7. Assign your shortcut (e.g., ⌘0)

## License

MIT
