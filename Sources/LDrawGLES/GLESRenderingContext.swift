#if os(iOS) || os(tvOS) || os(Linux)

/// Abstracts an OpenGL ES 2.0 rendering context so ``LDrawGLESRenderer`` can
/// stay platform-agnostic: on Apple platforms this wraps an `EAGLContext`
/// (see ``EAGLRenderingContext``); on Linux it wraps an EGL display/surface/
/// context triple (see ``EGLRenderingContext``).
public protocol GLESRenderingContext: AnyObject {
    /// Makes this context current on the calling thread. Must be called
    /// before issuing any `gl*` calls, including setup and teardown.
    func makeCurrent()

    /// Presents the back buffer. On Apple platforms this is normally a
    /// no-op — `GLKView` handles presentation itself when driven by a
    /// `CADisplayLink` — but EGL-backed contexts must call
    /// `eglSwapBuffers` explicitly.
    func swapBuffers()
}

#endif
