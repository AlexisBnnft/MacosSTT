import AppKit
import Foundation

// MARK: - State

let stateFile = "/tmp/willow_state"
let historyFile = NSString(string: "~/.willow/history.jsonl").expandingTildeInPath

enum IndicatorState: String {
    case idle, recording, processing, done, error

    var color: NSColor {
        switch self {
        case .idle:       return NSColor(white: 0.4, alpha: 1)
        case .recording:  return NSColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1)
        case .processing: return NSColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1)
        case .done:       return NSColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 1)
        case .error:      return NSColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1)
        }
    }
}

struct HistoryEntry {
    let time: Date
    let text: String
}

/// Last `limit` transcripts from ~/.willow/history.jsonl, newest first.
func loadHistory(limit: Int = 4) -> [HistoryEntry] {
    guard let content = try? String(contentsOfFile: historyFile, encoding: .utf8) else { return [] }
    var entries: [HistoryEntry] = []
    for line in content.split(separator: "\n").reversed() {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["text"] as? String else { continue }
        let t = obj["t"] as? Double ?? 0
        entries.append(HistoryEntry(time: Date(timeIntervalSince1970: t), text: text))
        if entries.count == limit { break }
    }
    return entries
}

func relativeTime(_ date: Date) -> String {
    let s = Date().timeIntervalSince(date)
    if s < 60 { return "à l'instant" }
    if s < 3600 { return "il y a \(Int(s / 60)) min" }
    if s < 86400 { return "il y a \(Int(s / 3600)) h" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "fr_FR")
    f.dateFormat = "d MMM"
    return f.string(from: date)
}

// MARK: - Spring

struct Spring {
    var x: CGFloat = 0
    var v: CGFloat = 0

    mutating func step(to target: CGFloat, k: CGFloat = 200, c: CGFloat = 20, dt: CGFloat = 1.0 / 60) {
        let a = k * (target - x) - c * v
        v += a * dt
        x += v * dt
    }
}

func clamp01(_ x: CGFloat) -> CGFloat { max(0, min(1, x)) }
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

// MARK: - Notch View
//
// A black shape that grows down out of the notch ("la goutte"):
//   idle        → nothing drawn, clicks pass through
//   hover       → a small lip peeks out below the notch, clicks enabled
//   recording   → drop with red dot, level bars and a timer
//   processing  → orange spinner and wave of dots
//   done/error  → check or cross, then retracts
//   click       → drop expands into a panel with the last 4 transcripts

class NotchView: NSView {
    // Geometry (set by the app once the screen is known)
    var notchW: CGFloat = 180
    var notchH: CGFloat = 32

    let dropExtraW: CGFloat = 30
    let dropExtraH: CGFloat = 26
    let panelW: CGFloat = 360
    let rowH: CGFloat = 50
    let panelHeaderH: CGFloat = 30

    // Inputs
    var state: IndicatorState = .idle
    var stateSince = Date()
    var audioLevel: CGFloat = 0
    var hovering = false
    var panelOpen = false
    var history: [HistoryEntry] = []
    var hoveredRow: Int? = nil
    var copiedRow: Int? = nil
    var copiedAt = Date.distantPast

    // Animation
    private var drop = Spring()
    private var panel = Spring()
    private var level = Spring()
    private var t: CGFloat = 0
    private var recordingStart = Date()

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// done/error are shown briefly, then behave like idle.
    var effectiveState: IndicatorState {
        if (state == .done || state == .error) && Date().timeIntervalSince(stateSince) > 1.3 { return .idle }
        return state
    }

    func setState(_ s: IndicatorState) {
        guard s != state else { return }
        if s == .recording { recordingStart = Date() }
        state = s
        stateSince = Date()
    }

    // MARK: Geometry

    var shapeSize: NSSize {
        let d = max(0, drop.x)
        var w = notchW + dropExtraW * d
        var h = notchH + dropExtraH * d + max(0, level.x) * 3
        let p = clamp01(panel.x)
        let rows = CGFloat(max(1, history.count))
        w = lerp(w, panelW, p)
        h = lerp(h, notchH + panelHeaderH + rows * rowH + 12, p)
        return NSSize(width: w, height: h)
    }

    var shapeRect: NSRect {
        let s = shapeSize
        return NSRect(x: bounds.midX - s.width / 2, y: 0, width: s.width, height: s.height)
    }

    /// Area that captures the mouse, in view coordinates.
    var hotZone: NSRect {
        if panelOpen { return shapeRect.insetBy(dx: -4, dy: -4) }
        let w = notchW + 40
        return NSRect(x: bounds.midX - w / 2, y: 0, width: w, height: max(notchH + 6, shapeSize.height))
    }

    func rowRect(_ i: Int) -> NSRect {
        let r = shapeRect
        return NSRect(x: r.minX + 8, y: notchH + panelHeaderH + CGFloat(i) * rowH, width: r.width - 16, height: rowH - 2)
    }

    func row(at p: NSPoint) -> Int? {
        guard panelOpen else { return nil }
        for i in 0..<history.count where rowRect(i).contains(p) { return i }
        return nil
    }

    // MARK: Tick

    func tick() {
        let dt: CGFloat = 1.0 / 60
        t += dt
        let s = effectiveState

        let dropTarget: CGFloat
        if s != .idle { dropTarget = 1 }
        else if hovering || panelOpen { dropTarget = 0.22 }
        else { dropTarget = 0 }
        drop.step(to: dropTarget, k: 200, c: 20)
        panel.step(to: panelOpen ? 1 : 0, k: 190, c: 22)
        level.step(to: s == .recording ? audioLevel : 0, k: 260, c: 24)

        needsDisplay = true
    }

    // MARK: Drawing

    private func notchPath(_ r: NSRect, radius: CGFloat, flare f: CGFloat = 6) -> NSBezierPath {
        let rad = min(radius, r.height / 2, r.width / 2)
        let x0 = r.minX, x1 = r.maxX, h = r.maxY
        let p = NSBezierPath()
        p.move(to: NSPoint(x: x0 - f, y: 0))
        p.curve(to: NSPoint(x: x0, y: f), controlPoint1: NSPoint(x: x0, y: 0), controlPoint2: NSPoint(x: x0, y: 0))
        p.line(to: NSPoint(x: x0, y: h - rad))
        p.curve(to: NSPoint(x: x0 + rad, y: h), controlPoint1: NSPoint(x: x0, y: h), controlPoint2: NSPoint(x: x0, y: h))
        p.line(to: NSPoint(x: x1 - rad, y: h))
        p.curve(to: NSPoint(x: x1, y: h - rad), controlPoint1: NSPoint(x: x1, y: h), controlPoint2: NSPoint(x: x1, y: h))
        p.line(to: NSPoint(x: x1, y: f))
        p.curve(to: NSPoint(x: x1 + f, y: 0), controlPoint1: NSPoint(x: x1, y: 0), controlPoint2: NSPoint(x: x1, y: 0))
        p.close()
        return p
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let d = max(0, drop.x), p = clamp01(panel.x)
        guard d > 0.01 || p > 0.01 else { return }

        let r = shapeRect
        let radius = 11 + 9 * clamp01(d) + 8 * p
        let shape = notchPath(r, radius: radius)
        NSColor.black.setFill()
        shape.fill()

        // Hairline rim below the notch band so the drop reads over dark content
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.clip(to: NSRect(x: 0, y: notchH, width: bounds.width, height: bounds.height))
            NSColor(white: 1, alpha: 0.1 * clamp01(d + p)).setStroke()
            let rim = notchPath(r.insetBy(dx: 0.5, dy: 0).offsetBy(dx: 0, dy: -0.5), radius: radius)
            rim.lineWidth = 1
            rim.stroke()
            ctx.restoreGState()
        }

        let contentAlpha = clamp01((d - 0.55) / 0.35) * (1 - clamp01(p * 2))
        if contentAlpha > 0 { drawDropContent(in: r, alpha: contentAlpha) }

        let panelAlpha = clamp01((p - 0.6) / 0.4)
        if panelAlpha > 0 { drawPanel(in: r, alpha: panelAlpha) }
    }

    private func drawDropContent(in r: NSRect, alpha: CGFloat) {
        let s = effectiveState
        let my = notchH + (r.height - notchH) / 2 - 1
        let lx = r.minX + 22, rx = r.maxX - 20
        let lv = clamp01(level.x)
        let ctx = NSGraphicsContext.current?.cgContext

        switch s {
        case .recording:
            ctx?.saveGState()
            ctx?.setShadow(offset: .zero, blur: 6 + lv * 8, color: s.color.withAlphaComponent(0.8 * alpha).cgColor)
            s.color.withAlphaComponent(alpha).setFill()
            let dr = 3.6 + lv * 1.4
            NSBezierPath(ovalIn: NSRect(x: lx - dr, y: my - dr, width: dr * 2, height: dr * 2)).fill()
            ctx?.restoreGState()

            let n = 11, gap: CGFloat = 5.2
            let x0 = r.midX - CGFloat(n - 1) * gap / 2 - 6
            NSColor(white: 1, alpha: 0.92 * alpha).setFill()
            for i in 0..<n {
                let c = (CGFloat(i) - CGFloat(n - 1) / 2) / 3.2
                let env = exp(-c * c)
                let f = 0.4 + 0.6 * abs(sin(t * 6.5 + CGFloat(i) * 0.85))
                let bh = 2.5 + lv * 15 * f * env
                NSBezierPath(roundedRect: NSRect(x: x0 + CGFloat(i) * gap - 1.2, y: my - bh / 2, width: 2.4, height: bh),
                             xRadius: 1.2, yRadius: 1.2).fill()
            }

            let secs = Int(Date().timeIntervalSince(recordingStart))
            drawText(String(format: "%d:%02d", secs / 60, secs % 60), rightAt: rx + 6, midY: my,
                     font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                     color: NSColor(white: 1, alpha: 0.55 * alpha))

        case .processing:
            let arc = NSBezierPath()
            let start = (t * 6).truncatingRemainder(dividingBy: .pi * 2) * 180 / .pi
            arc.appendArc(withCenter: NSPoint(x: lx, y: my), radius: 5.5, startAngle: start, endAngle: start + 234)
            arc.lineWidth = 2
            arc.lineCapStyle = .round
            s.color.withAlphaComponent(alpha).setStroke()
            arc.stroke()

            let n = 11, gap: CGFloat = 5.2
            let x0 = r.midX - CGFloat(n - 1) * gap / 2 - 6
            for i in 0..<n {
                let ph = sin(t * 7 - CGFloat(i) * 0.7) * 0.5 + 0.5
                let dr = 1.2 + ph * 0.9
                s.color.withAlphaComponent((0.3 + ph * 0.7) * alpha).setFill()
                NSBezierPath(ovalIn: NSRect(x: x0 + CGFloat(i) * gap - dr, y: my - dr, width: dr * 2, height: dr * 2)).fill()
            }

        case .done, .error:
            let mark = NSBezierPath()
            if s == .done {
                mark.move(to: NSPoint(x: lx - 5, y: my))
                mark.line(to: NSPoint(x: lx - 1.5, y: my + 3.5))
                mark.line(to: NSPoint(x: lx + 5, y: my - 4))
            } else {
                mark.move(to: NSPoint(x: lx - 4, y: my - 4)); mark.line(to: NSPoint(x: lx + 4, y: my + 4))
                mark.move(to: NSPoint(x: lx + 4, y: my - 4)); mark.line(to: NSPoint(x: lx - 4, y: my + 4))
            }
            mark.lineWidth = 2.2
            mark.lineCapStyle = .round
            mark.lineJoinStyle = .round
            s.color.withAlphaComponent(alpha).setStroke()
            mark.stroke()
            drawText(s == .done ? "Collé" : "Échec", centerAt: r.midX, midY: my,
                     font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor(white: 1, alpha: 0.9 * alpha))

        case .idle:
            break
        }
    }

    private func drawPanel(in r: NSRect, alpha: CGFloat) {
        let headerY = notchH + panelHeaderH / 2 - 2
        drawText("Récents", leftAt: r.minX + 18, midY: headerY,
                 font: .systemFont(ofSize: 13, weight: .semibold), color: NSColor(white: 1, alpha: alpha))
        drawText("clic copier · ⌥ clic coller", rightAt: r.maxX - 18, midY: headerY,
                 font: .systemFont(ofSize: 11), color: NSColor(white: 1, alpha: 0.45 * alpha))

        if history.isEmpty {
            drawText("Aucune dictée pour l'instant.", leftAt: r.minX + 18, midY: notchH + panelHeaderH + rowH / 2 - 2,
                     font: .systemFont(ofSize: 13), color: NSColor(white: 1, alpha: 0.55 * alpha))
            return
        }

        for (i, entry) in history.enumerated() {
            let rr = rowRect(i)
            if hoveredRow == i {
                NSColor(white: 1, alpha: 0.08 * alpha).setFill()
                NSBezierPath(roundedRect: rr, xRadius: 12, yRadius: 12).fill()
            }
            drawText("\(i + 1)", leftAt: rr.minX + 8, midY: rr.minY + 14,
                     font: .monospacedSystemFont(ofSize: 11, weight: .regular), color: NSColor(white: 1, alpha: 0.4 * alpha))

            let copied = copiedRow == i && Date().timeIntervalSince(copiedAt) < 1.4
            let when = copied ? "Copié" : relativeTime(entry.time)
            let whenFont = NSFont.systemFont(ofSize: 11.5)
            let whenColor = copied ? IndicatorState.done.color.withAlphaComponent(alpha) : NSColor(white: 1, alpha: 0.45 * alpha)
            let whenW = (when as NSString).size(withAttributes: [.font: whenFont]).width
            drawText(when, rightAt: rr.maxX - 8, midY: rr.minY + 14, font: whenFont, color: whenColor)

            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byTruncatingTail
            let textRect = NSRect(x: rr.minX + 28, y: rr.minY + 6, width: rr.width - 28 - whenW - 18, height: 36)
            (entry.text as NSString).draw(with: textRect,
                                          options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                          attributes: [.font: NSFont.systemFont(ofSize: 13),
                                                       .foregroundColor: NSColor(white: 1, alpha: alpha),
                                                       .paragraphStyle: para])
        }
    }

    // MARK: Text helpers

    private func attrs(_ font: NSFont, _ color: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: color]
    }

    private func drawText(_ s: String, leftAt x: CGFloat, midY: CGFloat, font: NSFont, color: NSColor) {
        let a = attrs(font, color), size = (s as NSString).size(withAttributes: a)
        (s as NSString).draw(at: NSPoint(x: x, y: midY - size.height / 2), withAttributes: a)
    }

    private func drawText(_ s: String, rightAt x: CGFloat, midY: CGFloat, font: NSFont, color: NSColor) {
        let a = attrs(font, color), size = (s as NSString).size(withAttributes: a)
        (s as NSString).draw(at: NSPoint(x: x - size.width, y: midY - size.height / 2), withAttributes: a)
    }

    private func drawText(_ s: String, centerAt x: CGFloat, midY: CGFloat, font: NSFont, color: NSColor) {
        let a = attrs(font, color), size = (s as NSString).size(withAttributes: a)
        (s as NSString).draw(at: NSPoint(x: x - size.width / 2, y: midY - size.height / 2), withAttributes: a)
    }

    // MARK: Mouse

    var onToggle: (() -> Void)?
    var onRowClick: ((Int, Bool) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let i = row(at: p) {
            onRowClick?(i, event.modifierFlags.contains(.option))
        } else if !panelOpen || p.y < notchH + panelHeaderH {
            onToggle?()
        }
    }
}

// MARK: - Window

/// Non-activating panel: clicking it never steals focus from the app you're typing in.
class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // Allow sitting over the menu bar / notch area
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Prefer the built-in screen with a notch
guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { exit(1) }
let screenFrame = screen.frame

let hasNotch = screen.safeAreaInsets.top > 0
let menuBarHeight: CGFloat = hasNotch ? screen.safeAreaInsets.top : (screenFrame.maxY - screen.visibleFrame.maxY)
var notchWidth: CGFloat = 180
if hasNotch, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
    notchWidth = screenFrame.width - left.width - right.width
}

let viewWidth: CGFloat = 400
let viewHeight: CGFloat = 320

let window = NotchPanel(
    contentRect: NSRect(x: screenFrame.midX - viewWidth / 2, y: screenFrame.maxY - viewHeight,
                        width: viewWidth, height: viewHeight),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
window.backgroundColor = .clear
window.isOpaque = false
window.hasShadow = false
window.level = .screenSaver
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
window.isFloatingPanel = true
window.becomesKeyOnlyIfNeeded = true
window.hidesOnDeactivate = false
window.ignoresMouseEvents = true
window.setFrame(NSRect(x: screenFrame.midX - viewWidth / 2, y: screenFrame.maxY - viewHeight,
                       width: viewWidth, height: viewHeight), display: false)

let notchView = NotchView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: viewHeight))
notchView.notchW = notchWidth
notchView.notchH = menuBarHeight
window.contentView = notchView
window.orderFrontRegardless()

func setPanel(open: Bool) {
    if open { notchView.history = loadHistory() }
    notchView.panelOpen = open
    notchView.hoveredRow = nil
}

func pasteIntoFrontApp() {
    let src = CGEventSource(stateID: .combinedSessionState)
    let vKey: CGKeyCode = 9
    let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
    let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
    down?.flags = .maskCommand
    up?.flags = .maskCommand
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}

notchView.onToggle = { setPanel(open: !notchView.panelOpen) }
notchView.onRowClick = { i, paste in
    guard i < notchView.history.count else { return }
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(notchView.history[i].text, forType: .string)
    notchView.copiedRow = i
    notchView.copiedAt = Date()
    if paste {
        setPanel(open: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { pasteIntoFrontApp() }
    }
}

// Any click outside the panel closes it
NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
    if notchView.panelOpen { setPanel(open: false) }
}

// MARK: - Loop

var frame = 0
let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now(), repeating: .milliseconds(16))
timer.setEventHandler {
    frame += 1

    // State file at ~30 Hz
    if frame % 2 == 0, let content = try? String(contentsOfFile: stateFile, encoding: .utf8) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("recording") {
            notchView.setState(.recording)
            let parts = trimmed.split(separator: ":")
            if parts.count == 2, let level = Double(parts[1]) { notchView.audioLevel = CGFloat(level) }
        } else if let s = IndicatorState(rawValue: trimmed) {
            if s != notchView.state { notchView.audioLevel = 0 }
            notchView.setState(s)
        }
    }

    // Hover: only capture the mouse when it's over the notch or the open panel
    let m = NSEvent.mouseLocation
    let wf = window.frame
    let p = NSPoint(x: m.x - wf.minX, y: wf.maxY - m.y)
    let inside = notchView.hotZone.contains(p)
    notchView.hovering = inside
    notchView.hoveredRow = inside ? notchView.row(at: p) : nil
    window.ignoresMouseEvents = !inside

    notchView.tick()
}
timer.resume()

print("Willow Indicator running (notch drop, notch \(Int(notchWidth))×\(Int(menuBarHeight)))")
print("State file: \(stateFile)")

app.run()
