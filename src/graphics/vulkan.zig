const std = @import("std");

const main = @import("main");
const c = main.Window.c;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

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
	const resultEnum = std.meta.intToEnum(VkResultEnum, result) catch {
		std.log.err("Encountered a vulkan error with unknown error code {}", .{result});
		return;
	};
	if(resultEnum == .VK_SUCCESS) return;
	std.log.err("Encountered a vulkan error: {s}", .{@tagName(resultEnum)});
}

fn checkResultIfAvailable(result: anytype) void {
	if(@TypeOf(result) != void) {
		checkResult(result);
	}
}

fn allocEnumerationGeneric(function: anytype, allocator: NeverFailingAllocator, args: anytype) []@typeInfo(@typeInfo(@TypeOf(function)).@"fn".params[@typeInfo(@TypeOf(function)).@"fn".params.len - 1].type.?).pointer.child {
	const T = @typeInfo(@typeInfo(@TypeOf(function)).@"fn".params[@typeInfo(@TypeOf(function)).@"fn".params.len - 1].type.?).pointer.child;
	var count: u32 = 0;
	while(true) {
		checkResultIfAvailable(@call(.auto, function, args ++ .{&count, null}));
		const list = allocator.alloc(T, count);
		const result = @call(.auto, function, args ++ .{&count, list.ptr});
		if(@TypeOf(result) != void and result == c.VK_INCOMPLETE) {
			allocator.free(list);
			continue;
		}
		checkResultIfAvailable(result);

		if(count < list.len) return allocator.realloc(list, count);
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

// MARK: globals

var instance: c.VkInstance = undefined;
var surface: c.VkSurfaceKHR = undefined;
var physicalDevice: c.VkPhysicalDevice = undefined;

// MARK: init

pub fn init(window: ?*c.GLFWwindow) !void {
	createInstance();
	checkResult(c.glfwCreateWindowSurface(instance, window, null, &surface));
	try pickPhysicalDevice();
}

pub fn deinit() void {
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
	for(validationLayers) |layerName| continueOuter: {
		for(availableLayers) |layerProperties| {
			if(std.mem.eql(u8, std.mem.span(layerName), std.mem.span(@as([*:0]const u8, @ptrCast(&layerProperties.layerName))))) {
				break :continueOuter;
			}
		}
		std.log.warn("Couldn't find validation layer {s}", .{layerName});
		return false;
	}
	return true;
}

pub fn createInstance() void {
	if(c.gladLoaderLoadVulkan(null, null, null) == 0) {
		@panic("GLAD failed to load Vulkan functions");
	}
	const appInfo = c.VkApplicationInfo{
		.sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
		.pApplicationName = "Cubyz",
		.applicationVersion = c.VK_MAKE_VERSION(0, 0, 0),
		.pEngineName = "Cubyz",
		.engineVersion = c.VK_MAKE_VERSION(0, 0, 0),
		.apiVersion = c.VK_API_VERSION_1_0,
	};
	var glfwExtensionCount: u32 = 0;
	const glfwExtensions: [*c][*c]const u8 = c.glfwGetRequiredInstanceExtensions(&glfwExtensionCount);

	const availableExtensions = enumerateInstanceExtensionProperties(main.stackAllocator, null);
	defer main.stackAllocator.free(availableExtensions);
	std.log.debug("Availabe vulkan instance extensions:", .{});
	for(availableExtensions) |ext| {
		std.log.debug("\t{s}", .{@as([*:0]const u8, @ptrCast(&ext.extensionName))});
	}

	const createInfo = c.VkInstanceCreateInfo{
		.sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
		.pApplicationInfo = &appInfo,
		.enabledExtensionCount = glfwExtensionCount,
		.ppEnabledExtensionNames = glfwExtensions,
		.ppEnabledLayerNames = validationLayers.ptr,
		.enabledLayerCount = if(checkValidationLayerSupport()) validationLayers.len else 0,
	};
	checkResult(c.vkCreateInstance(&createInfo, null, &instance));
}

// MARK: Physical Device

const deviceExtensions = [_][*:0]const u8{
	c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
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
	for(queueFamilies, 0..) |family, i| {
		if(family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
			result.graphicsFamily = @intCast(i);
		}
		var presentSupport: u32 = 0;
		checkResult(c.vkGetPhysicalDeviceSurfaceSupportKHR(dev, @intCast(i), surface, &presentSupport));
		if(presentSupport != 0) {
			result.presentFamily = @intCast(i);
		}
	}
	return result;
}

fn checkDeviceExtensionSupport(dev: c.VkPhysicalDevice) bool {
	const availableExtension = enumerateDeviceExtensionProperties(main.stackAllocator, dev, null);
	defer main.stackAllocator.free(availableExtension);
	for(deviceExtensions) |requiredName| continueOuter: {
		for(availableExtension) |available| {
			if(std.mem.eql(u8, std.mem.span(requiredName), std.mem.span(@as([*:0]const u8, @ptrCast(&available.extensionName))))) {
				break :continueOuter;
			}
		}
		std.log.warn("Rejecting device because extension {s} was not found", .{requiredName});
		return false;
	}
	return true;
}

fn deviceScore(dev: c.VkPhysicalDevice) f32 {
	var properties: c.VkPhysicalDeviceProperties = undefined;
	c.vkGetPhysicalDeviceProperties(dev, &properties);
	var features: c.VkPhysicalDeviceFeatures = undefined;
	c.vkGetPhysicalDeviceFeatures(dev, &features);
	std.log.debug("Device: {s}", .{@as([*:0]const u8, @ptrCast(&properties.deviceName))});
	std.log.debug("Properties: {}", .{properties});
	std.log.debug("Features: {}", .{features});

	const baseScore: f32 = switch(properties.deviceType) {
		c.VK_PHYSICAL_DEVICE_TYPE_CPU => 1e-9,
		c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => 1e9,
		c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => 1,
		else => 0.1,
	};

	const availableExtension = enumerateDeviceExtensionProperties(main.stackAllocator, dev, null);
	defer main.stackAllocator.free(availableExtension);
	std.log.debug("Device extensions:", .{});
	for(availableExtension) |ext| {
		std.log.debug("\t{s}", .{ext.extensionName});
	}
	if(!findQueueFamilies(dev).isComplete() or !checkDeviceExtensionSupport(dev)) return 0;

	if(features.multiDrawIndirect != c.VK_TRUE) {
		std.log.warn("Rejecting device: multDrawIndirect is not supported", .{});
		return 0;
	}

	if(features.dualSrcBlend != c.VK_TRUE) {
		std.log.warn("Rejecting device: dual source blending is not supported", .{});
		return 0;
	}

	return baseScore;
}

fn pickPhysicalDevice() !void {
	const devices = enumeratePhysicalDevices(main.stackAllocator);
	defer main.stackAllocator.free(devices);
	if(devices.len == 0) {
		return error.NoDevicesFound;
	}
	var bestScore: f32 = 0;
	for(devices) |dev| {
		const score = deviceScore(dev);
		if(score > bestScore) {
			bestScore = score;
			physicalDevice = dev;
		}
	}

	if(bestScore == 0) {
		return error.NoCapableDeviceFound;
	}

	var properties: c.VkPhysicalDeviceProperties = undefined;
	c.vkGetPhysicalDeviceProperties(physicalDevice, &properties);
	std.log.info("Selected device {s}", .{@as([*:0]const u8, @ptrCast(&properties.deviceName))});
}
