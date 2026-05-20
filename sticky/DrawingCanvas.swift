import SwiftUI
import AppKit

/// Pure SwiftUI drawing overlay. Replaces the prior NSViewRepresentable
/// implementation, which had hit-testing races inside NSHostingView. Uses
/// SwiftUI's `Canvas` for rendering and `DragGesture` for input. When
/// `isDrawing` is false, `.allowsHitTesting(false)` makes clicks pass
/// straight through to the text editor below — no ambiguity, no race.
struct DrawingOverlay: View {
    @Binding var strokes: [Stroke]
    @Binding var isDrawing: Bool

    @State private var currentPoints: [CGPoint] = []

    /// Color and width are fixed for now. If we ever want per-note brush
    /// settings, surface these as parameters.
    private let brushColor: Color = .black.opacity(0.85)
    private let brushWidth: CGFloat = 2

    var body: some View {
        Canvas { context, _ in
            // Finished strokes
            for stroke in strokes {
                guard !stroke.points.isEmpty else { continue }
                var path = Path()
                path.move(to: CGPoint(x: stroke.points[0].x, y: stroke.points[0].y))
                for p in stroke.points.dropFirst() {
                    path.addLine(to: CGPoint(x: p.x, y: p.y))
                }
                context.stroke(
                    path,
                    with: .color(Color(NSColor(hexString: stroke.colorHex))),
                    style: StrokeStyle(lineWidth: stroke.width,
                                       lineCap: .round, lineJoin: .round)
                )
            }
            // In-progress stroke
            if currentPoints.count >= 1 {
                var path = Path()
                path.move(to: currentPoints[0])
                for p in currentPoints.dropFirst() {
                    path.addLine(to: p)
                }
                // Special case: a single point (tap with no drag) — draw as a dot.
                if currentPoints.count == 1 {
                    let p = currentPoints[0]
                    path.move(to: p)
                    path.addLine(to: CGPoint(x: p.x + 0.5, y: p.y + 0.5))
                }
                context.stroke(
                    path,
                    with: .color(brushColor),
                    style: StrokeStyle(lineWidth: brushWidth,
                                       lineCap: .round, lineJoin: .round)
                )
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    guard isDrawing else { return }
                    currentPoints.append(value.location)
                }
                .onEnded { _ in
                    guard isDrawing, !currentPoints.isEmpty else {
                        currentPoints = []
                        return
                    }
                    let pts = currentPoints.map {
                        StrokePoint(x: Double($0.x), y: Double($0.y))
                    }
                    strokes.append(Stroke(
                        points: pts,
                        colorHex: "#000000",
                        width: Double(brushWidth)
                    ))
                    currentPoints = []
                }
        )
        // When not drawing, become invisible to clicks so the text editor
        // beneath receives them.
        .allowsHitTesting(isDrawing)
    }
}

// MARK: - NSColor hex helpers
// (Kept here since Stroke uses a hex string and other files reference these.)

extension NSColor {
    /// Convenience init from "#RRGGBB" or "RRGGBB".
    convenience init(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        self.init(
            red:   CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8)  & 0xFF) / 255.0,
            blue:  CGFloat(rgb         & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(round(rgb.redComponent   * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent  * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
