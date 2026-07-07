#if os(iOS) || os(tvOS) || os(Linux)

#if canImport(OpenGLES)
import OpenGLES
#elseif canImport(CGLES2)
import CGLES2
#endif
import simd

// MARK: - Shaders

private let vertexShaderSrc = """
attribute vec3 aPosition;
attribute vec3 aNormal;
attribute vec4 aColor;

uniform mat4 uMVP;
uniform mat4 uNormalMatrix;

varying vec3 vNormal;
varying vec4 vColor;

void main() {
    gl_Position = uMVP * vec4(aPosition, 1.0);
    vNormal = normalize((uNormalMatrix * vec4(aNormal, 0.0)).xyz);
    vColor = aColor;
}
"""

private let fragmentShaderSrc = """
precision mediump float;

varying vec3 vNormal;
varying vec4 vColor;

void main() {
    vec3 keyDir  = normalize(vec3( 1.0,  2.0,  1.5));
    vec3 fillDir = normalize(vec3(-1.0, -0.5, -1.0));
    vec3 n = normalize(vNormal);
    float key    = max(dot(n, keyDir),  0.0) * 0.75;
    float fill   = max(dot(n, fillDir), 0.0) * 0.25;
    float ambient = 0.2;
    vec3 rgb = vColor.rgb * (ambient + key + fill);
    gl_FragColor = vec4(rgb, vColor.a);
}
"""

// MARK: - Renderer

/// OpenGL ES 2.0 renderer that draws a pre-built vertex buffer.
///
/// This class contains no platform-specific windowing or context-management
/// code — it only issues `gl*` calls, which are identical between Apple's
/// `OpenGLES` framework (iOS/tvOS) and Linux's `libGLESv2` (via the `CGLES2`
/// system-library shim). Context creation/lifetime and buffer presentation
/// are delegated to a ``GLESRenderingContext`` supplied by the caller —
/// ``EAGLRenderingContext`` on Apple platforms, ``EGLRenderingContext`` on
/// Linux.
public final class LDrawGLESRenderer {

    // MARK: - Camera (set externally)
    public var azimuth: Float = 0
    public var elevation: Float = 0.4
    public var distance: Float = 100
    public var modelCenter = SIMD3<Float>.zero
    public var modelRadius: Float = 50

    private let context: any GLESRenderingContext
    private var program: GLuint = 0
    private var vbo: GLuint = 0
    private var vertexCount: Int = 0

    // Uniform locations
    private var mvpLoc: GLint = 0
    private var normalMatrixLoc: GLint = 0

    // Attribute locations
    private let positionAttr: GLuint = 0
    private let normalAttr:   GLuint = 1
    private let colorAttr:    GLuint = 2

    public init?(context: any GLESRenderingContext) {
        self.context = context
        context.makeCurrent()
        guard setupShaders() else { return nil }
        glEnable(GLenum(GL_DEPTH_TEST))
        glDepthFunc(GLenum(GL_LESS))
        glEnable(GLenum(GL_BLEND))
        glBlendFunc(GLenum(GL_SRC_ALPHA), GLenum(GL_ONE_MINUS_SRC_ALPHA))
        glClearColor(0.12, 0.12, 0.12, 1)
    }

    deinit {
        context.makeCurrent()
        if vbo != 0 { glDeleteBuffers(1, &vbo) }
        if program != 0 { glDeleteProgram(program) }
    }

    // MARK: - Upload

    public func upload(vertices: [GLESVertex]) {
        context.makeCurrent()
        vertexCount = vertices.count
        if vbo == 0 { glGenBuffers(1, &vbo) }
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vbo)
        let byteCount = vertices.count * MemoryLayout<GLESVertex>.stride
        glBufferData(GLenum(GL_ARRAY_BUFFER), byteCount, vertices, GLenum(GL_STATIC_DRAW))
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)
    }

    // MARK: - Draw

    /// Renders one frame at the given viewport aspect ratio (width / height)
    /// and presents it. The caller is responsible for calling this once per
    /// frame — e.g. from a `CADisplayLink` callback on Apple platforms, or
    /// from a render loop driving an EGL surface on Linux.
    public func draw(aspect: Float) {
        context.makeCurrent()
        guard vertexCount > 0 else {
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT))
            context.swapBuffers()
            return
        }

        glClear(GLbitfield(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT))
        glUseProgram(program)

        let (mvp, normalMat) = buildMatrices(aspect: aspect)

        withUnsafeBytes(of: mvp) { ptr in
            glUniformMatrix4fv(mvpLoc, 1, GLboolean(GL_FALSE),
                               ptr.bindMemory(to: Float.self).baseAddress)
        }
        withUnsafeBytes(of: normalMat) { ptr in
            glUniformMatrix4fv(normalMatrixLoc, 1, GLboolean(GL_FALSE),
                               ptr.bindMemory(to: Float.self).baseAddress)
        }

        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vbo)
        let stride = GLsizei(MemoryLayout<GLESVertex>.stride)

        glEnableVertexAttribArray(positionAttr)
        glVertexAttribPointer(positionAttr, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), stride,
                              UnsafeRawPointer(bitPattern: 0))

        glEnableVertexAttribArray(normalAttr)
        glVertexAttribPointer(normalAttr, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), stride,
                              UnsafeRawPointer(bitPattern: 12))

        glEnableVertexAttribArray(colorAttr)
        glVertexAttribPointer(colorAttr, 4, GLenum(GL_FLOAT), GLboolean(GL_FALSE), stride,
                              UnsafeRawPointer(bitPattern: 24))

        glDrawArrays(GLenum(GL_TRIANGLES), 0, GLsizei(vertexCount))

        glDisableVertexAttribArray(positionAttr)
        glDisableVertexAttribArray(normalAttr)
        glDisableVertexAttribArray(colorAttr)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)

        context.swapBuffers()
    }

    // MARK: - Camera math

    private func buildMatrices(aspect: Float) -> (mvp: float4x4, normal: float4x4) {
        let orbitOffset = SIMD3<Float>(
            distance * cos(elevation) * sin(azimuth),
            distance * sin(elevation),
            distance * cos(elevation) * cos(azimuth)
        )
        let eye = modelCenter + orbitOffset
        let view = lookAt(eye: eye, center: modelCenter, up: SIMD3<Float>(0, -1, 0))
        let near = max(1.0, distance - modelRadius * 2)
        let far  = distance + modelRadius * 2
        let proj = perspectiveFov(fovY: .pi / 4, aspect: aspect, near: near, far: far)
        let mvp  = proj * view
        // Normal matrix = upper-left 3x3 of view rotation
        let n = float4x4(columns: (
            SIMD4<Float>(view.columns.0.x, view.columns.0.y, view.columns.0.z, 0),
            SIMD4<Float>(view.columns.1.x, view.columns.1.y, view.columns.1.z, 0),
            SIMD4<Float>(view.columns.2.x, view.columns.2.y, view.columns.2.z, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
        return (mvp, n)
    }

    // MARK: - Shader setup

    private func setupShaders() -> Bool {
        guard
            let vert = compile(src: vertexShaderSrc,  type: GLenum(GL_VERTEX_SHADER)),
            let frag = compile(src: fragmentShaderSrc, type: GLenum(GL_FRAGMENT_SHADER))
        else { return false }

        let prog = glCreateProgram()
        glAttachShader(prog, vert)
        glAttachShader(prog, frag)

        // Bind attribute locations before linking
        glBindAttribLocation(prog, positionAttr, "aPosition")
        glBindAttribLocation(prog, normalAttr,   "aNormal")
        glBindAttribLocation(prog, colorAttr,    "aColor")

        glLinkProgram(prog)
        glDeleteShader(vert)
        glDeleteShader(frag)

        var status: GLint = 0
        glGetProgramiv(prog, GLenum(GL_LINK_STATUS), &status)
        guard status == GL_TRUE else {
            var log = [GLchar](repeating: 0, count: 512)
            glGetProgramInfoLog(prog, 512, nil, &log)
            print("Shader link error:", String(cString: log))
            glDeleteProgram(prog)
            return false
        }

        program = prog
        mvpLoc          = glGetUniformLocation(prog, "uMVP")
        normalMatrixLoc = glGetUniformLocation(prog, "uNormalMatrix")
        return true
    }

    private func compile(src: String, type: GLenum) -> GLuint? {
        let shader = glCreateShader(type)
        src.withCString { cStr in
            var mutableCStr: UnsafePointer<GLchar>? = cStr
            glShaderSource(shader, 1, &mutableCStr, nil)
        }
        glCompileShader(shader)
        var status: GLint = 0
        glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &status)
        if status != GL_TRUE {
            var log = [GLchar](repeating: 0, count: 512)
            glGetShaderInfoLog(shader, 512, nil, &log)
            print("Shader compile error:", String(cString: log))
            glDeleteShader(shader)
            return nil
        }
        return shader
    }
}

// MARK: - Matrix helpers

private func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> float4x4 {
    let f = simd_normalize(center - eye)
    let r = simd_normalize(simd_cross(f, up))
    let u = simd_cross(r, f)
    return float4x4(columns: (
        SIMD4<Float>( r.x,  u.x, -f.x, 0),
        SIMD4<Float>( r.y,  u.y, -f.y, 0),
        SIMD4<Float>( r.z,  u.z, -f.z, 0),
        SIMD4<Float>(-simd_dot(r, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)
    ))
}

private func perspectiveFov(fovY: Float, aspect: Float, near: Float, far: Float) -> float4x4 {
    let y = 1 / tan(fovY * 0.5)
    let x = y / aspect
    let z = far / (near - far)
    return float4x4(columns: (
        SIMD4<Float>(x, 0,  0,  0),
        SIMD4<Float>(0, y,  0,  0),
        SIMD4<Float>(0, 0,  z, -1),
        SIMD4<Float>(0, 0,  z * near, 0)
    ))
}

#endif
