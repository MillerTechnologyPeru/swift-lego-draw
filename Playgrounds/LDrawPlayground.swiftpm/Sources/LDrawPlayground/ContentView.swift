import SwiftUI
import simd
import LegoDrawFile

@MainActor
final class PlaygroundModel: ObservableObject {
    let hostVC: GLKHostViewController
    @Published var vertexCount: Int = 0

    nonisolated(unsafe) private var _autoRotate: Timer?

    init() {
        hostVC = GLKHostViewController()
        loadEmbeddedModel()
        _autoRotate = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.hostVC.renderer.azimuth += 0.008
        }
    }

    deinit { _autoRotate?.invalidate() }

    private func loadEmbeddedModel() {
        let (model, defaultColor, colorTable) = loadModel(colorCode: 4)
        let vertices = LDrawGLESFlattener(colorTable: colorTable, defaultColor: defaultColor).flatten(model)
        guard !vertices.isEmpty else { return }

        var minP = SIMD3<Float>(vertices[0].px, vertices[0].py, vertices[0].pz)
        var maxP = minP
        for v in vertices {
            let p = SIMD3<Float>(v.px, v.py, v.pz)
            minP = simd_min(minP, p)
            maxP = simd_max(maxP, p)
        }
        hostVC.renderer.modelCenter = (minP + maxP) * 0.5
        hostVC.renderer.modelRadius = simd_length(maxP - minP) * 0.5
        hostVC.renderer.distance    = hostVC.renderer.modelRadius * 3.5
        hostVC.renderer.upload(vertices: vertices)
        vertexCount = vertices.count
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var model = PlaygroundModel()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GLESView(hostVC: model.hostVC)
                .ignoresSafeArea()

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
