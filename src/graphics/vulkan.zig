const std = @import("std");

const main = @import("main");
const c = main.Window.c;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const Errors = struct { // MARK: Errors
	pub const VK_SUCCESS: c_int = 0;
	pub const VK_NOT_READY: c_int = 1;
	pub const VK_TIMEOUT: c_int = 2;
	pub const VK_EVENT_SET: c_int = 3;
	pub const VK_EVENT_RESET: c_int = 4;
	pub const VK_INCOMPLETE: c_int = 5;
	pub const VK_ERROR_OUT_OF_HOST_MEMORY: c_int = -1;
	pub const VK_ERROR_OUT_OF_DEVICE_MEMORY: c_int = -2;
	pub const VK_ERROR_INITIALIZATION_FAILED: c_int = -3;
	pub const VK_ERROR_DEVICE_LOST: c_int = -4;
	pub const VK_ERROR_MEMORY_MAP_FAILED: c_int = -5;
	pub const VK_ERROR_LAYER_NOT_PRESENT: c_int = -6;
	pub const VK_ERROR_EXTENSION_NOT_PRESENT: c_int = -7;
	pub const VK_ERROR_FEATURE_NOT_PRESENT: c_int = -8;
	pub const VK_ERROR_INCOMPATIBLE_DRIVER: c_int = -9;
	pub const VK_ERROR_TOO_MANY_OBJECTS: c_int = -10;
	pub const VK_ERROR_FORMAT_NOT_SUPPORTED: c_int = -11;
	pub const VK_ERROR_FRAGMENTED_POOL: c_int = -12;
	pub const VK_ERROR_UNKNOWN: c_int = -13;
	pub const VK_ERROR_OUT_OF_POOL_MEMORY: c_int = -1000069000;
	pub const VK_ERROR_INVALID_EXTERNAL_HANDLE: c_int = -1000072003;
	pub const VK_ERROR_FRAGMENTATION: c_int = -1000161000;
	pub const VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS: c_int = -1000257000;
	pub const VK_PIPELINE_COMPILE_REQUIRED: c_int = 1000297000;
	pub const VK_ERROR_NOT_PERMITTED: c_int = -1000174001;
	pub const VK_ERROR_SURFACE_LOST_KHR: c_int = -1000000000;
	pub const VK_ERROR_NATIVE_WINDOW_IN_USE_KHR: c_int = -1000000001;
	pub const VK_SUBOPTIMAL_KHR: c_int = 1000001003;
	pub const VK_ERROR_OUT_OF_DATE_KHR: c_int = -1000001004;
	pub const VK_ERROR_INCOMPATIBLE_DISPLAY_KHR: c_int = -1000003001;
	pub const VK_ERROR_VALIDATION_FAILED_EXT: c_int = -1000011001;
	pub const VK_ERROR_INVALID_SHADER_NV: c_int = -1000012000;
	pub const VK_ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR: c_int = -1000023000;
	pub const VK_ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR: c_int = -1000023001;
	pub const VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR: c_int = -1000023002;
	pub const VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR: c_int = -1000023003;
	pub const VK_ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR: c_int = -1000023004;
	pub const VK_ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR: c_int = -1000023005;
	pub const VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT: c_int = -1000158000;
	pub const VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT: c_int = -1000255000;
	pub const VK_THREAD_IDLE_KHR: c_int = 1000268000;
	pub const VK_THREAD_DONE_KHR: c_int = 1000268001;
	pub const VK_OPERATION_DEFERRED_KHR: c_int = 1000268002;
	pub const VK_OPERATION_NOT_DEFERRED_KHR: c_int = 1000268003;
	pub const VK_ERROR_INVALID_VIDEO_STD_PARAMETERS_KHR: c_int = -1000299000;
	pub const VK_ERROR_COMPRESSION_EXHAUSTED_EXT: c_int = -1000338000;
	pub const VK_INCOMPATIBLE_SHADER_BINARY_EXT: c_int = 1000482000;
	pub const VK_PIPELINE_BINARY_MISSING_KHR: c_int = 1000483000;
	pub const VK_ERROR_NOT_ENOUGH_SPACE_KHR: c_int = -1000483000;
	pub const VK_ERROR_OUT_OF_POOL_MEMORY_KHR: c_int = -1000069000;
	pub const VK_ERROR_INVALID_EXTERNAL_HANDLE_KHR: c_int = -1000072003;
	pub const VK_ERROR_FRAGMENTATION_EXT: c_int = -1000161000;
	pub const VK_ERROR_NOT_PERMITTED_EXT: c_int = -1000174001;
	pub const VK_ERROR_NOT_PERMITTED_KHR: c_int = -1000174001;
	pub const VK_ERROR_INVALID_DEVICE_ADDRESS_EXT: c_int = -1000257000;
	pub const VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS_KHR: c_int = -1000257000;
	pub const VK_PIPELINE_COMPILE_REQUIRED_EXT: c_int = 1000297000;
	pub const VK_ERROR_PIPELINE_COMPILE_REQUIRED_EXT: c_int = 1000297000;
	pub const VK_ERROR_INCOMPATIBLE_SHADER_BINARY_EXT: c_int = 1000482000;
	pub const VK_RESULT_MAX_ENUM: c_int = 2147483647;
};

pub fn checkResult(result: c.VkResult) void {
	if(result != c.VK_SUCCESS) {
		inline for(@typeInfo(Errors).@"struct".decls) |decl| {
			if(result == @field(Errors, decl.name)) {
				std.log.err("Encountered a vulkan error: {s}", .{decl.name});
				return;
			}
		}
		std.log.err("Encountered a vulkan error with unknown error code {}", .{result});
	}
}

fn checkResultIfAvailable(result: anytype) void {
	if(@TypeOf(result) != void) {
		checkResult(result);
	}
}

fn allocEnumerationGeneric(function: anytype, allocator: NeverFailingAllocator, args: anytype) []@typeInfo(@typeInfo(@TypeOf(function)).@"fn".params[@typeInfo(@TypeOf(function)).@"fn".params.len - 1].type.?).pointer.child {
	const T = @typeInfo(@typeInfo(@TypeOf(function)).@"fn".params[@typeInfo(@TypeOf(function)).@"fn".params.len - 1].type.?).pointer.child;
	var count: u32 = 0;
	checkResultIfAvailable(@call(.auto, function, args ++ .{&count, null}));
	const list = allocator.alloc(T, count);
	checkResultIfAvailable(@call(.auto, function, args ++ .{&count, list.ptr}));
	return list;
}

pub fn enumerateInstanceLayerProperties(allocator: NeverFailingAllocator) []c.VkLayerProperties {
	return allocEnumerationGeneric(c.vkEnumerateInstanceLayerProperties, allocator, .{});
}

pub fn enumerateInstanceExtensionProperties(allocator: NeverFailingAllocator, layerName: ?[*:0]u8) []c.VkExtensionProperties {
	return allocEnumerationGeneric(c.vkEnumerateInstanceExtensionProperties, allocator, .{layerName});
}

pub const Instance = struct { // MARK: Instance
	var instance: c.VkInstance = undefined;

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

	pub fn init() void {
		if(c.gladLoaderLoadVulkan(null, null, null) == 0) {
			@panic("GLAD failed to load Vulkan functions");
		}
		const appInfo = c.VkApplicationInfo{
			.sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
			.pApplicationName = "Cubyz",
			.applicationVersion = c.VK_MAKE_VERSION(0, 0, 0),
			.pEngineName = "custom",
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
		// TODO: Use the debug callback when validation layers are enabled to write messages into the logger.
		// https://docs.vulkan.org/tutorial/latest/03_Drawing_a_triangle/00_Setup/02_Validation_layers.html#_message_callback
		checkResult(c.vkCreateInstance(&createInfo, null, &instance));
	}

	pub fn deinit() void {
		c.vkDestroyInstance(instance, null);
	}
};
