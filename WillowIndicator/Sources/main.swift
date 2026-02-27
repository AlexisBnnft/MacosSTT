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

// MARK: - Gaussian Indicator View

class DotView: NSView {
    var currentState: IndicatorState = .idle
    var audioLevel: CGFloat = 0.0
    var smoothedLevel: CGFloat = 0.0

    private var animationTime: CGFloat = 0.0
    private var wobblePhase: CGFloat = 0.0

    // Gaussian geometry
    private let minDepth: CGFloat = 4
    private let maxDepth: CGFloat = 20
    private let lineWeight: CGFloat = 1.5
    private let steps = 80
    private var smoothedDepth: CGFloat = 4

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let lineY = bounds.maxY - 1

        switch currentState {
        case .idle:       drawIdle(lineY: lineY)
        case .recording:  drawRecording(lineY: lineY)
        case .processing: drawProcessing(lineY: lineY)
        }
    }

    // MARK: - Gaussian Path

    /// Gaussian bell curve dip: flat at edges, deepest at center
    private func gaussianStrokePath(lineY: CGFloat, dipDepth: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        let cx = bounds.midX
        let sigma = bounds.width / 5

        p.move(to: NSPoint(x: 0, y: lineY))
        for i in 0...steps {
            let x = bounds.width * CGFloat(i) / CGFloat(steps)
            let dx = x - cx
            let g = exp(-(dx * dx) / (2 * sigma * sigma))
            p.line(to: NSPoint(x: x, y: lineY - dipDepth * g))
        }
        return p
    }

    /// Closed gaussian path for fills
    private func gaussianFillPath(lineY: CGFloat, dipDepth: CGFloat) -> NSBezierPath {
        let p = gaussianStrokePath(lineY: lineY, dipDepth: dipDepth)
        p.close() // straight line back across the top
        return p
    }

    // MARK: - State Rendering

    private func drawIdle(lineY: CGFloat) {
        // Smoothly settle back to min depth
        smoothedDepth += (minDepth - smoothedDepth) * 0.08

        // Subtle fill
        currentState.baseColor.withAlphaComponent(0.05).setFill()
        gaussianFillPath(lineY: lineY, dipDepth: smoothedDepth).fill()

        // Outline
        let outline = gaussianStrokePath(lineY: lineY, dipDepth: smoothedDepth)
        currentState.baseColor.withAlphaComponent(0.4).setStroke()
        outline.lineWidth = lineWeight
        outline.lineCapStyle = .round
        outline.stroke()
    }

    private func drawRecording(lineY: CGFloat) {
        smoothedLevel += (audioLevel - smoothedLevel) * 0.25
        wobblePhase += 0.05
        let breathe = sin(wobblePhase) * 0.5 + 0.5

        // Amplify quiet sounds with sqrt curve, then map to depth
        let boosted = pow(smoothedLevel, 0.4)
        let targetDepth = minDepth + boosted * (maxDepth - minDepth)
        smoothedDepth += (targetDepth - smoothedDepth) * 0.25
        let d = smoothedDepth + breathe * 0.5

        // Glow
        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.saveGState()
        let glowRadius = 4 + smoothedLevel * 10
        ctx?.setShadow(offset: .zero, blur: glowRadius,
                       color: currentState.baseColor.withAlphaComponent(0.3 + smoothedLevel * 0.3).cgColor)

        // Audio-reactive fill
        let fillAlpha: CGFloat = 0.08 + smoothedLevel * 0.45 + breathe * 0.03
        currentState.baseColor.withAlphaComponent(fillAlpha).setFill()
        gaussianFillPath(lineY: lineY, dipDepth: d).fill()
        ctx?.restoreGState()

        // Outline
        let outlineAlpha: CGFloat = 0.5 + smoothedLevel * 0.5
        let lw = lineWeight + smoothedLevel * 0.8
        let outline = gaussianStrokePath(lineY: lineY, dipDepth: d)
        currentState.baseColor.withAlphaComponent(outlineAlpha).setStroke()
        outline.lineWidth = lw
        outline.lineCapStyle = .round
        outline.stroke()
    }

    private func drawProcessing(lineY: CGFloat) {
        animationTime += 0.016
        wobblePhase += 0.02
        let breathe = sin(animationTime * 2.0) * 0.5 + 0.5

        // Gentle breathing depth between min and mid
        let midDepth = (minDepth + maxDepth) / 2
        let targetDepth = midDepth + breathe * 3
        smoothedDepth += (targetDepth - smoothedDepth) * 0.08
        let d = smoothedDepth

        // Breathing fill
        let fillAlpha: CGFloat = 0.06 + breathe * 0.12
        currentState.baseColor.withAlphaComponent(fillAlpha).setFill()
        let fPath = gaussianFillPath(lineY: lineY, dipDepth: d)
        fPath.fill()

        // Sweeping highlight clipped to gaussian
        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.saveGState()
        fPath.addClip()

        let sweep = sin(animationTime * 1.5) * 0.5 + 0.5
        let sweepX = sweep * bounds.width
        let sweepRect = NSRect(x: sweepX - 25, y: 0, width: 50, height: bounds.height)
        currentState.baseColor.withAlphaComponent(0.2 + breathe * 0.08).setFill()
        NSBezierPath(ovalIn: sweepRect).fill()
        ctx?.restoreGState()

        // Outline
        let outline = gaussianStrokePath(lineY: lineY, dipDepth: d)
        currentState.baseColor.withAlphaComponent(0.6 + breathe * 0.2).setStroke()
        outline.lineWidth = lineWeight
        outline.lineCapStyle = .round
        outline.stroke()
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

// Detect menu bar height (accounts for notch on newer MacBooks)
var menuBarHeight: CGFloat = 25
if #available(macOS 12, *) {
    let topInset = screen.safeAreaInsets.top
    if topInset > 0 {
        menuBarHeight = topInset
    }
}

let viewWidth: CGFloat = 192   // shrunk 1/7
let viewHeight: CGFloat = 28

// Center on screen (where the notch is), just below menu bar
let x = screenFrame.midX - viewWidth / 2
let y = screenFrame.maxY - menuBarHeight - viewHeight

let window = NSWindow(
    contentRect: NSRect(x: x, y: y, width: viewWidth, height: viewHeight),
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

let dotView = DotView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: viewHeight))
window.contentView = dotView
window.orderFrontRegardless()

// 60fps animation timer
let animationTimer = DispatchSource.makeTimerSource(queue: .main)
animationTimer.schedule(deadline: .now(), repeating: .milliseconds(16))
animationTimer.setEventHandler {
    if let content = try? String(contentsOfFile: stateFile, encoding: .utf8) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

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

    dotView.updateAnimation()
}
animationTimer.resume()

print("Willow Indicator running (gaussian style)")
print("State file: \(stateFile)")

app.run()
