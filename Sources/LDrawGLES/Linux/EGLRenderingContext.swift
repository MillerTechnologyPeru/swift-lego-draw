#if os(Linux)
import CEGL

/// ``GLESRenderingContext`` backed by an EGL display/surface/context triple.
///
/// This does not create a native window itself — pass an `EGLNativeWindowType`
/// obtained from your windowing system (X11, Wayland, GBM/DRM, or an SDL/GLFW
/// window handle) to render into an on-screen surface, or pass `nil` to
/// render into an off-screen pbuffer (useful for headless rendering/testing).
public final class EGLRenderingContext: GLESRenderingContext {
    private let display: EGLDisplay
    private let surface: EGLSurface
    private let eglContext: EGLContext

    public init?(
        nativeWindow: EGLNativeWindowType? = nil,
        nativeDisplay: EGLNativeDisplayType = EGL_DEFAULT_DISPLAY,
        pbufferSize: (width: Int32, height: Int32) = (1, 1)
    ) {
        guard let dpy = eglGetDisplay(nativeDisplay), dpy != EGL_NO_DISPLAY else { return nil }

        var major: EGLint = 0
        var minor: EGLint = 0
        guard eglInitialize(dpy, &major, &minor) == EGL_TRUE else { return nil }
        guard eglBindAPI(EGLenum(EGL_OPENGL_ES_API)) == EGL_TRUE else { return nil }

        let configAttribs: [EGLint] = [
            EGL_SURFACE_TYPE, EGLint(nativeWindow != nil ? EGL_WINDOW_BIT : EGL_PBUFFER_BIT),
            EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
            EGL_RED_SIZE, 8,
            EGL_GREEN_SIZE, 8,
            EGL_BLUE_SIZE, 8,
            EGL_ALPHA_SIZE, 8,
            EGL_DEPTH_SIZE, 24,
            EGL_NONE
        ]

        var config: EGLConfig?
        var numConfigs: EGLint = 0
        guard eglChooseConfig(dpy, configAttribs, &config, 1, &numConfigs) == EGL_TRUE,
              numConfigs > 0, let cfg = config
        else { return nil }

        let surf: EGLSurface
        if let window = nativeWindow {
            surf = eglCreateWindowSurface(dpy, cfg, window, nil)
        } else {
            let pbufferAttribs: [EGLint] = [
                EGL_WIDTH, pbufferSize.width,
                EGL_HEIGHT, pbufferSize.height,
                EGL_NONE
            ]
            surf = eglCreatePbufferSurface(dpy, cfg, pbufferAttribs)
        }
        guard surf != EGL_NO_SURFACE else { return nil }

        let contextAttribs: [EGLint] = [EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE]
        guard let ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, contextAttribs),
              ctx != EGL_NO_CONTEXT
        else { return nil }

        self.display = dpy
        self.surface = surf
        self.eglContext = ctx
    }

    deinit {
        eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT)
        eglDestroyContext(display, eglContext)
        eglDestroySurface(display, surface)
        eglTerminate(display)
    }

    public func makeCurrent() {
        eglMakeCurrent(display, surface, surface, eglContext)
    }

    public func swapBuffers() {
        eglSwapBuffers(display, surface)
    }
}
#endif
