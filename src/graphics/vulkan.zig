const std = @import("std");
const builtin = @import("builtin");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const c = @import("c");

comptime {
	std.debug.assert(@as(u1, 1) == c.VK_TRUE and @as(u1, 0) == c.VK_FALSE); // Allows using @intFromBool to convert to vulkan types
}

const VkResultEnum = enum(c_int) { // MARK: VkResultEnum
	VK_SUCCESS = 0,
	VK_NOT_READY = 1,
	VK_TIMEOUT = 2,
	VK_EVENT_SET = 3,
	VK_EVENT_RESET = 4,
	VK_INCOMPLETE = 5,
	VK_ERROR_OUT_OF_HOST_MEMORY = -1,
	VK_ERROR_OUT_OF_DEVICE_MEMORY = -2,
	VK_ERROR_INITIALIZATION_FAILED = -3,
	VK_ERROR_DEVICE_LOST = -4,
	VK_ERROR_MEMORY_MAP_FAILED = -5,
	VK_ERROR_LAYER_NOT_PRESENT = -6,
	VK_ERROR_EXTENSION_NOT_PRESENT = -7,
	VK_ERROR_FEATURE_NOT_PRESENT = -8,
	VK_ERROR_INCOMPATIBLE_DRIVER = -9,
	VK_ERROR_TOO_MANY_OBJECTS = -10,
	VK_ERROR_FORMAT_NOT_SUPPORTED = -11,
	VK_ERROR_FRAGMENTED_POOL = -12,
	VK_ERROR_UNKNOWN = -13,
	VK_ERROR_OUT_OF_POOL_MEMORY = -1000069000,
	VK_ERROR_INVALID_EXTERNAL_HANDLE = -1000072003,
	VK_ERROR_FRAGMENTATION = -1000161000,
	VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS = -1000257000,
	VK_PIPELINE_COMPILE_REQUIRED = 1000297000,
	VK_ERROR_NOT_PERMITTED = -1000174001,
	VK_ERROR_SURFACE_LOST_KHR = -1000000000,
	VK_ERROR_NATIVE_WINDOW_IN_USE_KHR = -1000000001,
	VK_SUBOPTIMAL_KHR = 1000001003,
	VK_ERROR_OUT_OF_DATE_KHR = -1000001004,
	VK_ERROR_INCOMPATIBLE_DISPLAY_KHR = -1000003001,
	VK_ERROR_VALIDATION_FAILED_EXT = -1000011001,
	VK_ERROR_INVALID_SHADER_NV = -1000012000,
	VK_ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR = -1000023000,
	VK_ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR = -1000023001,
	VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR = -1000023002,
	VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR = -1000023003,
	VK_ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR = -1000023004,
	VK_ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR = -1000023005,
	VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT = -1000158000,
	VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT = -1000255000,
	VK_THREAD_IDLE_KHR = 1000268000,
	VK_THREAD_DONE_KHR = 1000268001,
	VK_OPERATION_DEFERRED_KHR = 1000268002,
	VK_OPERATION_NOT_DEFERRED_KHR = 1000268003,
	VK_ERROR_INVALID_VIDEO_STD_PARAMETERS_KHR = -1000299000,
	VK_ERROR_COMPRESSION_EXHAUSTED_EXT = -1000338000,
	VK_PIPELINE_BINARY_MISSING_KHR = 1000483000,
	VK_ERROR_NOT_ENOUGH_SPACE_KHR = -1000483000,
	VK_ERROR_INCOMPATIBLE_SHADER_BINARY_EXT = 1000482000,
	VK_RESULT_MAX_ENUM = 2147483647,
};

pub fn checkResult(result: c.VkResult) void {
	const resultEnum = std.enums.fromInt(VkResultEnum, result) orelse {
		std.log.err("Encountered a vulkan error with unknown error code {}", .{result});
		return;
	};
	if (resultEnum == .VK_SUCCESS) return;
	std.log.err("Encountered a vulkan error: {s}", .{@tagName(resultEnum)});
}

pub fn checkResultErr(result: c.VkResult) !void {
	const resultEnum = std.enums.fromInt(VkResultEnum, result) orelse {
		std.log.err("Encountered a vulkan error with unknown error code {}", .{result});
		return error.VulkanError;
	};
	if (resultEnum == .VK_SUCCESS) return;
	std.log.err("Encountered a vulkan error: {s}", .{@tagName(resultEnum)});
	return error.VulkanError;
}

fn checkResultIfAvailable(result: anytype) void {
	if (@TypeOf(result) != void) {
		checkResult(result);
	}
}

fn allocEnumerationGeneric(function: anytype, allocator: NeverFailingAllocator, args: anytype) []@typeInfo(@typeInfo(@TypeOf(function)).@"fn".params[@typeInfo(@TypeOf(function)).@"fn".params.len - 1].type.?).pointer.child {
	const T = @typeInfo(@typeInfo(@TypeOf(function)).@"fn".params[@typeInfo(@TypeOf(function)).@"fn".params.len - 1].type.?).pointer.child;
	var count: u32 = 0;
	while (true) {
		checkResultIfAvailable(@call(.auto, function, args ++ .{&count, null}));
		const list = allocator.alloc(T, count);
		const result = @call(.auto, function, args ++ .{&count, list.ptr});
		if (@TypeOf(result) != void and result == c.VK_INCOMPLETE) {
			allocator.free(list);
			continue;
		}
		checkResultIfAvailable(result);

		if (count < list.len) return allocator.realloc(list, count);
		return list;
	}
}

// MARK: Enumerators

pub fn enumerateInstanceLayerProperties(allocator: NeverFailingAllocator) []c.VkLayerProperties {
	return allocEnumerationGeneric(c.vkEnumerateInstanceLayerProperties, allocator, .{});
}

pub fn enumerateInstanceExtensionProperties(allocator: NeverFailingAllocator, layerName: ?[*:0]const u8) []c.VkExtensionProperties {
	return allocEnumerationGeneric(c.vkEnumerateInstanceExtensionProperties, allocator, .{layerName});
}

pub fn enumeratePhysicalDevices(allocator: NeverFailingAllocator) []c.VkPhysicalDevice {
	return allocEnumerationGeneric(c.vkEnumeratePhysicalDevices, allocator, .{instance});
}

pub fn enumerateDeviceExtensionProperties(allocator: NeverFailingAllocator, dev: c.VkPhysicalDevice, layerName: ?[*:0]const u8) []c.VkExtensionProperties {
	return allocEnumerationGeneric(c.vkEnumerateDeviceExtensionProperties, allocator, .{dev, layerName});
}

pub fn getPhysicalDeviceQueueFamilyProperties(allocator: NeverFailingAllocator, dev: c.VkPhysicalDevice) []c.VkQueueFamilyProperties {
	return allocEnumerationGeneric(c.vkGetPhysicalDeviceQueueFamilyProperties, allocator, .{dev});
}

pub fn getPhysicalDeviceSurfaceFormatsKHR(allocator: NeverFailingAllocator, dev: c.VkPhysicalDevice) []c.VkSurfaceFormatKHR {
	return allocEnumerationGeneric(c.vkGetPhysicalDeviceSurfaceFormatsKHR, allocator, .{dev, surface});
}

pub fn getPhysicalDeviceSurfacePresentModesKHR(allocator: NeverFailingAllocator, dev: c.VkPhysicalDevice) []c.VkPresentModeKHR {
	return allocEnumerationGeneric(c.vkGetPhysicalDeviceSurfacePresentModesKHR, allocator, .{dev, surface});
}

// MARK: globals

var instance: c.VkInstance = undefined;
var surface: c.VkSurfaceKHR = undefined;
var physicalDevice: c.VkPhysicalDevice = undefined;
pub var device: c.VkDevice = undefined;
var graphicsQueue: c.VkQueue = undefined;
var presentQueue: c.VkQueue = undefined;

pub var version: packed struct(u32) {
	patch: u12,
	minor: u10,
	major: u7,
	variant: u3,
} = @bitCast(@as(u32, 0));

pub var interestingExtensions: struct {
	VK_KHR_buffer_device_address: bool = false, // #2960
	VK_EXT_fragment_shader_interlock: bool = false, // #817
	VK_EXT_descriptor_buffer: bool = false, // for bindless
	VK_EXT_descriptor_heap: bool = false, // for bindless
	VK_EXT_descriptor_indexing: bool = false, // for bindless
	VK_EXT_mutable_descriptor_type: bool = false, // also for bindless
} = .{};

// MARK: init

pub fn init(window: ?*c.GLFWwindow) !void {
	// NOTE(blackedout): glad is currently not used on macOS
	if (builtin.target.os.tag != .macos) {
		if (c.gladLoaderLoadVulkan(null, null, null) == 0) {
			@panic("GLAD failed to load Vulkan functions");
		}
	}
	createInstance();
	checkResult(c.glfwCreateWindowSurface(instance, window, null, &surface));
	try pickPhysicalDevice();
	if (builtin.target.os.tag != .macos) {
		if (c.gladLoaderLoadVulkan(instance, physicalDevice, null) == 0) {
			@panic("GLAD failed to load Vulkan functions");
		}
	}
	createLogicalDevice();
	if (builtin.target.os.tag != .macos) {
		if (c.gladLoaderLoadVulkan(instance, physicalDevice, device) == 0) {
			@panic("GLAD failed to load Vulkan functions");
		}
	}
	command_pool.init();
	SwapChain.init();
	gpu_allocator.init();
}

pub fn deinit() void {
	gpu_garbage_collection.deinit();
	gpu_allocator.deinit();
	SwapChain.deinit();
	command_pool.deinit();
	c.vkDestroyDevice(device, null);
	c.vkDestroySurfaceKHR(instance, surface, null);
	c.vkDestroyInstance(instance, null);
}

// MARK: Instance

const validationLayers: []const [*:0]const u8 = &.{
	"VK_LAYER_KHRONOS_validation",
};

fn checkValidationLayerSupport() bool {
	const availableLayers = enumerateInstanceLayerProperties(main.stackAllocator);
	defer main.stackAllocator.free(availableLayers);
	for (validationLayers) |layerName| continueOuter: {
		for (availableLayers) |layerProperties| {
			if (std.mem.eql(u8, std.mem.span(layerName), std.mem.span(@as([*:0]const u8, @ptrCast(&layerProperties.layerName))))) {
				break :continueOuter;
			}
		}
		std.log.warn("Couldn't find validation layer {s}", .{layerName});
		return false;
	}
	return true;
}

pub fn createInstance() void {
	const appInfo = c.VkApplicationInfo{
		.sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
		.pApplicationName = "Cubyz",
		.applicationVersion = c.VK_MAKE_VERSION(0, 0, 0),
		.pEngineName = "Cubyz",
		.engineVersion = c.VK_MAKE_VERSION(0, 0, 0),
		.apiVersion = c.VK_API_VERSION_1_3,
	};
	var glfwExtensionCount: u32 = 0;
	const glfwExtensions: [*c][*c]const u8 = c.glfwGetRequiredInstanceExtensions(&glfwExtensionCount);
	if (glfwExtensions == null) {
		@panic("glfwGetRequiredInstanceExtensions returned a null pointer. This may be a problem with your Vulkan driver.");
	}

	const availableExtensions = enumerateInstanceExtensionProperties(main.stackAllocator, null);
	defer main.stackAllocator.free(availableExtensions);
	std.log.debug("Availabe vulkan instance extensions:", .{});
	for (availableExtensions) |ext| {
		std.log.debug("\t{s}", .{@as([*:0]const u8, @ptrCast(&ext.extensionName))});
	}

	var createFlags: u32 = 0;
	var extensions: main.ListManaged([*c]const u8) = .init(main.stackAllocator);
	defer extensions.deinit();
	extensions.appendSlice(glfwExtensions[0..glfwExtensionCount]);

	if (builtin.target.os.tag == .macos) {
		// NOTE(blackedout): These constants may not be available for other targets because currently only macOS uses higher version headers
		extensions.appendSlice(&.{
			c.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME,
			c.VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME,
		});
		createFlags |= c.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
	}

	const createInfo = c.VkInstanceCreateInfo{
		.sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
		.flags = createFlags,
		.pApplicationInfo = &appInfo,
		.enabledExtensionCount = @intCast(extensions.items.len),
		.ppEnabledExtensionNames = extensions.items.ptr,
		.ppEnabledLayerNames = validationLayers.ptr,
		.enabledLayerCount = if (checkValidationLayerSupport()) validationLayers.len else 0,
	};
	checkResult(c.vkCreateInstance(&createInfo, null, &instance));
}

// MARK: Physical Device

const deviceExtensions = blk: {
	const baseDeviceExtensions = [_][*:0]const u8{
		c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
		c.VK_KHR_PUSH_DESCRIPTOR_EXTENSION_NAME,
	};
	if (builtin.target.os.tag == .macos) {
		break :blk baseDeviceExtensions ++ [_][*:0]const u8{c.VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME};
	}
	break :blk baseDeviceExtensions;
};

const DeviceFeatures = struct {
	v10: c.VkPhysicalDeviceFeatures,
	v11: c.VkPhysicalDeviceVulkan11Features,
	v12: c.VkPhysicalDeviceVulkan12Features,
	v13: c.VkPhysicalDeviceVulkan13Features,

	fn getFromDevice(dev: c.VkPhysicalDevice) DeviceFeatures {
		var self: DeviceFeatures = undefined;
		var features: c.VkPhysicalDeviceFeatures2 = .{
			.sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
			.pNext = self.chain(),
		};
		c.vkGetPhysicalDeviceFeatures2(dev, &features);
		self.v10 = features.features;
		return self;
	}

	fn chain(self: *DeviceFeatures) *anyopaque {
		self.v11.sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES;
		self.v11.pNext = &self.v12;
		self.v12.sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
		self.v12.pNext = &self.v13;
		self.v13.sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES;
		self.v13.pNext = null;
		return &self.v11;
	}
};

const deviceFeatures: DeviceFeatures = .{
	.v10 = .{
		// needed for indirect chunk rendering
		.multiDrawIndirect = c.VK_TRUE,
		.vertexPipelineStoresAndAtomics = c.VK_TRUE,
		.fragmentStoresAndAtomics = c.VK_TRUE,
		// needed for colored glass
		.dualSrcBlend = c.VK_TRUE,
		// needed to prevent near-plane clipping
		.depthClamp = c.VK_TRUE,
	},
	.v11 = .{},
	.v12 = .{},
	.v13 = .{
		// together they replace render passes, device support is basically at 100%
		.synchronization2 = c.VK_TRUE,
		.dynamicRendering = c.VK_TRUE,
	},
};

const QueueFamilyIndidices = struct {
	graphicsFamily: ?u32 = null,
	presentFamily: ?u32 = null,

	fn isComplete(self: QueueFamilyIndidices) bool {
		return self.graphicsFamily != null and self.presentFamily != null;
	}
};

fn findQueueFamilies(dev: c.VkPhysicalDevice) QueueFamilyIndidices {
	var result: QueueFamilyIndidices = .{};
	const queueFamilies = getPhysicalDeviceQueueFamilyProperties(main.stackAllocator, dev);
	defer main.stackAllocator.free(queueFamilies);
	for (queueFamilies, 0..) |family, i| {
		if (family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0 and family.queueFlags & c.VK_QUEUE_COMPUTE_BIT != 0) {
			result.graphicsFamily = @intCast(i);
		}
		var presentSupport: u32 = 0;
		checkResult(c.vkGetPhysicalDeviceSurfaceSupportKHR(dev, @intCast(i), surface, &presentSupport));
		if (presentSupport != 0) {
			result.presentFamily = @intCast(i);
		}
	}
	return result;
}

fn checkDeviceExtensionSupport(dev: c.VkPhysicalDevice) bool {
	const availableExtension = enumerateDeviceExtensionProperties(main.stackAllocator, dev, null);
	defer main.stackAllocator.free(availableExtension);
	for (deviceExtensions) |requiredName| continueOuter: {
		for (availableExtension) |available| {
			if (std.mem.eql(u8, std.mem.span(requiredName), std.mem.span(@as([*:0]const u8, @ptrCast(&available.extensionName))))) {
				break :continueOuter;
			}
		}
		std.log.warn("Rejecting device because extension {s} was not found", .{requiredName});
		return false;
	}
	return true;
}

fn getDeviceScore(dev: c.VkPhysicalDevice) f32 {
	var properties: c.VkPhysicalDeviceProperties = undefined;
	c.vkGetPhysicalDeviceProperties(dev, &properties);
	const features: DeviceFeatures = .getFromDevice(dev);
	std.log.debug("Device: {s}", .{@as([*:0]const u8, @ptrCast(&properties.deviceName))});
	std.log.debug("Properties: {}", .{properties});
	std.log.debug("Features: {}", .{features});

	const baseScore: f32 = switch (properties.deviceType) {
		c.VK_PHYSICAL_DEVICE_TYPE_CPU => 1e-9,
		c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => 1e9,
		c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => 1,
		else => 0.1,
	};

	const availableExtension = enumerateDeviceExtensionProperties(main.stackAllocator, dev, null);
	defer main.stackAllocator.free(availableExtension);
	std.log.debug("Device extensions:", .{});
	for (availableExtension) |ext| {
		std.log.debug("\t{s}", .{@as([*:0]const u8, @ptrCast(&ext.extensionName))});
	}
	if (!findQueueFamilies(dev).isComplete() or !checkDeviceExtensionSupport(dev)) return 0;

	inline for (comptime std.meta.fieldNames(@TypeOf(deviceFeatures))) |ver| {
		inline for (comptime std.meta.fieldNames(@TypeOf(@field(deviceFeatures, ver)))) |name| {
			if (comptime std.mem.eql(u8, name, "sType")) continue;
			if (comptime std.mem.eql(u8, name, "pNext")) continue;
			if (@field(@field(deviceFeatures, ver), name) == c.VK_TRUE and @field(@field(features, ver), name) == c.VK_FALSE) {
				std.log.warn("Rejecting device: {s} is not supported", .{name});
				return 0;
			}
		}
	}

	return baseScore;
}

fn pickPhysicalDevice() !void {
	const devices = enumeratePhysicalDevices(main.stackAllocator);
	defer main.stackAllocator.free(devices);
	if (devices.len == 0) {
		return error.NoDevicesFound;
	}
	var bestScore: f32 = 0;
	for (devices) |dev| {
		const score = getDeviceScore(dev);
		if (score > bestScore) {
			bestScore = score;
			physicalDevice = dev;
		}
	}

	if (bestScore == 0) {
		return error.NoCapableDeviceFound;
	}

	var properties: c.VkPhysicalDeviceProperties = undefined;
	c.vkGetPhysicalDeviceProperties(physicalDevice, &properties);
	version = @bitCast(properties.apiVersion);

	const availableExtension = enumerateDeviceExtensionProperties(main.stackAllocator, physicalDevice, null);
	defer main.stackAllocator.free(availableExtension);
	for (availableExtension) |ext| {
		inline for (comptime std.meta.fieldNames(@TypeOf(interestingExtensions))) |extensionName| {
			if (std.mem.eql(u8, ext.extensionName[0..extensionName.len], extensionName)) {
				@field(interestingExtensions, extensionName) = true;
			}
		}
	}

	std.log.info("Selected device {s}", .{@as([*:0]const u8, @ptrCast(&properties.deviceName))});
}

// MARK: Logical Device

fn createLogicalDevice() void {
	const indices = findQueueFamilies(physicalDevice);
	var uniqueFamilies: std.AutoHashMapUnmanaged(u32, void) = .{};
	defer uniqueFamilies.deinit(main.stackAllocator.allocator);
	_ = uniqueFamilies.getOrPut(main.stackAllocator.allocator, indices.graphicsFamily.?) catch unreachable;
	_ = uniqueFamilies.getOrPut(main.stackAllocator.allocator, indices.presentFamily.?) catch unreachable;

	var queueCreateInfos: main.ListManaged(c.VkDeviceQueueCreateInfo) = .init(main.stackAllocator);
	defer queueCreateInfos.deinit();
	var iterator = uniqueFamilies.keyIterator();
	while (iterator.next()) |queueFamily| {
		queueCreateInfos.append(.{
			.sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
			.queueFamilyIndex = queueFamily.*,
			.queueCount = 1,
			.pQueuePriorities = &@as(f32, 1.0),
		});
	}

	var features = deviceFeatures;

	const createInfo: c.VkDeviceCreateInfo = .{
		.sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
		.pNext = features.chain(),
		.pQueueCreateInfos = queueCreateInfos.items.ptr,
		.queueCreateInfoCount = @intCast(queueCreateInfos.items.len),
		.pEnabledFeatures = &features.v10,
		.ppEnabledLayerNames = validationLayers.ptr,
		.enabledLayerCount = if (checkValidationLayerSupport()) validationLayers.len else 0,
		.ppEnabledExtensionNames = &deviceExtensions,
		.enabledExtensionCount = @intCast(deviceExtensions.len),
	};
	checkResult(c.vkCreateDevice(physicalDevice, &createInfo, null, &device));
	c.vkGetDeviceQueue(device, indices.graphicsFamily.?, 0, &graphicsQueue);
	c.vkGetDeviceQueue(device, indices.presentFamily.?, 0, &presentQueue);
}

pub const Semaphore = struct { // MARK: Semaphore
	handle: c.VkSemaphore,

	fn init() Semaphore {
		var result: c.VkSemaphore = undefined;
		const semaphoreInfo = c.VkSemaphoreCreateInfo{
			.sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
		};
		checkResult(c.vkCreateSemaphore(device, &semaphoreInfo, null, &result));
		return .{.handle = result};
	}
	fn deinit(self: Semaphore) void {
		c.vkDestroySemaphore(device, self.handle, null);
	}
};

pub const Fence = struct { // MARK: Fence
	handle: c.VkFence,

	fn init(createSignaled: bool) Fence {
		var result: c.VkFence = undefined;
		const fenceInfo = c.VkFenceCreateInfo{
			.sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
			.flags = if (createSignaled) c.VK_FENCE_CREATE_SIGNALED_BIT else 0,
		};
		checkResult(c.vkCreateFence(device, &fenceInfo, null, &result));
		return .{.handle = result};
	}
	fn deinit(self: Fence) void {
		c.vkDestroyFence(device, self.handle, null);
	}

	fn waitAndReset(self: Fence) void {
		checkResult(c.vkWaitForFences(device, 1, &self.handle, c.VK_TRUE, c.UINT64_MAX));
		checkResult(c.vkResetFences(device, 1, &self.handle));
	}
};

const FrameData = struct {
	fence: Fence,
	uploadFence: Fence,
	swapChainImageIndex: u32,

	imageAvailable: Semaphore,
	uploadFinished: Semaphore,
	renderFinished: Semaphore,

	uploadCommands: main.graphics.CommandBuffer,
	guiCommands: main.graphics.CommandBuffer,

	fn init() FrameData {
		return .{
			.fence = .init(true),
			.uploadFence = .init(true),
			.imageAvailable = .init(),
			.uploadFinished = .init(),
			.renderFinished = .init(),
			.swapChainImageIndex = undefined,
			.uploadCommands = .init(),
			.guiCommands = .init(),
		};
	}

	fn deinit(self: FrameData) void {
		self.fence.deinit();
		self.uploadFence.deinit();
		self.imageAvailable.deinit();
		self.uploadFinished.deinit();
		self.renderFinished.deinit();
		self.uploadCommands.deinit();
		self.guiCommands.deinit();
	}
};

var frames: [2]FrameData = undefined;

pub var currentFrame: *const FrameData = undefined;

pub const SwapChain = struct { // MARK: SwapChain
	var swapChain: c.VkSwapchainKHR = null;
	var images: []c.VkImage = undefined;
	var imageViews: []c.VkImageView = undefined;
	pub var imageFormat: c.VkFormat = undefined;
	pub var extent: c.VkExtent2D = undefined;

	const SupportDetails = struct {
		capabilities: c.VkSurfaceCapabilitiesKHR,
		formats: []const c.VkSurfaceFormatKHR,
		presentModes: []const c.VkPresentModeKHR,

		fn init(allocator: NeverFailingAllocator, physical: c.VkPhysicalDevice) SupportDetails {
			var result: SupportDetails = undefined;
			checkResult(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical, surface, &result.capabilities));
			result.formats = getPhysicalDeviceSurfaceFormatsKHR(allocator, physical);
			result.presentModes = getPhysicalDeviceSurfacePresentModesKHR(allocator, physical);
			return result;
		}

		fn deinit(self: SupportDetails, allocator: NeverFailingAllocator) void {
			allocator.free(self.formats);
			allocator.free(self.presentModes);
		}

		fn chooseFormat(self: SupportDetails) c.VkSurfaceFormatKHR {
			for (self.formats) |format| {
				if (format.format == c.VK_FORMAT_B8G8R8A8_SRGB and format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
					return format;
				}
			}
			@panic("Couldn't find swapchain format BGRA8 SRGB");
		}

		fn chooseSwapPresentMode(self: SupportDetails) c.VkPresentModeKHR {
			_ = self; // TODO: Use MAILBOX if vsync is disabled
			return c.VK_PRESENT_MODE_FIFO_KHR;
		}

		fn chooseSwapExtent(self: SupportDetails) c.VkExtent2D {
			if (self.capabilities.currentExtent.width != std.math.maxInt(u32)) {
				return self.capabilities.currentExtent;
			}
			var width: i32 = undefined;
			var height: i32 = undefined;
			c.glfwGetFramebufferSize(main.Window.vulkanWindow, &width, &height);
			return .{
				.width = @min(self.capabilities.maxImageExtent.width, @max(self.capabilities.minImageExtent.width, @max(0, width))),
				.height = @min(self.capabilities.maxImageExtent.height, @max(self.capabilities.minImageExtent.height, @max(0, height))),
			};
		}
	};

	fn createImageView(image: c.VkImage) c.VkImageView {
		const createInfo: c.VkImageViewCreateInfo = .{
			.sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
			.image = image,
			.viewType = c.VK_IMAGE_VIEW_TYPE_2D,
			.format = imageFormat,
			.components = .{
				.a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
				.r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
				.g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
				.b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
			},
			.subresourceRange = .{
				.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
				.baseMipLevel = 0,
				.levelCount = 1,
				.baseArrayLayer = 0,
				.layerCount = 1,
			},
		};
		var result: c.VkImageView = undefined;
		checkResult(c.vkCreateImageView(device, &createInfo, null, &result));
		return result;
	}

	fn init() void {
		const support = SupportDetails.init(main.stackAllocator, physicalDevice);
		defer support.deinit(main.stackAllocator);

		const surfaceFormat = support.chooseFormat();
		imageFormat = surfaceFormat.format;
		const presentMode = support.chooseSwapPresentMode();
		extent = support.chooseSwapExtent();
		const imageCount: u32 = @max(2, support.capabilities.minImageCount);

		var createInfo: c.VkSwapchainCreateInfoKHR = .{
			.sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
			.surface = surface,
			.minImageCount = imageCount,
			.imageFormat = surfaceFormat.format,
			.imageColorSpace = surfaceFormat.colorSpace,
			.imageExtent = extent,
			.imageArrayLayers = 1,
			.imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
			.preTransform = support.capabilities.currentTransform,
			.compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
			.presentMode = presentMode,
			.clipped = c.VK_TRUE,
			.oldSwapchain = null,
		};
		const queueFamilies = findQueueFamilies(physicalDevice);
		if (queueFamilies.graphicsFamily.? != queueFamilies.presentFamily.?) {
			const queueFamilyIndices = [_]u32{queueFamilies.graphicsFamily.?, queueFamilies.presentFamily.?};
			createInfo.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
			createInfo.queueFamilyIndexCount = @intCast(queueFamilyIndices.len);
			createInfo.pQueueFamilyIndices = &queueFamilyIndices;
		} else {
			createInfo.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
		}

		checkResult(c.vkCreateSwapchainKHR(device, &createInfo, null, &swapChain));
		var newImageCount = imageCount;
		checkResult(c.vkGetSwapchainImagesKHR(device, swapChain, &newImageCount, null));
		images = main.globalArena.alloc(c.VkImage, newImageCount);
		checkResult(c.vkGetSwapchainImagesKHR(device, swapChain, &newImageCount, images.ptr));

		imageViews = main.globalArena.alloc(c.VkImageView, newImageCount);
		for (0..images.len) |i| {
			imageViews[i] = createImageView(images[i]);
		}

		for (&frames) |*frame| {
			frame.* = .init();
		}
		currentFrame = &frames[frameIndex];
		currentFrame.uploadFence.waitAndReset();
		currentFrame.uploadCommands.beginRecording(0);
	}

	fn deinit() void {
		for (imageViews) |imageView| {
			c.vkDestroyImageView(device, imageView, null);
		}
		for (&frames) |frame| {
			frame.deinit();
		}
		c.vkDestroySwapchainKHR(device, swapChain, null);
	}

	fn beginRender() void {
		currentFrame.fence.waitAndReset();
		checkResult(c.vkAcquireNextImageKHR(device, swapChain, c.UINT64_MAX, currentFrame.imageAvailable.handle, null, &frames[frameIndex].swapChainImageIndex));

		currentFrame.guiCommands.beginRecording(0);
		currentFrame.guiCommands.pipelineBarrier(.{.imageMemoryBarriers = &.{
			.{
				.sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
				.srcStageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
				.srcAccessMask = 0,
				.dstStageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
				.dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
				.oldLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
				.newLayout = c.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
				.image = images[currentFrame.swapChainImageIndex],
				.subresourceRange = .{.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT, .levelCount = 1, .layerCount = 1},
			},
		}});
		currentFrame.guiCommands.beginRendering(.{
			.textures = &.{
				.{
					.imageView = imageViews[currentFrame.swapChainImageIndex],
					.layout = c.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
					.loadOp = .{.clearColor = .{.float32 = .{0.5, 1, 1, 1.0}}},
					.storeOp = .store,
				},
			},
			.renderArea = .{.extent = extent},
		});
	}

	fn endRender() void {
		currentFrame.uploadCommands.endRecording();
		currentFrame.uploadCommands.submit(
			graphicsQueue,
			&.{},
			&.{},
			&.{currentFrame.uploadFinished.handle},
			currentFrame.uploadFence.handle,
		);

		currentFrame.guiCommands.endRendering();
		currentFrame.guiCommands.pipelineBarrier(.{.imageMemoryBarriers = &.{
			.{
				.sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
				.srcStageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
				.srcAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
				.dstStageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
				.dstAccessMask = 0,
				.oldLayout = c.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
				.newLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
				.image = images[currentFrame.swapChainImageIndex],
				.subresourceRange = .{.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT, .levelCount = 1, .layerCount = 1},
			},
		}});
		currentFrame.guiCommands.endRecording();
		currentFrame.guiCommands.submit(
			graphicsQueue,
			&.{currentFrame.imageAvailable.handle, currentFrame.uploadFinished.handle},
			&.{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, c.VK_PIPELINE_STAGE_TRANSFER_BIT},
			&.{currentFrame.renderFinished.handle},
			currentFrame.fence.handle,
		);

		const presentInfo: c.VkPresentInfoKHR = .{
			.sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
			.waitSemaphoreCount = 1,
			.pWaitSemaphores = &currentFrame.renderFinished.handle,
			.swapchainCount = 1,
			.pSwapchains = &swapChain,
			.pImageIndices = &currentFrame.swapChainImageIndex,
		};
		const result = c.vkQueuePresentKHR(presentQueue, &presentInfo);
		frameIndex = (frameIndex + 1)%frames.len;
		currentFrame = &frames[frameIndex];
		currentFrame.uploadFence.waitAndReset();
		currentFrame.uploadCommands.beginRecording(0);
		checkResult(result); // TODO: swapchain recreation
	}
};

pub const command_pool = struct { // MARK: command_pool
	pub var handle: c.VkCommandPool = undefined;

	fn init() void {
		const queueFamilies = findQueueFamilies(physicalDevice);
		const poolInfo = c.VkCommandPoolCreateInfo{
			.sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
			.flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
			.queueFamilyIndex = queueFamilies.graphicsFamily.?,
		};
		checkResult(c.vkCreateCommandPool(device, &poolInfo, null, &handle));
	}

	fn deinit() void {
		c.vkDestroyCommandPool(device, handle, null);
	}
};

pub const Buffer = struct { // MARK: Buffer
	handle: c.VkBuffer,
	allocation: c.VmaAllocation,

	const BufferOptions = struct {
		usage: c.VkBufferUsageFlags,
		hostAccessible: bool = false,
	};
	pub fn init(size: usize, options: BufferOptions) Buffer {
		std.debug.assert(size != 0); // Vulkan cannot handle empty buffers
		var self: Buffer = undefined;
		const bufferInfo: c.VkBufferCreateInfo = .{
			.sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
			.size = size,
			.usage = options.usage,
		};
		const allocCreateInfo: c.VmaAllocationCreateInfo = .{
			.usage = c.VMA_MEMORY_USAGE_AUTO,
			.flags = if (options.hostAccessible) c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT else 0,
		};
		checkResult(c.vmaCreateBuffer(gpu_allocator.handle, &bufferInfo, &allocCreateInfo, &self.handle, &self.allocation, null));
		return self;
	}

	fn privateDeinit(self: Buffer) void {
		c.vmaDestroyBuffer(gpu_allocator.handle, self.handle, self.allocation);
	}

	pub fn deferredDeinit(self: Buffer) void {
		gpu_garbage_collection.deferredFree(.{.buf = self});
	}

	pub fn uploadData(self: Buffer, offset: usize, data: []const u8) void {
		if (data.len == 0) return;
		const stagingBuffer: Buffer = .init(data.len, .{.usage = c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, .hostAccessible = true});
		defer stagingBuffer.deferredDeinit();
		var gpuMemory: ?*anyopaque = undefined;
		checkResult(c.vmaMapMemory(gpu_allocator.handle, stagingBuffer.allocation, &gpuMemory));
		@memcpy(@as([*]u8, @ptrCast(gpuMemory.?)), data);
		c.vmaUnmapMemory(gpu_allocator.handle, stagingBuffer.allocation);
		currentFrame.uploadCommands.copyBuffer(self, offset, stagingBuffer, 0, data.len);
	}
};

pub const Image = struct { // MARK: Image
	handle: c.VkImage = undefined,
	allocation: c.VmaAllocation = undefined,
	mipLevels: u32,
	size: main.vec.Vec3i,

	const ImageOptions = struct {
		usage: c.VkImageUsageFlags,
		hostAccessible: bool = false,
		flags: c.VkImageCreateFlags = 0,
		imageType: c.VkImageType = c.VK_IMAGE_TYPE_2D,
		format: c.VkFormat = c.VK_FORMAT_R8G8B8A8_UNORM,
		mipLevels: u32 = 1,
		arrayLayers: u32 = 1,
		samples: c.VkSampleCountFlags = c.VK_SAMPLE_COUNT_1_BIT,
	};
	pub fn init(size: main.vec.Vec3i, options: ImageOptions) Image {
		var self: Image = .{
			.mipLevels = options.mipLevels,
			.size = size,
		};
		const imageInfo: c.VkImageCreateInfo = .{
			.sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
			.flags = options.flags,
			.imageType = options.imageType,
			.format = options.format,
			.extent = .{.width = @intCast(size[0]), .height = @intCast(size[1]), .depth = @intCast(size[2])},
			.mipLevels = options.mipLevels,
			.arrayLayers = options.arrayLayers,
			.samples = options.samples,
			.tiling = c.VK_IMAGE_TILING_OPTIMAL,
			.usage = options.usage,
			.sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
			.initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
		};
		const allocCreateInfo: c.VmaAllocationCreateInfo = .{
			.usage = c.VMA_MEMORY_USAGE_AUTO,
			.flags = if (options.hostAccessible) c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT else 0,
		};
		checkResult(c.vmaCreateImage(gpu_allocator.handle, &imageInfo, &allocCreateInfo, &self.handle, &self.allocation, null));
		return self;
	}

	fn privateDeinit(self: Image) void {
		c.vmaDestroyImage(gpu_allocator.handle, self.handle, self.allocation);
	}

	pub fn deferredDeinit(self: Image) void {
		gpu_garbage_collection.deferredFree(.{.image = self});
	}

	pub fn uploadData(self: Image, offset: usize, data: []const u8) void {
		if (data.len == 0) return;
		const stagingBuffer: Buffer = .init(data.len, .{.usage = c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, .hostAccessible = true});
		defer stagingBuffer.deferredDeinit();
		var gpuMemory: ?*anyopaque = undefined;
		checkResult(c.vmaMapMemory(gpu_allocator.handle, stagingBuffer.allocation, &gpuMemory));
		@memcpy(@as([*]u8, @ptrCast(gpuMemory.?)), data);
		c.vmaUnmapMemory(gpu_allocator.handle, stagingBuffer.allocation);
		currentFrame.uploadCommands.pipelineBarrier(.{.imageMemoryBarriers = &.{
			.{
				.sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
				.srcStageMask = c.VK_PIPELINE_STAGE_2_NONE,
				.srcAccessMask = c.VK_ACCESS_2_NONE,
				.dstStageMask = c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
				.dstAccessMask = c.VK_ACCESS_2_TRANSFER_WRITE_BIT,
				.oldLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
				.newLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
				.image = self.handle,
				.subresourceRange = .{.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT, .levelCount = self.mipLevels, .layerCount = 1},
			},
		}});
		currentFrame.uploadCommands.copyBufferToImage(self, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, stagingBuffer, &.{
			.{
				.sType = c.VK_STRUCTURE_TYPE_BUFFER_IMAGE_COPY_2,
				.bufferOffset = offset,
				.imageSubresource = .{
					.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
					.mipLevel = 0,
					.baseArrayLayer = 0,
					.layerCount = 1,
				},
				.imageOffset = .{.x = 0, .y = 0, .z = 0},
				.imageExtent = .{.width = @intCast(self.size[0]), .height = @intCast(self.size[1]), .depth = @intCast(self.size[2])},
			},
		});
		currentFrame.uploadCommands.pipelineBarrier(.{.imageMemoryBarriers = &.{
			.{
				.sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
				.srcStageMask = c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
				.srcAccessMask = c.VK_ACCESS_2_TRANSFER_WRITE_BIT,
				.dstStageMask = c.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
				.dstAccessMask = c.VK_ACCESS_SHADER_READ_BIT,
				.oldLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
				.newLayout = c.VK_IMAGE_LAYOUT_READ_ONLY_OPTIMAL,
				.image = self.handle,
				.subresourceRange = .{.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT, .levelCount = self.mipLevels, .layerCount = 1},
			},
		}});
	}
};

pub const gpu_allocator = struct {
	var handle: c.VmaAllocator = undefined;

	fn init() void {
		const vkFunctions: c.VmaVulkanFunctions = .{
			.glad_vkGetInstanceProcAddr = c.glad_vkGetInstanceProcAddr,
			.glad_vkGetDeviceProcAddr = c.glad_vkGetDeviceProcAddr,
			.glad_vkCreateImage = c.glad_vkCreateImage,
		};
		const allocatorCreateInfo: c.VmaAllocatorCreateInfo = .{
			.flags = 0,
			.physicalDevice = physicalDevice,
			.device = device,
			.pVulkanFunctions = &vkFunctions,
			.instance = instance,
		};
		checkResult(c.vmaCreateAllocator(&allocatorCreateInfo, &gpu_allocator.handle));
	}

	fn deinit() void {
		c.vmaDestroyAllocator(gpu_allocator.handle);
	}
};

pub const gpu_garbage_collection = struct {
	const Entry = union(enum) {
		buf: Buffer,
		image: Image,
	};
	var currentList: usize = 0;
	var lists: [frames.len + 1]main.List(Entry) = @splat(.empty);

	fn deinit() void {
		for (lists) |list| {
			for (list.items) |entry| {
				switch (entry) {
					inline else => |item| item.privateDeinit(),
				}
			}
			list.deinit(main.globalAllocator);
		}
	}

	fn cleanupFrame() void {
		currentList += 1;
		if (currentList == lists.len) currentList = 0;
		for (lists[currentList].items) |entry| {
			switch (entry) {
				inline else => |item| item.privateDeinit(),
			}
		}
		lists[currentList].clearRetainingCapacity();
	}

	pub fn deferredFree(entry: Entry) void {
		lists[currentList].append(main.globalAllocator, entry);
	}
};

var frameIndex: usize = 0;

pub fn beginRender() void {
	SwapChain.beginRender();
}

pub fn endRender() void {
	SwapChain.endRender();
	gpu_garbage_collection.cleanupFrame();
}
