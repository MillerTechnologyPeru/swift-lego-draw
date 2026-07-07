import SwiftUI
import GLKit
import simd
import LegoDrawFile

@MainActor
final class PlaygroundModel: ObservableObject {
    let eaglContext: EAGLContext
    let renderer: OpenGLESRenderer
    let displayLink: CADisplayLink

    // Stored as a raw pointer so deinit (nonisolated) can safely schedule invalidation
    nonisolated(unsafe) private var _timerRef: Timer?
    @Published var vertexCount: Int = 0

    init() {
        guard
            let ctx = EAGLContext(api: .openGLES2),
            let r = OpenGLESRenderer(context: ctx)
        else {
            fatalError("Could not initialise OpenGL ES 2.0")
        }
        self.eaglContext = ctx
        self.renderer = r

        // CADisplayLink drives GLKView redraws
        let dl = CADisplayLink(target: DisplayLinkTarget(), selector: #selector(DisplayLinkTarget.tick))
        dl.add(to: .main, forMode: .common)
        self.displayLink = dl

        loadEmbeddedModel()

        // Auto-rotate
        _timerRef = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak r] _ in
            r?.azimuth += 0.008
        }
    }

    deinit { _timerRef?.invalidate() }

    private func loadEmbeddedModel() {
        do {
            let (model, defaultColor) = try makeEmbeddedModel(colorCode: 4, colorTable: LDrawColorTable())
            let flattener = LDrawGLESFlattener(colorTable: LDrawColorTable(), defaultColor: defaultColor)
            let vertices = flattener.flatten(model)

            // Compute bounding sphere
            if !vertices.isEmpty {
                var minP = SIMD3<Float>(vertices[0].px, vertices[0].py, vertices[0].pz)
                var maxP = minP
                for v in vertices {
                    let p = SIMD3<Float>(v.px, v.py, v.pz)
                    minP = simd_min(minP, p)
                    maxP = simd_max(maxP, p)
                }
                renderer.modelCenter = (minP + maxP) * 0.5
                renderer.modelRadius = simd_length(maxP - minP) * 0.5
                renderer.distance    = renderer.modelRadius * 3.5
            }

            renderer.upload(vertices: vertices)
            vertexCount = vertices.count
        } catch {
            print("Failed to load embedded model:", error)
        }
    }
}

/// Dummy target for CADisplayLink — we rely on GLKView.enableSetNeedsDisplay = false
/// so that GLKView draws every vsync automatically.
private final class DisplayLinkTarget: NSObject {
    @objc func tick(_ link: CADisplayLink) {}
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var model = PlaygroundModel()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GLESView(renderer: model.renderer, displayLink: model.displayLink)
                .ignoresSafeArea()
                .onAppear {
                    // Trigger first draw
                }

            VStack(alignment: .trailing, spacing: 4) {
                Text("LDraw OpenGL ES")
                    .font(.caption.bold())
                Text("Drag to orbit · Pinch to zoom")
                    .font(.caption2)
                Text("\(model.vertexCount / 3) triangles")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding()
        }
        .background(Color(red: 0.12, green: 0.12, blue: 0.12))
    }
}

#Preview {
    ContentView()
}
