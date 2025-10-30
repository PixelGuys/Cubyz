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

pub fn getPhysicalDeviceSurfacePresentModesKHR(allocator: NeverFailingAllocator, dev: c.VkPhysicalDevice) []c.VkPresentModeKHR {
	return allocEnumerationGeneric(c.vkGetPhysicalDeviceSurfacePresentModesKHR, allocator, .{dev, surface});
}

// MARK: globals

var instance: c.VkInstance = undefined;
var surface: c.VkSurfaceKHR = undefined;
var physicalDevice: c.VkPhysicalDevice = undefined;
var device: c.VkDevice = undefined;
var graphicsQueue: c.VkQueue = undefined;
var presentQueue: c.VkQueue = undefined;

// MARK: init

pub fn init(window: ?*c.GLFWwindow) !void {
	if(c.gladLoaderLoadVulkan(null, null, null) == 0) {
		@panic("GLAD failed to load Vulkan functions");
	}
	createInstance();
	checkResult(c.glfwCreateWindowSurface(instance, window, null, &surface));
	try pickPhysicalDevice();
	if(c.gladLoaderLoadVulkan(instance, physicalDevice, null) == 0) {
		@panic("GLAD failed to load Vulkan functions");
	}
	createLogicalDevice();
	if(c.gladLoaderLoadVulkan(instance, physicalDevice, device) == 0) {
		@panic("GLAD failed to load Vulkan functions");
	}
	SwapChain.init();
}

pub fn deinit() void {
	SwapChain.deinit();
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

const deviceFeatures: c.VkPhysicalDeviceFeatures = .{
	.multiDrawIndirect = c.VK_TRUE,
	.dualSrcBlend = c.VK_TRUE,
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
		if(family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0 and family.queueFlags & c.VK_QUEUE_COMPUTE_BIT != 0) {
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

fn getDeviceScore(dev: c.VkPhysicalDevice) f32 {
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
		std.log.debug("\t{s}", .{@as([*:0]const u8, @ptrCast(&ext.extensionName))});
	}
	if(!findQueueFamilies(dev).isComplete() or !checkDeviceExtensionSupport(dev)) return 0;

	inline for(comptime std.meta.fieldNames(@TypeOf(deviceFeatures))) |name| {
		if(@field(deviceFeatures, name) == c.VK_TRUE and @field(features, name) == c.VK_FALSE) {
			std.log.warn("Rejecting device: {s} is not supported", .{name});
			return 0;
		}
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
		const score = getDeviceScore(dev);
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

// MARK: Logical Device

fn createLogicalDevice() void {
	const indices = findQueueFamilies(physicalDevice);
	var uniqueFamilies: std.AutoHashMapUnmanaged(u32, void) = .{};
	defer uniqueFamilies.deinit(main.stackAllocator.allocator);
	_ = uniqueFamilies.getOrPut(main.stackAllocator.allocator, indices.graphicsFamily.?) catch unreachable;
	_ = uniqueFamilies.getOrPut(main.stackAllocator.allocator, indices.presentFamily.?) catch unreachable;

	var queueCreateInfos = main.List(c.VkDeviceQueueCreateInfo).init(main.stackAllocator);
	defer queueCreateInfos.deinit();
	var iterator = uniqueFamilies.keyIterator();
	while(iterator.next()) |queueFamily| {
		queueCreateInfos.append(.{
			.sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
			.queueFamilyIndex = queueFamily.*,
			.queueCount = 1,
			.pQueuePriorities = &@as(f32, 1.0),
		});
	}

	const createInfo: c.VkDeviceCreateInfo = .{
		.sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
		.pQueueCreateInfos = queueCreateInfos.items.ptr,
		.queueCreateInfoCount = @intCast(queueCreateInfos.items.len),
		.pEnabledFeatures = &deviceFeatures,
		.ppEnabledLayerNames = validationLayers.ptr,
		.enabledLayerCount = if(checkValidationLayerSupport()) validationLayers.len else 0,
		.ppEnabledExtensionNames = &deviceExtensions,
		.enabledExtensionCount = @intCast(deviceExtensions.len),
	};
	checkResult(c.vkCreateDevice(physicalDevice, &createInfo, null, &device));
	c.vkGetDeviceQueue(device, indices.graphicsFamily.?, 0, &graphicsQueue);
	c.vkGetDeviceQueue(device, indices.presentFamily.?, 0, &presentQueue);
}

const SwapChain = struct { // MARK: SwapChain
	var swapChain: c.VkSwapchainKHR = null;
	var images: []c.VkImage = undefined;
	var imageViews: []c.VkImageView = undefined;
	var imageFormat: c.VkFormat = undefined;
	var extent: c.VkExtent2D = undefined;

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
			for(self.formats) |format| {
				if(format.format == c.VK_FORMAT_B8G8R8A8_SRGB and format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
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
			if(self.capabilities.currentExtent.width != std.math.maxInt(u32)) {
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
		const imageCount = @min(support.capabilities.minImageCount + 1, support.capabilities.maxImageCount -% 1 +| 1);

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
		if(queueFamilies.graphicsFamily.? != queueFamilies.presentFamily.?) {
			const queueFamilyIndices = [_]u32{queueFamilies.graphicsFamily.?, queueFamilies.presentFamily.?};
			createInfo.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
			createInfo.queueFamilyIndexCount = @intCast(queueFamilyIndices.len);
			createInfo.pQueueFamilyIndices = &queueFamilyIndices;
		} else {
			createInfo.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
		}

		checkResult(c.vkCreateSwapchainKHR(device, &createInfo, null, &swapChain));
		images = main.globalAllocator.alloc(c.VkImage, imageCount);
		var newImageCount = imageCount;
		checkResult(c.vkGetSwapchainImagesKHR(device, swapChain, &newImageCount, images.ptr));
		std.debug.assert(newImageCount == imageCount);

		imageViews = main.globalAllocator.alloc(c.VkImageView, imageCount);
		for(0..images.len) |i| {
			imageViews[i] = createImageView(images[i]);
		}
	}

	fn deinit() void {
		for(imageViews) |imageView| {
			c.vkDestroyImageView(device, imageView, null);
		}
		main.globalAllocator.free(imageViews);
		main.globalAllocator.free(images);
		c.vkDestroySwapchainKHR(device, swapChain, null);
	}
};
