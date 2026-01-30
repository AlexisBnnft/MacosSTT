import AppKit
import Foundation

// MARK: - State

let stateFile = "/tmp/willow_state"

enum IndicatorState: String {
    case idle = "idle"
    case recording = "recording"
    case processing = "processing"

    var baseColor: NSColor {
        switch self {
        case .idle: return NSColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 0.9)
        case .recording: return NSColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
        case .processing: return NSColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0)
        }
    }
}

// MARK: - Animated Dot View

class DotView: NSView {
    var currentState: IndicatorState = .idle
    var audioLevel: CGFloat = 0.0
    var smoothedLevel: CGFloat = 0.0

    // Animation state
    private var animationTime: CGFloat = 0.0
    private var arcRotation: CGFloat = 0.0
    private var arcSpeed: CGFloat = 0.0
    private var targetArcSpeed: CGFloat = 2.5

    // Organic wobble
    private var wobblePhase: CGFloat = 0.0
    private var wobbleAmount: CGFloat = 0.0

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let baseRadius: CGFloat = 8.0

        switch currentState {
        case .idle:
            drawIdleDot(center: center, radius: baseRadius)

        case .recording:
            drawRecordingDot(center: center, baseRadius: baseRadius)

        case .processing:
            drawProcessingAnimation(center: center, baseRadius: baseRadius)
        }
    }

    private func drawIdleDot(center: NSPoint, radius: CGFloat) {
        // Smaller idle dot (half size)
        let smallRadius = radius * 0.5
        let dotRect = NSRect(
            x: center.x - smallRadius,
            y: center.y - smallRadius,
            width: smallRadius * 2,
            height: smallRadius * 2
        )

        // Subtle glow
        let glowColor = currentState.baseColor.withAlphaComponent(0.2)
        glowColor.setFill()
        let glowRect = dotRect.insetBy(dx: -2, dy: -2)
        NSBezierPath(ovalIn: glowRect).fill()

        // Main dot
        currentState.baseColor.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }

    private func drawRecordingDot(center: NSPoint, baseRadius: CGFloat) {
        // Smooth the audio level for organic feel
        smoothedLevel += (audioLevel - smoothedLevel) * 0.15

        // Start with smaller base, pulse up to 3x on loud audio
        let smallBase = baseRadius * 0.5  // Half size when quiet
        let maxPulse = baseRadius * 2.5   // Can grow to 3x the small base
        let pulseAmount = smoothedLevel * maxPulse
        let radius = smallBase + pulseAmount

        // Organic breathing wobble
        wobblePhase += 0.05
        let breathe = sin(wobblePhase) * 0.5 + 0.5
        let wobbledRadius = radius + breathe * 0.3

        let dotRect = NSRect(
            x: center.x - wobbledRadius,
            y: center.y - wobbledRadius,
            width: wobbledRadius * 2,
            height: wobbledRadius * 2
        )

        // Multi-layer glow that pulses with audio
        let glowIntensity = 0.15 + smoothedLevel * 0.35

        // Outer glow - scales dramatically with audio
        let outerGlowRadius = wobbledRadius + 4 + smoothedLevel * 8
        let outerGlowRect = NSRect(
            x: center.x - outerGlowRadius,
            y: center.y - outerGlowRadius,
            width: outerGlowRadius * 2,
            height: outerGlowRadius * 2
        )
        currentState.baseColor.withAlphaComponent(glowIntensity * 0.3).setFill()
        NSBezierPath(ovalIn: outerGlowRect).fill()

        // Middle glow
        let midGlowRadius = wobbledRadius + 2 + smoothedLevel * 5
        let midGlowRect = NSRect(
            x: center.x - midGlowRadius,
            y: center.y - midGlowRadius,
            width: midGlowRadius * 2,
            height: midGlowRadius * 2
        )
        currentState.baseColor.withAlphaComponent(glowIntensity * 0.5).setFill()
        NSBezierPath(ovalIn: midGlowRect).fill()

        // Inner glow
        let innerGlowRect = dotRect.insetBy(dx: -1.5, dy: -1.5)
        currentState.baseColor.withAlphaComponent(glowIntensity).setFill()
        NSBezierPath(ovalIn: innerGlowRect).fill()

        // Main dot with slight brightness variation
        let brightnessBoost = smoothedLevel * 0.2
        let boostedColor = NSColor(
            red: min(1.0, 1.0 + brightnessBoost),
            green: min(1.0, 0.23 + brightnessBoost * 0.5),
            blue: min(1.0, 0.19 + brightnessBoost * 0.3),
            alpha: 1.0
        )
        boostedColor.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }

    private func drawProcessingAnimation(center: NSPoint, baseRadius: CGFloat) {
        // Ease arc speed in/out for organic feel
        arcSpeed += (targetArcSpeed - arcSpeed) * 0.05

        // Add subtle speed variation for organic movement
        wobblePhase += 0.02
        let speedVariation = sin(wobblePhase * 1.7) * 0.3 + sin(wobblePhase * 2.3) * 0.2
        arcRotation += (arcSpeed + speedVariation) * 0.05

        // Gentle breathing
        let breathe = sin(animationTime * 2.0) * 0.5 + 0.5
        let radius = baseRadius + breathe * 1.0
        animationTime += 0.016

        // Draw center dot (smaller during processing)
        let dotRadius = radius * 0.7
        let dotRect = NSRect(
            x: center.x - dotRadius,
            y: center.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        )

        // Subtle glow
        currentState.baseColor.withAlphaComponent(0.2).setFill()
        let glowRect = dotRect.insetBy(dx: -3, dy: -3)
        NSBezierPath(ovalIn: glowRect).fill()

        currentState.baseColor.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        // Draw spinning arc
        let arcRadius = radius + 4
        let arcPath = NSBezierPath()

        // Arc length varies organically
        let arcLengthVariation = sin(wobblePhase * 1.3) * 0.2
        let arcLength: CGFloat = 1.8 + arcLengthVariation  // ~100-130 degrees

        arcPath.appendArc(
            withCenter: center,
            radius: arcRadius,
            startAngle: arcRotation * 180 / .pi,
            endAngle: (arcRotation + arcLength) * 180 / .pi,
            clockwise: false
        )

        // Arc stroke with gradient-like fade at ends
        currentState.baseColor.withAlphaComponent(0.9).setStroke()
        arcPath.lineWidth = 2.5
        arcPath.lineCapStyle = .round
        arcPath.stroke()

        // Second smaller arc going opposite direction for more organic feel
        let arc2Path = NSBezierPath()
        let arc2Rotation = -arcRotation * 0.7
        let arc2Length: CGFloat = 0.8 + arcLengthVariation * 0.5

        arc2Path.appendArc(
            withCenter: center,
            radius: arcRadius + 0.5,
            startAngle: arc2Rotation * 180 / .pi,
            endAngle: (arc2Rotation + arc2Length) * 180 / .pi,
            clockwise: false
        )

        currentState.baseColor.withAlphaComponent(0.4).setStroke()
        arc2Path.lineWidth = 1.5
        arc2Path.lineCapStyle = .round
        arc2Path.stroke()
    }

    func updateAnimation() {
        needsDisplay = true
    }
}

// MARK: - App

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

guard let screen = NSScreen.main else { exit(1) }

let screenFrame = screen.frame
let viewSize: CGFloat = 40  // Larger to accommodate glow/arcs

// Position near top, right of center (avoiding notch camera)
let x = screenFrame.midX + 100
let y = screenFrame.maxY - viewSize - 4

// Create window
let window = NSWindow(
    contentRect: NSRect(x: x, y: y, width: viewSize, height: viewSize),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)

window.backgroundColor = .clear
window.isOpaque = false
window.hasShadow = false
window.level = .screenSaver
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
window.ignoresMouseEvents = true

// Create dot view
let dotView = DotView(frame: NSRect(x: 0, y: 0, width: viewSize, height: viewSize))
window.contentView = dotView

window.orderFrontRegardless()

// Animation timer - 60fps for smooth animations
let animationTimer = DispatchSource.makeTimerSource(queue: .main)
animationTimer.schedule(deadline: .now(), repeating: .milliseconds(16))
animationTimer.setEventHandler {
    // Read state file
    if let content = try? String(contentsOfFile: stateFile, encoding: .utf8) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse state and optional audio level
        if trimmed.hasPrefix("recording:") {
            let parts = trimmed.split(separator: ":")
            if parts.count == 2, let level = Double(parts[1]) {
                dotView.currentState = .recording
                dotView.audioLevel = CGFloat(level)
            }
        } else if let newState = IndicatorState(rawValue: trimmed) {
            if newState != dotView.currentState {
                dotView.currentState = newState
                dotView.audioLevel = 0.0
            }
        }
    }

    // Always update for animations
    dotView.updateAnimation()
}
animationTimer.resume()

print("Willow Indicator running (animated)")
print("State file: \(stateFile)")

app.run()
