#if os(iOS) || os(tvOS)
import GLKit

/// ``GLESRenderingContext`` backed by an `EAGLContext`. Presentation is
/// handled by `GLKView` itself (when driven by a `CADisplayLink` calling
/// `glkView.display()`), so ``swapBuffers()`` is a no-op here.
public final class EAGLRenderingContext: GLESRenderingContext {
    public let eaglContext: EAGLContext

    public init?() {
        guard let ctx = EAGLContext(api: .openGLES2) else { return nil }
        self.eaglContext = ctx
    }

    public func makeCurrent() {
        EAGLContext.setCurrent(eaglContext)
    }

    public func swapBuffers() {
        // GLKView presents the drawable itself; nothing to do here.
    }
}
#endif
