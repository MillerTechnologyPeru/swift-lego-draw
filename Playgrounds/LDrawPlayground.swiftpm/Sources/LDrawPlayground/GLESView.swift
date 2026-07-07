import SwiftUI
import GLKit

/// SwiftUI wrapper around a `GLKView` that drives the OpenGL ES renderer.
struct GLESView: UIViewRepresentable {
    let renderer: OpenGLESRenderer
    let displayLink: CADisplayLink

    init(renderer: OpenGLESRenderer, displayLink: CADisplayLink) {
        self.renderer = renderer
        self.displayLink = displayLink
    }

    func makeUIView(context: Context) -> GLKView {
        guard let eaglContext = EAGLContext(api: .openGLES2) else {
            fatalError("OpenGL ES 2.0 not available")
        }
        let view = GLKView(frame: .zero, context: eaglContext)
        view.drawableDepthFormat = .format24
        view.delegate = renderer
        view.enableSetNeedsDisplay = false

        // Drag to orbit
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(pan)

        // Pinch to zoom
        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                              action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinch)

        return view
    }

    func updateUIView(_ uiView: GLKView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer)
    }

    // MARK: - Gesture coordinator

    final class Coordinator: NSObject {
        let renderer: OpenGLESRenderer
        private var lastPanLocation: CGPoint = .zero
        private var lastPinchScale: CGFloat = 1

        init(renderer: OpenGLESRenderer) {
            self.renderer = renderer
        }

        @objc func handlePan(_ gr: UIPanGestureRecognizer) {
            let loc = gr.location(in: gr.view)
            if gr.state == .began { lastPanLocation = loc; return }
            let dx = Float(loc.x - lastPanLocation.x) * 0.005
            let dy = Float(loc.y - lastPanLocation.y) * 0.005
            lastPanLocation = loc
            renderer.azimuth   += dx
            renderer.elevation  = max(-1.4, min(1.4, renderer.elevation + dy))
        }

        @objc func handlePinch(_ gr: UIPinchGestureRecognizer) {
            if gr.state == .began { lastPinchScale = gr.scale; return }
            let factor = Float(lastPinchScale / gr.scale)
            lastPinchScale = gr.scale
            renderer.distance = max(renderer.modelRadius * 0.5,
                                    renderer.distance * factor)
        }
    }
}
