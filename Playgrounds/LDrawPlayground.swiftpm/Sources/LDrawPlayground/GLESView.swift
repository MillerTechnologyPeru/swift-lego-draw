import SwiftUI
import GLKit
import LDrawGLES

/// UIViewController that owns the ``EAGLRenderingContext``, `GLKView`, and
/// `CADisplayLink`. The display link calls `glkView.display()` each vsync,
/// which invokes `glkView(_:drawIn:)` below — that in turn calls the
/// platform-agnostic ``LDrawGLESRenderer/draw(aspect:)``.
final class GLKHostViewController: UIViewController, GLKViewDelegate {

    let eaglContext: EAGLRenderingContext
    let renderer: LDrawGLESRenderer
    private var glkView: GLKView!
    private var displayLink: CADisplayLink?

    init() {
        guard
            let ctx = EAGLRenderingContext(),
            let r = LDrawGLESRenderer(context: ctx)
        else { fatalError("OpenGL ES 2.0 unavailable") }
        self.eaglContext = ctx
        self.renderer = r
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        glkView = GLKView(frame: .zero, context: eaglContext.eaglContext)
        glkView.drawableDepthFormat = .format24
        glkView.enableSetNeedsDisplay = false
        glkView.delegate = self
        view = glkView

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        glkView.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        glkView.addGestureRecognizer(pinch)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        displayLink = CADisplayLink(target: self, selector: #selector(render))
        displayLink?.add(to: .main, forMode: .common)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func render() { glkView.display() }

    // MARK: - GLKViewDelegate

    nonisolated func glkView(_ view: GLKView, drawIn rect: CGRect) {
        MainActor.assumeIsolated {
            let aspect = Float(rect.width / rect.height)
            renderer.draw(aspect: aspect)
        }
    }

    // MARK: - Gestures

    private var lastPanLocation: CGPoint = .zero

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        let loc = gr.location(in: gr.view)
        if gr.state == .began { lastPanLocation = loc; return }
        let dx = Float(loc.x - lastPanLocation.x) * 0.005
        let dy = Float(loc.y - lastPanLocation.y) * 0.005
        lastPanLocation = loc
        renderer.azimuth   += dx
        renderer.elevation  = max(-1.4, min(1.4, renderer.elevation + dy))
    }

    private var lastPinchScale: CGFloat = 1

    @objc private func handlePinch(_ gr: UIPinchGestureRecognizer) {
        if gr.state == .began { lastPinchScale = gr.scale; return }
        let factor = Float(lastPinchScale / gr.scale)
        lastPinchScale = gr.scale
        renderer.distance = max(renderer.modelRadius * 0.5, renderer.distance * factor)
    }
}

// MARK: - SwiftUI wrapper

struct GLESView: UIViewControllerRepresentable {
    let hostVC: GLKHostViewController

    func makeUIViewController(context: Context) -> GLKHostViewController { hostVC }
    func updateUIViewController(_ uiViewController: GLKHostViewController, context: Context) {}
}
