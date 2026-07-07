#if canImport(Metal)
import Metal
import MetalKit
import simd

/// Uniforms buffer layout — must match MSL `Uniforms` struct.
struct LDrawUniforms {
    var modelViewProjection: float4x4
    var normalMatrix: float4x4
}

/// MTKViewDelegate that renders a pre-built vertex buffer with a Metal pipeline.
public final class LDrawMetalRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {

    // MARK: - Camera state (set by the viewer)
    public var azimuth: Float = 0           // radians, horizontal orbit
    public var elevation: Float = 0.4       // radians, vertical orbit
    public var distance: Float = 500        // from model center in LDU
    public var modelRadius: Float = 200     // used for projection near/far
    public var modelCenter: SIMD3<Float> = .zero  // world-space bounding center

    // MARK: - Private Metal objects
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private var vertexBuffer: MTLBuffer?
    private var vertexCount: Int = 0

    public init?(mtkView: MTKView) {
        guard
            let device = mtkView.device,
            let queue = device.makeCommandQueue()
        else { return nil }

        self.device = device
        self.commandQueue = queue

        // Compile embedded MSL source at runtime — avoids SwiftPM bundle issues with .metal files
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: LDrawMSLSource, options: nil)
        } catch {
            fputs("Metal shader compile error: \(error)\n", stderr)
            return nil
        }
        let vertFn = library.makeFunction(name: "vertex_main")
        let fragFn = library.makeFunction(name: "fragment_main")

        // LDrawMetalVertex layout: SIMD3<Float> is 16 bytes (not 12) due to alignment
        // position @ 0, normal @ 16, color @ 32, stride = 48
        let vd = MTLVertexDescriptor()
        vd.attributes[0].format = .float3
        vd.attributes[0].offset = 0
        vd.attributes[0].bufferIndex = 0
        vd.attributes[1].format = .float3
        vd.attributes[1].offset = 16
        vd.attributes[1].bufferIndex = 0
        vd.attributes[2].format = .float4
        vd.attributes[2].offset = 32
        vd.attributes[2].bufferIndex = 0
        vd.layouts[0].stride = 48
        vd.layouts[0].stepFunction = .perVertex

        let pd = MTLRenderPipelineDescriptor()
        pd.vertexFunction = vertFn
        pd.fragmentFunction = fragFn
        pd.vertexDescriptor = vd
        pd.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        pd.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat

        // Alpha blending for transparent parts
        pd.colorAttachments[0].isBlendingEnabled = true
        pd.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pd.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pd.colorAttachments[0].sourceAlphaBlendFactor = .one
        pd.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: pd) else {
            return nil
        }
        self.pipelineState = pipeline

        let ds = MTLDepthStencilDescriptor()
        ds.depthCompareFunction = .less
        ds.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: ds) else {
            return nil
        }
        self.depthState = depthState

        super.init()

        mtkView.delegate = self
        mtkView.clearColor = MTLClearColorMake(0.15, 0.15, 0.15, 1)
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.colorPixelFormat = .bgra8Unorm
    }

    public func upload(vertices: [LDrawMetalVertex]) {
        guard !vertices.isEmpty else { return }
        vertexCount = vertices.count
        let byteCount = vertices.count * MemoryLayout<LDrawMetalVertex>.stride
        vertexBuffer = device.makeBuffer(bytes: vertices, length: byteCount, options: .storageModeShared)
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let buf = vertexBuffer, vertexCount > 0 else { return }
        guard let cmdBuf = commandQueue.makeCommandBuffer() else { return }
        guard let rpd = view.currentRenderPassDescriptor else { return }
        guard let enc = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else { return }
        guard let drawable = view.currentDrawable else {
            enc.endEncoding(); cmdBuf.commit(); return
        }

        let size = view.drawableSize
        let aspect = Float(size.width / size.height)
        let uniforms = buildUniforms(aspect: aspect)

        enc.setRenderPipelineState(pipelineState)
        enc.setDepthStencilState(depthState)
        enc.setVertexBuffer(buf, offset: 0, index: 0)

        var u = uniforms
        enc.setVertexBytes(&u, length: MemoryLayout<LDrawUniforms>.size, index: 1)

        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        enc.endEncoding()

        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    // MARK: - Camera math

    private func buildUniforms(aspect: Float) -> LDrawUniforms {
        let orbitOffset = SIMD3<Float>(
            distance * cos(elevation) * sin(azimuth),
            distance * sin(elevation),
            distance * cos(elevation) * cos(azimuth)
        )
        let cam = modelCenter + orbitOffset
        let view = lookAt(eye: cam, center: modelCenter, up: SIMD3<Float>(0, -1, 0))
        let nearPlane = max(1.0, distance - modelRadius * 2)
        let farPlane  = distance + modelRadius * 2
        let proj = perspectiveFov(fovY: Float.pi / 4, aspect: aspect, near: nearPlane, far: farPlane)
        let mv = proj * view

        // Normal matrix: upper-left 3×3 of inverse-transpose of view (no non-uniform scale here, so view rotation suffices)
        let n = float4x4(
            SIMD4<Float>(view.columns.0.x, view.columns.0.y, view.columns.0.z, 0),
            SIMD4<Float>(view.columns.1.x, view.columns.1.y, view.columns.1.z, 0),
            SIMD4<Float>(view.columns.2.x, view.columns.2.y, view.columns.2.z, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
        return LDrawUniforms(modelViewProjection: mv, normalMatrix: n)
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
