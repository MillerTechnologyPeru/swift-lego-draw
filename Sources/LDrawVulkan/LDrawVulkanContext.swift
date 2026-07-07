#if os(Linux)
import Glibc
import CVulkan

/// Owns the top-level Vulkan objects shared by any renderer built on top of
/// it: instance, physical/logical device, a graphics-capable queue, and a
/// command pool. Headless — does not touch `VkSurfaceKHR`/swapchain, so it
/// has no windowing-system dependency.
public final class LDrawVulkanContext {
    public let instance: VkInstance
    public let physicalDevice: VkPhysicalDevice
    public let device: VkDevice
    public let graphicsQueue: VkQueue
    public let graphicsQueueFamilyIndex: UInt32
    public let commandPool: VkCommandPool

    public init?(applicationName: String = "LDrawVulkan", enableValidation: Bool = false) {
        // MARK: Instance
        var appInfo = VkApplicationInfo()
        appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO
        appInfo.pApplicationName = strdup(applicationName)
        appInfo.applicationVersion = 1
        appInfo.pEngineName = strdup("LDrawVulkan")
        appInfo.engineVersion = 1
        appInfo.apiVersion = UInt32(VK_API_VERSION_1_0)

        var instanceCreateInfo = VkInstanceCreateInfo()
        instanceCreateInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
        var appInfoLocal = appInfo
        var createdInstance: VkInstance? = nil
        let instanceResult = withUnsafePointer(to: &appInfoLocal) { appInfoPtr -> VkResult in
            instanceCreateInfo.pApplicationInfo = appInfoPtr
            return vkCreateInstance(&instanceCreateInfo, nil, &createdInstance)
        }
        free(UnsafeMutableRawPointer(mutating: appInfo.pApplicationName))
        free(UnsafeMutableRawPointer(mutating: appInfo.pEngineName))
        guard instanceResult == VK_SUCCESS, let instance = createdInstance else { return nil }
        self.instance = instance

        // MARK: Physical device — prefer a discrete GPU, else take the first one
        var deviceCount: UInt32 = 0
        vkEnumeratePhysicalDevices(instance, &deviceCount, nil)
        guard deviceCount > 0 else { return nil }
        var physicalDevices = [VkPhysicalDevice?](repeating: nil, count: Int(deviceCount))
        vkEnumeratePhysicalDevices(instance, &deviceCount, &physicalDevices)

        var chosen: VkPhysicalDevice? = physicalDevices.first ?? nil
        for candidate in physicalDevices {
            guard let candidate else { continue }
            var props = VkPhysicalDeviceProperties()
            vkGetPhysicalDeviceProperties(candidate, &props)
            if props.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU {
                chosen = candidate
                break
            }
        }
        guard let physicalDevice = chosen else { return nil }
        self.physicalDevice = physicalDevice

        // MARK: Graphics queue family
        var queueFamilyCount: UInt32 = 0
        vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, nil)
        var queueFamilies = [VkQueueFamilyProperties](repeating: VkQueueFamilyProperties(), count: Int(queueFamilyCount))
        vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, &queueFamilies)

        guard let familyIndex = queueFamilies.firstIndex(where: {
            $0.queueFlags & UInt32(VK_QUEUE_GRAPHICS_BIT.rawValue) != 0
        }) else { return nil }
        let queueFamilyIndex = UInt32(familyIndex)
        self.graphicsQueueFamilyIndex = queueFamilyIndex

        // MARK: Logical device + queue
        var queuePriority: Float = 1.0
        var createdDevice: VkDevice? = nil
        let deviceResult: VkResult = withUnsafePointer(to: &queuePriority) { priorityPtr -> VkResult in
            var queueCreateInfo = VkDeviceQueueCreateInfo()
            queueCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO
            queueCreateInfo.queueFamilyIndex = queueFamilyIndex
            queueCreateInfo.queueCount = 1
            queueCreateInfo.pQueuePriorities = priorityPtr

            return withUnsafePointer(to: &queueCreateInfo) { queueInfoPtr -> VkResult in
                var deviceCreateInfo = VkDeviceCreateInfo()
                deviceCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO
                deviceCreateInfo.queueCreateInfoCount = 1
                deviceCreateInfo.pQueueCreateInfos = queueInfoPtr
                return vkCreateDevice(physicalDevice, &deviceCreateInfo, nil, &createdDevice)
            }
        }
        guard deviceResult == VK_SUCCESS, let device = createdDevice else { return nil }
        self.device = device

        var queue: VkQueue? = nil
        vkGetDeviceQueue(device, queueFamilyIndex, 0, &queue)
        guard let graphicsQueue = queue else { return nil }
        self.graphicsQueue = graphicsQueue

        // MARK: Command pool
        var poolCreateInfo = VkCommandPoolCreateInfo()
        poolCreateInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO
        poolCreateInfo.flags = UInt32(VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT.rawValue)
        poolCreateInfo.queueFamilyIndex = queueFamilyIndex
        var createdPool: VkCommandPool? = nil
        guard vkCreateCommandPool(device, &poolCreateInfo, nil, &createdPool) == VK_SUCCESS,
              let commandPool = createdPool
        else { return nil }
        self.commandPool = commandPool
    }

    /// Finds a memory type index satisfying both the given type-bitmask
    /// (from `VkMemoryRequirements.memoryTypeBits`) and the required
    /// property flags (e.g. host-visible + host-coherent).
    public func findMemoryType(typeBits: UInt32, properties: VkMemoryPropertyFlags) -> UInt32? {
        var memProps = VkPhysicalDeviceMemoryProperties()
        vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memProps)
        let types = withUnsafeBytes(of: memProps.memoryTypes) { raw -> [VkMemoryType] in
            let buf = raw.bindMemory(to: VkMemoryType.self)
            return Array(buf.prefix(Int(memProps.memoryTypeCount)))
        }
        for (i, type) in types.enumerated() {
            let matchesType = (typeBits & (1 << UInt32(i))) != 0
            let matchesProps = (type.propertyFlags & properties) == properties
            if matchesType && matchesProps { return UInt32(i) }
        }
        return nil
    }

    deinit {
        vkDestroyCommandPool(device, commandPool, nil)
        vkDestroyDevice(device, nil)
        vkDestroyInstance(instance, nil)
    }
}
#endif
