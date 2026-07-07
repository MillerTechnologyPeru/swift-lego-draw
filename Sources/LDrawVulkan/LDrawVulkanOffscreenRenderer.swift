#if os(Linux) || os(Android)
#if os(Android)
import Android
#else
import Glibc
#endif
import Foundation
import CVulkan
import LegoDrawFile

/// Renders a flattened LDraw model into an off-screen RGBA8 color image
/// (with a real depth buffer) and reads the result back to host memory.
///
/// This has no windowing-system dependency — it's the Vulkan equivalent of
/// `RenderLDrawModel`'s SceneKit snapshot path, suitable for headless
/// rendering (CI, screenshots, testing). On-screen presentation via a
/// `VkSurfaceKHR` supplied by a window toolkit (SDL, GLFW, XCB, Wayland) is
/// a natural extension point but out of scope here.
public final class LDrawVulkanOffscreenRenderer {

    // MARK: - Camera (set externally, same convention as the GLES/Metal renderers)
    public var azimuth: Float = 0
    public var elevation: Float = 0.4
    public var distance: Float = 100
    public var modelCenter = Vector3.zero
    public var modelRadius: Float = 50

    public let width: Int
    public let height: Int

    private let context: LDrawVulkanContext
    private var device: VkDevice { context.device }

    private var colorImage: VkImage!
    private var colorImageMemory: VkDeviceMemory!
    private var colorImageView: VkImageView!
    private var depthImage: VkImage!
    private var depthImageMemory: VkDeviceMemory!
    private var depthImageView: VkImageView!
    private var renderPass: VkRenderPass!
    private var framebuffer: VkFramebuffer!

    private var descriptorSetLayout: VkDescriptorSetLayout!
    private var pipelineLayout: VkPipelineLayout!
    private var pipeline: VkPipeline!
    private var descriptorPool: VkDescriptorPool!
    private var descriptorSet: VkDescriptorSet!

    private var vertexBuffer: VkBuffer?
    private var vertexBufferMemory: VkDeviceMemory?
    private var vertexCount: Int = 0

    private var uniformBuffer: VkBuffer!
    private var uniformBufferMemory: VkDeviceMemory!

    private var readbackBuffer: VkBuffer!
    private var readbackBufferMemory: VkDeviceMemory!

    private var commandBuffer: VkCommandBuffer!
    private var fence: VkFence!

    private static let colorFormat = VK_FORMAT_R8G8B8A8_UNORM
    private static let depthFormat = VK_FORMAT_D32_SFLOAT

    /// Directory to look for `triangle.vert.spv`/`triangle.frag.spv` in, overriding the default
    /// `Bundle.module` lookup. Needed on Android: `Bundle.module`'s generated accessor resolves
    /// paths relative to `Bundle.main`, which isn't meaningful for a shared library loaded via
    /// JNI into a host `app_process` — there the caller extracts the shaders from the APK's
    /// assets to a known filesystem directory and passes it here instead.
    private let shaderDirectory: URL?

    public init?(context: LDrawVulkanContext, width: Int, height: Int, shaderDirectory: URL? = nil) {
        self.context = context
        self.width = width
        self.height = height
        self.shaderDirectory = shaderDirectory

        guard createAttachments() else { return nil }
        guard createRenderPass() else { return nil }
        guard createFramebuffer() else { return nil }
        guard createUniformBuffer() else { return nil }
        guard createDescriptorSet() else { return nil }
        guard createPipeline() else { return nil }
        guard createReadbackBuffer() else { return nil }
        guard createCommandBufferAndFence() else { return nil }
    }

    deinit {
        vkDestroyFence(device, fence, nil)
        vkFreeCommandBuffers(device, context.commandPool, 1, [commandBuffer])
        vkDestroyBuffer(device, readbackBuffer, nil)
        vkFreeMemory(device, readbackBufferMemory, nil)
        if let vb = vertexBuffer { vkDestroyBuffer(device, vb, nil) }
        if let vbm = vertexBufferMemory { vkFreeMemory(device, vbm, nil) }
        vkDestroyBuffer(device, uniformBuffer, nil)
        vkFreeMemory(device, uniformBufferMemory, nil)
        vkDestroyDescriptorPool(device, descriptorPool, nil)
        vkDestroyPipeline(device, pipeline, nil)
        vkDestroyPipelineLayout(device, pipelineLayout, nil)
        vkDestroyDescriptorSetLayout(device, descriptorSetLayout, nil)
        vkDestroyFramebuffer(device, framebuffer, nil)
        vkDestroyRenderPass(device, renderPass, nil)
        vkDestroyImageView(device, depthImageView, nil)
        vkDestroyImage(device, depthImage, nil)
        vkFreeMemory(device, depthImageMemory, nil)
        vkDestroyImageView(device, colorImageView, nil)
        vkDestroyImage(device, colorImage, nil)
        vkFreeMemory(device, colorImageMemory, nil)
    }

    // MARK: - Upload

    public func upload(vertices: [LDrawVulkanVertex]) {
        if let vb = vertexBuffer { vkDestroyBuffer(device, vb, nil) }
        if let vbm = vertexBufferMemory { vkFreeMemory(device, vbm, nil) }
        vertexBuffer = nil
        vertexBufferMemory = nil
        vertexCount = vertices.count
        guard !vertices.isEmpty else { return }

        let byteCount = vertices.count * MemoryLayout<LDrawVulkanVertex>.stride
        let (buffer, memory) = createBuffer(
            size: byteCount,
            usage: UInt32(VK_BUFFER_USAGE_VERTEX_BUFFER_BIT.rawValue),
            properties: UInt32(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.rawValue)
        )
        guard let buffer, let memory else { return }

        var mapped: UnsafeMutableRawPointer? = nil
        vkMapMemory(device, memory, 0, VkDeviceSize(byteCount), 0, &mapped)
        vertices.withUnsafeBytes { src in
            mapped?.copyMemory(from: src.baseAddress!, byteCount: byteCount)
        }
        vkUnmapMemory(device, memory)

        vertexBuffer = buffer
        vertexBufferMemory = memory
    }

    // MARK: - Draw + readback

    /// Renders one frame and returns tightly-packed RGBA8 pixels,
    /// `width * height * 4` bytes, row-major top-to-bottom.
    public func renderToRGBA() -> [UInt8] {
        updateUniforms()

        vkResetFences(device, 1, [fence])
        vkResetCommandBuffer(commandBuffer, 0)

        var beginInfo = VkCommandBufferBeginInfo()
        beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
        vkBeginCommandBuffer(commandBuffer, &beginInfo)

        var clearValues = [VkClearValue](repeating: VkClearValue(), count: 2)
        clearValues[0].color.float32 = (0.12, 0.12, 0.12, 1.0)
        clearValues[1].depthStencil = VkClearDepthStencilValue(depth: 1.0, stencil: 0)

        clearValues.withUnsafeBufferPointer { clearPtr in
            var rpBegin = VkRenderPassBeginInfo()
            rpBegin.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO
            rpBegin.renderPass = renderPass
            rpBegin.framebuffer = framebuffer
            rpBegin.renderArea = VkRect2D(offset: VkOffset2D(x: 0, y: 0),
                                           extent: VkExtent2D(width: UInt32(width), height: UInt32(height)))
            rpBegin.clearValueCount = 2
            rpBegin.pClearValues = clearPtr.baseAddress
            vkCmdBeginRenderPass(commandBuffer, &rpBegin, VK_SUBPASS_CONTENTS_INLINE)
        }

        vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline)

        var viewport = VkViewport(x: 0, y: 0, width: Float(width), height: Float(height), minDepth: 0, maxDepth: 1)
        vkCmdSetViewport(commandBuffer, 0, 1, &viewport)
        var scissor = VkRect2D(offset: VkOffset2D(x: 0, y: 0), extent: VkExtent2D(width: UInt32(width), height: UInt32(height)))
        vkCmdSetScissor(commandBuffer, 0, 1, &scissor)

        var descSet: VkDescriptorSet? = descriptorSet
        vkCmdBindDescriptorSets(commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, pipelineLayout, 0, 1, &descSet, 0, nil)

        if let vb = vertexBuffer, vertexCount > 0 {
            var buffers: [VkBuffer?] = [vb]
            var offsets: [VkDeviceSize] = [0]
            vkCmdBindVertexBuffers(commandBuffer, 0, 1, &buffers, &offsets)
            vkCmdDraw(commandBuffer, UInt32(vertexCount), 1, 0, 0)
        }

        vkCmdEndRenderPass(commandBuffer)

        transitionAndCopyToReadback(commandBuffer: commandBuffer)

        vkEndCommandBuffer(commandBuffer)

        var cmdBuf: VkCommandBuffer? = commandBuffer
        var submitInfo = VkSubmitInfo()
        submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO
        submitInfo.commandBufferCount = 1
        withUnsafePointer(to: &cmdBuf) { ptr in
            submitInfo.pCommandBuffers = ptr
            vkQueueSubmit(context.graphicsQueue, 1, &submitInfo, fence)
        }
        vkWaitForFences(device, 1, [fence], VkBool32(VK_TRUE), UInt64.max)

        return readPixels()
    }

    // MARK: - Attachments

    private func createAttachments() -> Bool {
        guard let (img, mem) = createImage(
            format: Self.colorFormat,
            usage: UInt32(VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue | VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue)
        ) else { return false }
        colorImage = img; colorImageMemory = mem
        guard let civ = createImageView(image: img, format: Self.colorFormat, aspect: UInt32(VK_IMAGE_ASPECT_COLOR_BIT.rawValue))
        else { return false }
        colorImageView = civ

        guard let (dimg, dmem) = createImage(
            format: Self.depthFormat,
            usage: UInt32(VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT.rawValue)
        ) else { return false }
        depthImage = dimg; depthImageMemory = dmem
        guard let div = createImageView(image: dimg, format: Self.depthFormat, aspect: UInt32(VK_IMAGE_ASPECT_DEPTH_BIT.rawValue))
        else { return false }
        depthImageView = div

        return true
    }

    private func createImage(format: VkFormat, usage: VkImageUsageFlags) -> (VkImage, VkDeviceMemory)? {
        var info = VkImageCreateInfo()
        info.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO
        info.imageType = VK_IMAGE_TYPE_2D
        info.format = format
        info.extent = VkExtent3D(width: UInt32(width), height: UInt32(height), depth: 1)
        info.mipLevels = 1
        info.arrayLayers = 1
        info.samples = VK_SAMPLE_COUNT_1_BIT
        info.tiling = VK_IMAGE_TILING_OPTIMAL
        info.usage = usage
        info.sharingMode = VK_SHARING_MODE_EXCLUSIVE
        info.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED

        var image: VkImage? = nil
        guard vkCreateImage(device, &info, nil, &image) == VK_SUCCESS, let image else { return nil }

        var req = VkMemoryRequirements()
        vkGetImageMemoryRequirements(device, image, &req)
        guard let typeIndex = context.findMemoryType(
            typeBits: req.memoryTypeBits,
            properties: UInt32(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT.rawValue)
        ) else { return nil }

        var allocInfo = VkMemoryAllocateInfo()
        allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
        allocInfo.allocationSize = req.size
        allocInfo.memoryTypeIndex = typeIndex
        var memory: VkDeviceMemory? = nil
        guard vkAllocateMemory(device, &allocInfo, nil, &memory) == VK_SUCCESS, let memory else { return nil }
        vkBindImageMemory(device, image, memory, 0)
        return (image, memory)
    }

    private func createImageView(image: VkImage, format: VkFormat, aspect: VkImageAspectFlags) -> VkImageView? {
        var info = VkImageViewCreateInfo()
        info.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
        info.image = image
        info.viewType = VK_IMAGE_VIEW_TYPE_2D
        info.format = format
        info.subresourceRange = VkImageSubresourceRange(
            aspectMask: aspect, baseMipLevel: 0, levelCount: 1, baseArrayLayer: 0, layerCount: 1
        )
        var view: VkImageView? = nil
        guard vkCreateImageView(device, &info, nil, &view) == VK_SUCCESS else { return nil }
        return view
    }

    // MARK: - Render pass + framebuffer

    private func createRenderPass() -> Bool {
        var colorAttachment = VkAttachmentDescription()
        colorAttachment.format = Self.colorFormat
        colorAttachment.samples = VK_SAMPLE_COUNT_1_BIT
        colorAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR
        colorAttachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE
        colorAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
        colorAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
        colorAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
        colorAttachment.finalLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL

        var depthAttachment = VkAttachmentDescription()
        depthAttachment.format = Self.depthFormat
        depthAttachment.samples = VK_SAMPLE_COUNT_1_BIT
        depthAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR
        depthAttachment.storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
        depthAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
        depthAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
        depthAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
        depthAttachment.finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL

        var colorRef = VkAttachmentReference(attachment: 0, layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL)
        var depthRef = VkAttachmentReference(attachment: 1, layout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL)

        var subpass = VkSubpassDescription()
        subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS
        subpass.colorAttachmentCount = 1

        let attachments = [colorAttachment, depthAttachment]
        var result: VkResult = VK_ERROR_UNKNOWN
        var createdPass: VkRenderPass? = nil
        attachments.withUnsafeBufferPointer { attachPtr in
            withUnsafePointer(to: &colorRef) { colorRefPtr in
                withUnsafePointer(to: &depthRef) { depthRefPtr in
                    subpass.pColorAttachments = colorRefPtr
                    subpass.pDepthStencilAttachment = depthRefPtr
                    withUnsafePointer(to: &subpass) { subpassPtr in
                        var rpInfo = VkRenderPassCreateInfo()
                        rpInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO
                        rpInfo.attachmentCount = UInt32(attachments.count)
                        rpInfo.pAttachments = attachPtr.baseAddress
                        rpInfo.subpassCount = 1
                        rpInfo.pSubpasses = subpassPtr
                        result = vkCreateRenderPass(device, &rpInfo, nil, &createdPass)
                    }
                }
            }
        }
        guard result == VK_SUCCESS, let pass = createdPass else { return false }
        renderPass = pass
        return true
    }

    private func createFramebuffer() -> Bool {
        let attachments: [VkImageView?] = [colorImageView, depthImageView]
        var fb: VkFramebuffer? = nil
        let result: VkResult = attachments.withUnsafeBufferPointer { attachPtr in
            var info = VkFramebufferCreateInfo()
            info.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO
            info.renderPass = renderPass
            info.attachmentCount = UInt32(attachments.count)
            info.pAttachments = attachPtr.baseAddress
            info.width = UInt32(width)
            info.height = UInt32(height)
            info.layers = 1
            return vkCreateFramebuffer(device, &info, nil, &fb)
        }
        guard result == VK_SUCCESS, let framebuffer = fb else { return false }
        self.framebuffer = framebuffer
        return true
    }

    // MARK: - Uniforms + descriptors

    private func createUniformBuffer() -> Bool {
        // Two mat4 (16 floats each) = 128 bytes
        let size = MemoryLayout<Float>.stride * 32
        let (buf, mem) = createBuffer(
            size: size,
            usage: UInt32(VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT.rawValue),
            properties: UInt32(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.rawValue)
        )
        guard let buf, let mem else { return false }
        uniformBuffer = buf
        uniformBufferMemory = mem
        return true
    }

    private func createDescriptorSet() -> Bool {
        var binding = VkDescriptorSetLayoutBinding()
        binding.binding = 0
        binding.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
        binding.descriptorCount = 1
        binding.stageFlags = UInt32(VK_SHADER_STAGE_VERTEX_BIT.rawValue)

        var layout: VkDescriptorSetLayout? = nil
        let layoutResult: VkResult = withUnsafePointer(to: &binding) { bindingPtr in
            var info = VkDescriptorSetLayoutCreateInfo()
            info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
            info.bindingCount = 1
            info.pBindings = bindingPtr
            return vkCreateDescriptorSetLayout(device, &info, nil, &layout)
        }
        guard layoutResult == VK_SUCCESS, let descriptorSetLayout = layout else { return false }
        self.descriptorSetLayout = descriptorSetLayout

        var poolSize = VkDescriptorPoolSize(type: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, descriptorCount: 1)
        var pool: VkDescriptorPool? = nil
        let poolResult: VkResult = withUnsafePointer(to: &poolSize) { poolSizePtr in
            var info = VkDescriptorPoolCreateInfo()
            info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO
            info.maxSets = 1
            info.poolSizeCount = 1
            info.pPoolSizes = poolSizePtr
            return vkCreateDescriptorPool(device, &info, nil, &pool)
        }
        guard poolResult == VK_SUCCESS, let descriptorPool = pool else { return false }
        self.descriptorPool = descriptorPool

        var setLayout: VkDescriptorSetLayout? = descriptorSetLayout
        var allocatedSet: VkDescriptorSet? = nil
        let allocResult: VkResult = withUnsafePointer(to: &setLayout) { layoutPtr in
            var allocInfo = VkDescriptorSetAllocateInfo()
            allocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO
            allocInfo.descriptorPool = descriptorPool
            allocInfo.descriptorSetCount = 1
            allocInfo.pSetLayouts = layoutPtr
            return vkAllocateDescriptorSets(device, &allocInfo, &allocatedSet)
        }
        guard allocResult == VK_SUCCESS, let descriptorSet = allocatedSet else { return false }
        self.descriptorSet = descriptorSet

        var bufferInfo = VkDescriptorBufferInfo(buffer: uniformBuffer, offset: 0, range: VkDeviceSize(MemoryLayout<Float>.stride * 32))
        withUnsafePointer(to: &bufferInfo) { bufferInfoPtr in
            var write = VkWriteDescriptorSet()
            write.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
            write.dstSet = descriptorSet
            write.dstBinding = 0
            write.descriptorCount = 1
            write.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
            write.pBufferInfo = bufferInfoPtr
            vkUpdateDescriptorSets(device, 1, &write, 0, nil)
        }
        return true
    }

    private func updateUniforms() {
        let orbitOffset = Vector3(
            x: distance * cosf(elevation) * sinf(azimuth),
            y: distance * sinf(elevation),
            z: distance * cosf(elevation) * cosf(azimuth)
        )
        let eye = modelCenter + orbitOffset
        let view = lookAt(eye: eye, center: modelCenter, up: Vector3(x: 0, y: -1, z: 0))
        let near = max(1.0, distance - modelRadius * 2)
        let far = distance + modelRadius * 2
        let proj = perspectiveVulkan(fovY: .pi / 4, aspect: Float(width) / Float(height), near: near, far: far)
        let mvp = proj * view
        let normalMatrix = Mat4(m: [
            view.m[0], view.m[1], view.m[2], 0,
            view.m[4], view.m[5], view.m[6], 0,
            view.m[8], view.m[9], view.m[10], 0,
            0, 0, 0, 1
        ])

        let data = mvp.m + normalMatrix.m
        var mapped: UnsafeMutableRawPointer? = nil
        vkMapMemory(device, uniformBufferMemory, 0, VkDeviceSize(data.count * MemoryLayout<Float>.stride), 0, &mapped)
        data.withUnsafeBytes { src in
            mapped?.copyMemory(from: src.baseAddress!, byteCount: src.count)
        }
        vkUnmapMemory(device, uniformBufferMemory)
    }

    // MARK: - Pipeline

    private func createPipeline() -> Bool {
        guard
            let vertModule = loadShaderModule(named: "triangle.vert.spv"),
            let fragModule = loadShaderModule(named: "triangle.frag.spv")
        else {
            logToStderr("LDrawVulkan: missing compiled shaders (run Sources/LDrawVulkan/Shaders/compile.sh)\n")
            return false
        }
        defer {
            vkDestroyShaderModule(device, vertModule, nil)
            vkDestroyShaderModule(device, fragModule, nil)
        }

        var setLayout: VkDescriptorSetLayout? = descriptorSetLayout
        var layout: VkPipelineLayout? = nil
        let layoutResult: VkResult = withUnsafePointer(to: &setLayout) { layoutPtr in
            var info = VkPipelineLayoutCreateInfo()
            info.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO
            info.setLayoutCount = 1
            info.pSetLayouts = layoutPtr
            return vkCreatePipelineLayout(device, &info, nil, &layout)
        }
        guard layoutResult == VK_SUCCESS, let pipelineLayout = layout else { return false }
        self.pipelineLayout = pipelineLayout

        let entry = strdup("main")
        defer { free(entry) }

        var vertStage = VkPipelineShaderStageCreateInfo()
        vertStage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
        vertStage.stage = VK_SHADER_STAGE_VERTEX_BIT
        vertStage.module = vertModule
        vertStage.pName = UnsafePointer(entry)

        var fragStage = VkPipelineShaderStageCreateInfo()
        fragStage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
        fragStage.stage = VK_SHADER_STAGE_FRAGMENT_BIT
        fragStage.module = fragModule
        fragStage.pName = UnsafePointer(entry)

        let stages = [vertStage, fragStage]

        // Vertex input: position(0)@0, normal(1)@12, color(2)@24, stride 40
        var binding = VkVertexInputBindingDescription(
            binding: 0, stride: UInt32(MemoryLayout<LDrawVulkanVertex>.stride), inputRate: VK_VERTEX_INPUT_RATE_VERTEX
        )
        let attributes = [
            VkVertexInputAttributeDescription(location: 0, binding: 0, format: VK_FORMAT_R32G32B32_SFLOAT, offset: 0),
            VkVertexInputAttributeDescription(location: 1, binding: 0, format: VK_FORMAT_R32G32B32_SFLOAT, offset: 12),
            VkVertexInputAttributeDescription(location: 2, binding: 0, format: VK_FORMAT_R32G32B32A32_SFLOAT, offset: 24),
        ]

        var inputAssembly = VkPipelineInputAssemblyStateCreateInfo()
        inputAssembly.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
        inputAssembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST

        var viewportState = VkPipelineViewportStateCreateInfo()
        viewportState.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO
        viewportState.viewportCount = 1
        viewportState.scissorCount = 1

        var rasterizer = VkPipelineRasterizationStateCreateInfo()
        rasterizer.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO
        rasterizer.polygonMode = VK_POLYGON_MODE_FILL
        rasterizer.cullMode = UInt32(VK_CULL_MODE_NONE.rawValue) // double-sided (vertices duplicated with flipped winding)
        rasterizer.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE
        rasterizer.lineWidth = 1.0

        var multisample = VkPipelineMultisampleStateCreateInfo()
        multisample.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
        multisample.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT

        var depthStencil = VkPipelineDepthStencilStateCreateInfo()
        depthStencil.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
        depthStencil.depthTestEnable = VkBool32(VK_TRUE)
        depthStencil.depthWriteEnable = VkBool32(VK_TRUE)
        depthStencil.depthCompareOp = VK_COMPARE_OP_LESS

        var colorBlendAttachment = VkPipelineColorBlendAttachmentState()
        colorBlendAttachment.blendEnable = VkBool32(VK_TRUE)
        colorBlendAttachment.srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA
        colorBlendAttachment.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
        colorBlendAttachment.colorBlendOp = VK_BLEND_OP_ADD
        colorBlendAttachment.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE
        colorBlendAttachment.dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
        colorBlendAttachment.alphaBlendOp = VK_BLEND_OP_ADD
        colorBlendAttachment.colorWriteMask = 0xF

        let dynamicStates: [VkDynamicState] = [VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR]

        var result: VkResult = VK_ERROR_UNKNOWN
        var createdPipeline: VkPipeline? = nil

        stages.withUnsafeBufferPointer { stagesPtr in
            attributes.withUnsafeBufferPointer { attrPtr in
                withUnsafePointer(to: &binding) { bindingPtr in
                    var vertexInput = VkPipelineVertexInputStateCreateInfo()
                    vertexInput.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
                    vertexInput.vertexBindingDescriptionCount = 1
                    vertexInput.pVertexBindingDescriptions = bindingPtr
                    vertexInput.vertexAttributeDescriptionCount = UInt32(attributes.count)
                    vertexInput.pVertexAttributeDescriptions = attrPtr.baseAddress

                    withUnsafePointer(to: &colorBlendAttachment) { blendAttachPtr in
                        var colorBlend = VkPipelineColorBlendStateCreateInfo()
                        colorBlend.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
                        colorBlend.attachmentCount = 1
                        colorBlend.pAttachments = blendAttachPtr

                        dynamicStates.withUnsafeBufferPointer { dynPtr in
                            var dynamicState = VkPipelineDynamicStateCreateInfo()
                            dynamicState.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO
                            dynamicState.dynamicStateCount = UInt32(dynamicStates.count)
                            dynamicState.pDynamicStates = dynPtr.baseAddress

                            withUnsafePointer(to: &inputAssembly) { iaPtr in
                            withUnsafePointer(to: &viewportState) { vpPtr in
                            withUnsafePointer(to: &rasterizer) { rastPtr in
                            withUnsafePointer(to: &multisample) { msPtr in
                            withUnsafePointer(to: &depthStencil) { dsPtr in
                            withUnsafePointer(to: &vertexInput) { viPtr in
                            withUnsafePointer(to: &colorBlend) { cbPtr in
                            withUnsafePointer(to: &dynamicState) { dynStatePtr in
                                var pipelineInfo = VkGraphicsPipelineCreateInfo()
                                pipelineInfo.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO
                                pipelineInfo.stageCount = UInt32(stages.count)
                                pipelineInfo.pStages = stagesPtr.baseAddress
                                pipelineInfo.pVertexInputState = viPtr
                                pipelineInfo.pInputAssemblyState = iaPtr
                                pipelineInfo.pViewportState = vpPtr
                                pipelineInfo.pRasterizationState = rastPtr
                                pipelineInfo.pMultisampleState = msPtr
                                pipelineInfo.pDepthStencilState = dsPtr
                                pipelineInfo.pColorBlendState = cbPtr
                                pipelineInfo.pDynamicState = dynStatePtr
                                pipelineInfo.layout = pipelineLayout
                                pipelineInfo.renderPass = renderPass
                                pipelineInfo.subpass = 0
                                result = vkCreateGraphicsPipelines(device, nil, 1, &pipelineInfo, nil, &createdPipeline)
                            }}}}}}}}
                        }
                    }
                }
            }
        }

        guard result == VK_SUCCESS, let pipeline = createdPipeline else { return false }
        self.pipeline = pipeline
        return true
    }

    private func loadShaderModule(named name: String) -> VkShaderModule? {
        let url: URL
        if let shaderDirectory {
            url = shaderDirectory.appendingPathComponent(name)
        } else if let bundled = Bundle.module.url(forResource: name, withExtension: nil) {
            url = bundled
        } else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }

        var module: VkShaderModule? = nil
        let result: VkResult = data.withUnsafeBytes { raw in
            var info = VkShaderModuleCreateInfo()
            info.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO
            info.codeSize = data.count
            info.pCode = raw.bindMemory(to: UInt32.self).baseAddress
            return vkCreateShaderModule(device, &info, nil, &module)
        }
        guard result == VK_SUCCESS else { return nil }
        return module
    }

    // MARK: - Buffers

    private func createBuffer(size: Int, usage: VkBufferUsageFlags, properties: VkMemoryPropertyFlags) -> (VkBuffer?, VkDeviceMemory?) {
        var info = VkBufferCreateInfo()
        info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO
        info.size = VkDeviceSize(size)
        info.usage = usage
        info.sharingMode = VK_SHARING_MODE_EXCLUSIVE

        var buffer: VkBuffer? = nil
        guard vkCreateBuffer(device, &info, nil, &buffer) == VK_SUCCESS, let buffer else { return (nil, nil) }

        var req = VkMemoryRequirements()
        vkGetBufferMemoryRequirements(device, buffer, &req)
        guard let typeIndex = context.findMemoryType(typeBits: req.memoryTypeBits, properties: properties) else {
            return (nil, nil)
        }

        var allocInfo = VkMemoryAllocateInfo()
        allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
        allocInfo.allocationSize = req.size
        allocInfo.memoryTypeIndex = typeIndex
        var memory: VkDeviceMemory? = nil
        guard vkAllocateMemory(device, &allocInfo, nil, &memory) == VK_SUCCESS, let memory else { return (nil, nil) }
        vkBindBufferMemory(device, buffer, memory, 0)
        return (buffer, memory)
    }

    private func createReadbackBuffer() -> Bool {
        let size = width * height * 4
        let (buf, mem) = createBuffer(
            size: size,
            usage: UInt32(VK_BUFFER_USAGE_TRANSFER_DST_BIT.rawValue),
            properties: UInt32(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.rawValue)
        )
        guard let buf, let mem else { return false }
        readbackBuffer = buf
        readbackBufferMemory = mem
        return true
    }

    private func transitionAndCopyToReadback(commandBuffer: VkCommandBuffer) {
        var barrier = VkImageMemoryBarrier()
        barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER
        barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL // matches renderPass finalLayout
        barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL
        // VK_QUEUE_FAMILY_IGNORED imports with a differently-signed type on some platforms
        // (e.g. Int32 vs UInt32); truncatingIfNeeded reinterprets the bits regardless.
        barrier.srcQueueFamilyIndex = UInt32(truncatingIfNeeded: VK_QUEUE_FAMILY_IGNORED)
        barrier.dstQueueFamilyIndex = UInt32(truncatingIfNeeded: VK_QUEUE_FAMILY_IGNORED)
        barrier.image = colorImage
        barrier.subresourceRange = VkImageSubresourceRange(
            aspectMask: UInt32(VK_IMAGE_ASPECT_COLOR_BIT.rawValue), baseMipLevel: 0, levelCount: 1, baseArrayLayer: 0, layerCount: 1
        )

        var region = VkBufferImageCopy()
        region.bufferOffset = 0
        region.imageSubresource = VkImageSubresourceLayers(
            aspectMask: UInt32(VK_IMAGE_ASPECT_COLOR_BIT.rawValue), mipLevel: 0, baseArrayLayer: 0, layerCount: 1
        )
        region.imageExtent = VkExtent3D(width: UInt32(width), height: UInt32(height), depth: 1)

        vkCmdCopyImageToBuffer(commandBuffer, colorImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readbackBuffer, 1, &region)
    }

    private func readPixels() -> [UInt8] {
        let size = width * height * 4
        var mapped: UnsafeMutableRawPointer? = nil
        vkMapMemory(device, readbackBufferMemory, 0, VkDeviceSize(size), 0, &mapped)
        defer { vkUnmapMemory(device, readbackBufferMemory) }
        guard let mapped else { return [] }
        return [UInt8](UnsafeRawBufferPointer(start: mapped, count: size))
    }

    // MARK: - Command buffer + fence

    private func createCommandBufferAndFence() -> Bool {
        var allocInfo = VkCommandBufferAllocateInfo()
        allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
        allocInfo.commandPool = context.commandPool
        allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY
        allocInfo.commandBufferCount = 1
        var cmdBuf: VkCommandBuffer? = nil
        guard vkAllocateCommandBuffers(device, &allocInfo, &cmdBuf) == VK_SUCCESS, let cmdBuf else { return false }
        commandBuffer = cmdBuf

        var fenceInfo = VkFenceCreateInfo()
        fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO
        var f: VkFence? = nil
        guard vkCreateFence(device, &fenceInfo, nil, &f) == VK_SUCCESS, let f else { return false }
        fence = f
        return true
    }
}

/// Writes to fd 2 directly rather than through the global `stderr` `FILE*`, which isn't
/// `Sendable`-safe under Swift 6 strict concurrency.
func logToStderr(_ message: String) {
    let bytes = Array(message.utf8)
    bytes.withUnsafeBufferPointer { buf in
        _ = write(2, buf.baseAddress, buf.count)
    }
}
#endif
