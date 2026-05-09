const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const vulkan = graphics.vulkan;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const c = @import("c");

const glslang = @cImport({
	@cInclude("glslang/Include/glslang_c_interface.h");
	@cInclude("glslang/Public/resource_limits_c.h");
});

const Shader = struct { // MARK: Shader
	id: c_uint,

	const ShaderStage = enum(glslang.glslang_stage_t) {
		vert = glslang.GLSLANG_STAGE_VERTEX,
		frag = glslang.GLSLANG_STAGE_FRAGMENT,
		comp = glslang.GLSLANG_STAGE_COMPUTE,
	};

	fn compileToSpirV(allocator: NeverFailingAllocator, source: []const u8, filename: []const u8, defines: []const u8, shaderStage: ShaderStage) ![]c_uint {
		const versionLineEnd = if (std.mem.indexOfScalar(u8, source, '\n')) |len| len + 1 else 0;
		const versionLine = source[0..versionLineEnd];
		const sourceLines = source[versionLineEnd..];

		var sourceWithDefines = main.List(u8).init(main.stackAllocator);
		defer sourceWithDefines.deinit();
		sourceWithDefines.appendSlice(versionLine);
		sourceWithDefines.appendSlice(defines);
		sourceWithDefines.appendSlice(sourceLines);
		sourceWithDefines.append(0);

		const input = glslang.glslang_input_t{
			.language = glslang.GLSLANG_SOURCE_GLSL,
			.stage = @intFromEnum(shaderStage),
			.client = glslang.GLSLANG_CLIENT_VULKAN,
			.client_version = glslang.GLSLANG_TARGET_VULKAN_1_0,
			.target_language = glslang.GLSLANG_TARGET_SPV,
			.target_language_version = glslang.GLSLANG_TARGET_SPV_1_0,
			.code = sourceWithDefines.items.ptr,
			.default_version = 100,
			.default_profile = glslang.GLSLANG_NO_PROFILE,
			.force_default_version_and_profile = glslang.false,
			.forward_compatible = glslang.false,
			.messages = glslang.GLSLANG_MSG_DEFAULT_BIT,
			.resource = glslang.glslang_default_resource(),
			.callbacks = .{}, // TODO: Add support for shader includes
			.callbacks_ctx = null,
		};
		const shader = glslang.glslang_shader_create(&input);
		defer glslang.glslang_shader_delete(shader);
		if (glslang.glslang_shader_preprocess(shader, &input) == 0) {
			std.log.err("Error preprocessing shader {s}:\n{s}\n{s}\n", .{filename, glslang.glslang_shader_get_info_log(shader), glslang.glslang_shader_get_info_debug_log(shader)});
			return error.FailedCompiling;
		}

		if (glslang.glslang_shader_parse(shader, &input) == 0) {
			std.log.err("Error parsing shader {s}:\n{s}\n{s}\n", .{filename, glslang.glslang_shader_get_info_log(shader), glslang.glslang_shader_get_info_debug_log(shader)});
			return error.FailedCompiling;
		}

		const program = glslang.glslang_program_create();
		defer glslang.glslang_program_delete(program);
		glslang.glslang_program_add_shader(program, shader);

		if (glslang.glslang_program_link(program, glslang.GLSLANG_MSG_SPV_RULES_BIT | glslang.GLSLANG_MSG_VULKAN_RULES_BIT) == 0) {
			std.log.err("Error linking shader {s}:\n{s}\n{s}\n", .{filename, glslang.glslang_shader_get_info_log(shader), glslang.glslang_shader_get_info_debug_log(shader)});
			return error.FailedCompiling;
		}

		glslang.glslang_program_SPIRV_generate(program, @intFromEnum(shaderStage));
		const result = allocator.alloc(c_uint, glslang.glslang_program_SPIRV_get_size(program));
		glslang.glslang_program_SPIRV_get(program, result.ptr);
		return result;
	}

	fn addShader(self: *const Shader, filename: []const u8, defines: []const u8, shaderStage: c_uint) !void {
		const source = main.files.cwd().read(main.stackAllocator, filename) catch |err| {
			std.log.err("Couldn't read shader file: {s}", .{filename});
			return err;
		};
		defer main.stackAllocator.free(source);

		const shader = c.glCreateShader(shaderStage);
		defer c.glDeleteShader(shader);

		const versionLineEnd = if (std.mem.indexOfScalar(u8, source, '\n')) |len| len + 1 else 0;
		const versionLine = source[0..versionLineEnd];
		const sourceLines = source[versionLineEnd..];

		const sourceLen: [3]c_int = .{@intCast(versionLine.len), @intCast(defines.len), @intCast(sourceLines.len)};
		c.glShaderSource(shader, 3, &[3][*c]const u8{versionLine.ptr, defines.ptr, sourceLines.ptr}, &sourceLen);

		c.glCompileShader(shader);

		var success: c_int = undefined;
		c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &success);
		if (success != c.GL_TRUE) {
			var len: u32 = undefined;
			c.glGetShaderiv(shader, c.GL_INFO_LOG_LENGTH, @ptrCast(&len));
			var buf: [4096]u8 = undefined;
			c.glGetShaderInfoLog(shader, 4096, @ptrCast(&len), &buf);
			std.log.err("Error compiling shader {s}:\n{s}\n", .{filename, buf[0..len]});
			return error.FailedCompiling;
		}

		c.glAttachShader(self.id, shader);
	}

	fn link(self: *const Shader, file: []const u8) !void {
		c.glLinkProgram(self.id);

		var success: c_int = undefined;
		c.glGetProgramiv(self.id, c.GL_LINK_STATUS, &success);
		if (success != c.GL_TRUE) {
			var len: u32 = undefined;
			c.glGetProgramiv(self.id, c.GL_INFO_LOG_LENGTH, @ptrCast(&len));
			var buf: [4096]u8 = undefined;
			c.glGetProgramInfoLog(self.id, 4096, @ptrCast(&len), &buf);
			std.log.err("Error Linking Shader program {s}:\n{s}\n", .{file, buf[0..len]});
			return error.FailedLinking;
		}
	}

	fn init(vertex: []const u8, fragment: []const u8, defines: []const u8, uniformStruct: anytype) Shader {
		const shader = Shader{.id = c.glCreateProgram()};
		shader.addShader(vertex, defines, c.GL_VERTEX_SHADER) catch return shader;
		shader.addShader(fragment, defines, c.GL_FRAGMENT_SHADER) catch return shader;
		shader.link(fragment) catch return shader;

		if (@TypeOf(uniformStruct) != @TypeOf(null)) {
			inline for (@typeInfo(@TypeOf(uniformStruct.*)).@"struct".fields) |field| {
				if (field.type == c_int) {
					@field(uniformStruct, field.name) = c.glGetUniformLocation(shader.id, field.name[0..]);
				}
			}
		}
		return shader;
	}

	fn initCompute(compute: []const u8, defines: []const u8, uniformStruct: anytype) Shader {
		const shader = Shader{.id = c.glCreateProgram()};
		shader.addShader(compute, defines, c.GL_COMPUTE_SHADER) catch return shader;
		shader.link(compute) catch return shader;

		if (@TypeOf(uniformStruct) != @TypeOf(null)) {
			inline for (@typeInfo(@TypeOf(uniformStruct.*)).@"struct".fields) |field| {
				if (field.type == c_int) {
					@field(uniformStruct, field.name) = c.glGetUniformLocation(shader.id, field.name[0..]);
				}
			}
		}
		return shader;
	}

	fn createShaderModule(path: []const u8, defines: []const u8, stage: ShaderStage) !c.VkShaderModule {
		const source = main.files.cwd().read(main.stackAllocator, path) catch |err| {
			std.log.err("Couldn't read shader file: {s}", .{path});
			return err;
		};
		defer main.stackAllocator.free(source);

		const spirv = try compileToSpirV(main.stackAllocator, source, path, defines, stage);
		defer main.stackAllocator.free(spirv);

		const createInfo = c.VkShaderModuleCreateInfo{
			.sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
			.codeSize = @intCast(spirv.len*@sizeOf(u32)),
			.pCode = spirv.ptr,
		};

		var shaderModule: c.VkShaderModule = undefined;
		try vulkan.checkResultErr(c.vkCreateShaderModule(vulkan.device, &createInfo, null, &shaderModule));
		return shaderModule;
	}

	fn bind(self: *const Shader) void {
		c.glUseProgram(self.id);
	}

	fn deinit(self: *const Shader) void {
		c.glDeleteProgram(self.id);
	}
};

const RasterizationState = struct { // MARK: RasterizationState
	depthClamp: bool = true,
	rasterizerDiscard: bool = false,
	polygonMode: PolygonMode = .fill,
	cullMode: CullModeFlags = .back,
	frontFace: FrontFace = .counterClockwise,
	depthBias: ?DepthBias = null,
	lineWidth: f32 = 1,

	const PolygonMode = enum(c.VkPolygonMode) {
		fill = c.VK_POLYGON_MODE_FILL,
		line = c.VK_POLYGON_MODE_LINE,
		point = c.VK_POLYGON_MODE_POINT,
	};

	const CullModeFlags = enum(c.VkCullModeFlags) {
		none = c.VK_CULL_MODE_NONE,
		front = c.VK_CULL_MODE_FRONT_BIT,
		back = c.VK_CULL_MODE_BACK_BIT,
		frontAndBack = c.VK_CULL_MODE_FRONT_AND_BACK,
	};

	const FrontFace = enum(c.VkFrontFace) {
		counterClockwise = c.VK_FRONT_FACE_COUNTER_CLOCKWISE,
		clockwise = c.VK_FRONT_FACE_CLOCKWISE,
	};

	const DepthBias = struct {
		constantFactor: f32,
		clamp: f32,
		slopeFactor: f32,
	};

	pub fn toVulkan(self: RasterizationState) c.VkPipelineRasterizationStateCreateInfo {
		return .{
			.sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
			.depthClampEnable = @intFromBool(self.depthClamp),
			.rasterizerDiscardEnable = @intFromBool(self.rasterizerDiscard),
			.polygonMode = @intFromEnum(self.polygonMode),
			.lineWidth = self.lineWidth,
			.cullMode = @intFromEnum(self.cullMode),
			.frontFace = @intFromEnum(self.frontFace),
			.depthBiasEnable = @intFromBool(self.depthBias != null),
			.depthBiasConstantFactor = if (self.depthBias) |d| d.constantFactor else 0,
			.depthBiasClamp = if (self.depthBias) |d| d.clamp else 0,
			.depthBiasSlopeFactor = if (self.depthBias) |d| d.slopeFactor else 0,
		};
	}
};

const MultisampleState = struct { // MARK: MultisampleState
	rasterizationSamples: Count = .@"1",
	sampleShading: bool = false,
	minSampleShading: f32 = undefined,
	sampleMask: [*]const c.VkSampleMask = &.{0, 0},
	alphaToCoverage: bool = false,
	alphaToOne: bool = false,

	const Count = enum(c.VkSampleCountFlags) {
		@"1" = c.VK_SAMPLE_COUNT_1_BIT,
		@"2" = c.VK_SAMPLE_COUNT_2_BIT,
		@"4" = c.VK_SAMPLE_COUNT_4_BIT,
		@"8" = c.VK_SAMPLE_COUNT_8_BIT,
		@"16" = c.VK_SAMPLE_COUNT_16_BIT,
		@"32" = c.VK_SAMPLE_COUNT_32_BIT,
		@"64" = c.VK_SAMPLE_COUNT_64_BIT,
	};

	pub fn toVulkan(self: MultisampleState) c.VkPipelineMultisampleStateCreateInfo {
		return .{
			.sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
			.rasterizationSamples = @intFromEnum(self.rasterizationSamples),
			.sampleShadingEnable = @intFromBool(self.sampleShading),
			.minSampleShading = self.minSampleShading,
			.pSampleMask = self.sampleMask,
			.alphaToCoverageEnable = @intFromBool(self.alphaToCoverage),
			.alphaToOneEnable = @intFromBool(self.alphaToOne),
		};
	}
};

const DepthStencilState = struct { // MARK: DepthStencilState
	depthTest: bool,
	depthWrite: bool = true,
	depthCompare: CompareOp = .less,
	depthBoundsTest: ?DepthBoundsTest = null,
	stencilTest: ?StencilTest = null,

	const CompareOp = enum(c.VkCompareOp) {
		never = c.VK_COMPARE_OP_NEVER,
		less = c.VK_COMPARE_OP_LESS,
		equal = c.VK_COMPARE_OP_EQUAL,
		lessOrEqual = c.VK_COMPARE_OP_LESS_OR_EQUAL,
		greater = c.VK_COMPARE_OP_GREATER,
		notEqual = c.VK_COMPARE_OP_NOT_EQUAL,
		greateOrEqual = c.VK_COMPARE_OP_GREATER_OR_EQUAL,
		always = c.VK_COMPARE_OP_ALWAYS,
	};

	const StencilTest = struct {
		front: StencilOpState,
		back: StencilOpState,

		const StencilOpState = struct {
			failOp: StencilOp,
			passOp: StencilOp,
			depthFailOp: StencilOp,
			compareOp: CompareOp,
			compareMask: u32,
			writeMask: u32,
			reference: u32,

			const StencilOp = enum(c.VkStencilOp) {
				keep = c.VK_STENCIL_OP_KEEP,
				zero = c.VK_STENCIL_OP_ZERO,
				replace = c.VK_STENCIL_OP_REPLACE,
				incrementAndClamp = c.VK_STENCIL_OP_INCREMENT_AND_CLAMP,
				decrementAndClamp = c.VK_STENCIL_OP_DECREMENT_AND_CLAMP,
				invert = c.VK_STENCIL_OP_INVERT,
				incrementAndWrap = c.VK_STENCIL_OP_INCREMENT_AND_WRAP,
				decrementAndWrap = c.VK_STENCIL_OP_DECREMENT_AND_WRAP,
			};

			fn toVulkan(self: StencilOpState) c.VkStencilOpState {
				return .{
					.failOp = @intFromEnum(self.failOp),
					.passOp = @intFromEnum(self.passOp),
					.depthFailOp = @intFromEnum(self.depthFailOp),
					.compareOp = @intFromEnum(self.compareOp),
					.compareMask = self.compareMask,
					.writeMask = self.writeMask,
					.reference = self.reference,
				};
			}
		};
	};

	const DepthBoundsTest = struct {
		min: f32,
		max: f32,
	};

	pub fn toVulkan(self: DepthStencilState) c.VkPipelineDepthStencilStateCreateInfo {
		return .{
			.sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
			.depthTestEnable = @intFromBool(self.depthTest),
			.depthWriteEnable = @intFromBool(self.depthWrite),
			.depthCompareOp = @intFromEnum(self.depthCompare),
			.depthBoundsTestEnable = @intFromBool(self.depthBoundsTest != null),
			.stencilTestEnable = @intFromBool(self.stencilTest != null),
			.front = if (self.stencilTest) |s| s.front.toVulkan() else undefined,
			.back = if (self.stencilTest) |s| s.back.toVulkan() else undefined,
			.minDepthBounds = if (self.depthBoundsTest) |d| d.min else undefined,
			.maxDepthBounds = if (self.depthBoundsTest) |d| d.max else undefined,
		};
	}
};

const ColorBlendAttachmentState = struct { // MARK: ColorBlendAttachmentState
	enabled: bool = true,
	srcColorBlendFactor: BlendFactor,
	dstColorBlendFactor: BlendFactor,
	colorBlendOp: BlendOp,
	srcAlphaBlendFactor: BlendFactor,
	dstAlphaBlendFactor: BlendFactor,
	alphaBlendOp: BlendOp,
	colorWriteMask: ColorComponentFlags = .all,

	pub const alphaBlending: ColorBlendAttachmentState = .{
		.srcColorBlendFactor = .srcAlpha,
		.dstColorBlendFactor = .oneMinusSrcAlpha,
		.colorBlendOp = .add,
		.srcAlphaBlendFactor = .srcAlpha,
		.dstAlphaBlendFactor = .oneMinusSrcAlpha,
		.alphaBlendOp = .add,
	};
	pub const noBlending: ColorBlendAttachmentState = .{
		.enabled = false,
		.srcColorBlendFactor = .zero,
		.dstColorBlendFactor = .zero,
		.colorBlendOp = .add,
		.srcAlphaBlendFactor = .zero,
		.dstAlphaBlendFactor = .zero,
		.alphaBlendOp = .add,
	};

	const BlendFactor = enum(c.VkBlendFactor) {
		zero = c.VK_BLEND_FACTOR_ZERO,
		one = c.VK_BLEND_FACTOR_ONE,
		srcColor = c.VK_BLEND_FACTOR_SRC_COLOR,
		oneMinusSrcColor = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR,
		dstColor = c.VK_BLEND_FACTOR_DST_COLOR,
		oneMinusDstColor = c.VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR,
		srcAlpha = c.VK_BLEND_FACTOR_SRC_ALPHA,
		oneMinusSrcAlpha = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
		dstAlpha = c.VK_BLEND_FACTOR_DST_ALPHA,
		oneMinusDstAlpha = c.VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA,
		constantColor = c.VK_BLEND_FACTOR_CONSTANT_COLOR,
		oneMinusConstantColor = c.VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_COLOR,
		constantAlpha = c.VK_BLEND_FACTOR_CONSTANT_ALPHA,
		oneMinusConstantAlpha = c.VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_ALPHA,
		srcAlphaSaturate = c.VK_BLEND_FACTOR_SRC_ALPHA_SATURATE,
		src1Color = c.VK_BLEND_FACTOR_SRC1_COLOR,
		oneMinusSrc1Color = c.VK_BLEND_FACTOR_ONE_MINUS_SRC1_COLOR,
		src1Alpha = c.VK_BLEND_FACTOR_SRC1_ALPHA,
		oneMinusSrc1Alpha = c.VK_BLEND_FACTOR_ONE_MINUS_SRC1_ALPHA,

		fn toGl(self: BlendFactor) c.GLenum {
			return switch (self) {
				.zero => c.GL_ZERO,
				.one => c.GL_ONE,
				.srcColor => c.GL_SRC_COLOR,
				.oneMinusSrcColor => c.GL_ONE_MINUS_SRC_COLOR,
				.dstColor => c.GL_DST_COLOR,
				.oneMinusDstColor => c.GL_ONE_MINUS_DST_COLOR,
				.srcAlpha => c.GL_SRC_ALPHA,
				.oneMinusSrcAlpha => c.GL_ONE_MINUS_SRC_ALPHA,
				.dstAlpha => c.GL_DST_ALPHA,
				.oneMinusDstAlpha => c.GL_ONE_MINUS_DST_ALPHA,
				.constantColor => c.GL_CONSTANT_COLOR,
				.oneMinusConstantColor => c.GL_ONE_MINUS_CONSTANT_COLOR,
				.constantAlpha => c.GL_CONSTANT_ALPHA,
				.oneMinusConstantAlpha => c.GL_ONE_MINUS_CONSTANT_ALPHA,
				.srcAlphaSaturate => c.GL_SRC_ALPHA_SATURATE,
				.src1Color => c.GL_SRC1_COLOR,
				.oneMinusSrc1Color => c.GL_ONE_MINUS_SRC1_COLOR,
				.src1Alpha => c.GL_SRC1_ALPHA,
				.oneMinusSrc1Alpha => c.GL_ONE_MINUS_SRC1_ALPHA,
			};
		}
	};

	const BlendOp = enum(c.VkBlendOp) {
		add = c.VK_BLEND_OP_ADD,
		subtract = c.VK_BLEND_OP_SUBTRACT,
		reverseSubtract = c.VK_BLEND_OP_REVERSE_SUBTRACT,
		min = c.VK_BLEND_OP_MIN,
		max = c.VK_BLEND_OP_MAX,

		fn toGl(self: BlendOp) c.GLenum {
			return switch (self) {
				.add => c.GL_FUNC_ADD,
				.subtract => c.GL_FUNC_SUBTRACT,
				.reverseSubtract => c.GL_FUNC_REVERSE_SUBTRACT,
				.min => c.GL_MIN,
				.max => c.GL_MAX,
			};
		}
	};

	const ColorComponentFlags = packed struct {
		r: bool,
		g: bool,
		b: bool,
		a: bool,
		pub const all: ColorComponentFlags = .{.r = true, .g = true, .b = true, .a = true};
		pub const none: ColorComponentFlags = .{.r = false, .g = false, .b = false, .a = false};
	};

	pub fn toVulkan(self: ColorBlendAttachmentState) c.VkPipelineColorBlendAttachmentState {
		return .{
			.blendEnable = @intFromBool(self.enabled),
			.srcColorBlendFactor = @intFromEnum(self.srcColorBlendFactor),
			.dstColorBlendFactor = @intFromEnum(self.dstColorBlendFactor),
			.colorBlendOp = @intFromEnum(self.colorBlendOp),
			.srcAlphaBlendFactor = @intFromEnum(self.srcAlphaBlendFactor),
			.dstAlphaBlendFactor = @intFromEnum(self.dstAlphaBlendFactor),
			.alphaBlendOp = @intFromEnum(self.alphaBlendOp),
			.colorWriteMask = @as(u4, @bitCast(self.colorWriteMask)),
		};
	}
};

const ColorBlendState = struct { // MARK: ColorBlendState
	logicOp: ?LogicOp = null,
	attachments: []const ColorBlendAttachmentState,
	blendConstants: [4]f32 = .{0, 0, 0, 0},

	const LogicOp = enum(c.VkLogicOp) {
		clear = c.VK_LOGIC_OP_CLEAR,
		@"and" = c.VK_LOGIC_OP_AND,
		andReverse = c.VK_LOGIC_OP_AND_REVERSE,
		copy = c.VK_LOGIC_OP_COPY,
		andInverted = c.VK_LOGIC_OP_AND_INVERTED,
		noOp = c.VK_LOGIC_OP_NO_OP,
		xor = c.VK_LOGIC_OP_XOR,
		@"or" = c.VK_LOGIC_OP_OR,
		nor = c.VK_LOGIC_OP_NOR,
		equivalent = c.VK_LOGIC_OP_EQUIVALENT,
		invert = c.VK_LOGIC_OP_INVERT,
		orReverse = c.VK_LOGIC_OP_OR_REVERSE,
		copyInverted = c.VK_LOGIC_OP_COPY_INVERTED,
		orInverted = c.VK_LOGIC_OP_OR_INVERTED,
		nand = c.VK_LOGIC_OP_NAND,
		set = c.VK_LOGIC_OP_SET,
	};

	pub fn toVulkan(self: ColorBlendState, attachments: []const c.VkPipelineColorBlendAttachmentState) c.VkPipelineColorBlendStateCreateInfo {
		return .{
			.sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
			.logicOpEnable = @intFromBool(self.logicOp != null),
			.logicOp = if (self.logicOp) |l| @intFromEnum(l) else undefined,
			.attachmentCount = @intCast(attachments.len),
			.pAttachments = attachments.ptr,
			.blendConstants = self.blendConstants,
		};
	}
};

pub const DescriptorSetLayoutBinding = extern struct { // MARK: DescriptorSetLayoutBinding
	binding: u32,
	type: enum(c_int) {
		sampler = c.VK_DESCRIPTOR_TYPE_SAMPLER,
		combinedImageSampler = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
		sampledImage = c.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
		storageImage = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
		uniformTexelBuffer = c.VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER,
		storageTexelBuffer = c.VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER,
		uniformBuffer = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
		storageBuffer = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
		uniformBufferDynamic = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
		storageBufferDynamic = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC,
		inputAttachment = c.VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT,
	},
	count: u32,
	stageFlags: packed struct(c_int) {
		vertex: bool = false,
		tessellationControl: bool = false,
		tessellationEvaluation: bool = false,
		geometriy: bool = false,
		fragment: bool = false,
		compute: bool = false,
		_: u26 = 0,
	},
	immutableSamplers: ?[*]const c.VkSampler = null,
};

pub const Pipeline = struct { // MARK: Pipeline
	shader: Shader,
	rasterState: RasterizationState,
	multisampleState: MultisampleState = .{}, // TODO: Not implemented
	depthStencilState: DepthStencilState,
	blendState: ColorBlendState,
	vulkanCreationSuccessful: bool = false, // TODO: Remove after all Vulkan pipelines compile
	pipelineLayout: c.VkPipelineLayout = undefined,
	descriptorSetLayout: c.VkDescriptorSetLayout = undefined,
	graphicsPipeline: c.VkPipeline = undefined,

	fn initVulkan(self: *Pipeline, vertexPath: []const u8, fragmentPath: []const u8, defines: []const u8, VertexType: type, bindings: []const DescriptorSetLayoutBinding) !void {
		const vertModule = try Shader.createShaderModule(vertexPath, defines, .vert);
		defer c.vkDestroyShaderModule(vulkan.device, vertModule, null);
		const fragModule = try Shader.createShaderModule(fragmentPath, defines, .frag);
		defer c.vkDestroyShaderModule(vulkan.device, fragModule, null);

		const shaderStages = [_]c.VkPipelineShaderStageCreateInfo{
			.{
				.sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
				.stage = c.VK_SHADER_STAGE_VERTEX_BIT,
				.module = vertModule,
				.pName = "main",
			},
			.{
				.sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
				.stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
				.module = fragModule,
				.pName = "main",
			},
		};

		const dynamicStates = [_]c.VkDynamicState{
			c.VK_DYNAMIC_STATE_VIEWPORT,
			c.VK_DYNAMIC_STATE_SCISSOR,
		};
		const dynamicState: c.VkPipelineDynamicStateCreateInfo = .{
			.sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
			.dynamicStateCount = @intCast(dynamicStates.len),
			.pDynamicStates = &dynamicStates,
		};
		const bindingDescription: c.VkVertexInputBindingDescription = .{ // TODO: Do we need this as a configurable input? It is only needed for instanced rendering as far as I can tell.
			.binding = 0,
			.stride = @sizeOf(VertexType),
			.inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
		};
		const vertexInputInfo: c.VkPipelineVertexInputStateCreateInfo = .{
			.sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
			.vertexBindingDescriptionCount = 1,
			.pVertexBindingDescriptions = &bindingDescription,
			.vertexAttributeDescriptionCount = VertexType.attributeDescriptions.len,
			.pVertexAttributeDescriptions = VertexType.attributeDescriptions.ptr,
		};
		const inputAssembly: c.VkPipelineInputAssemblyStateCreateInfo = .{
			.sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
			.topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, // TODO: Make this an input
			.primitiveRestartEnable = c.VK_FALSE, // TODO: Make this an input
		};
		const viewport: c.VkViewport = .{}; // overwritten dynamically
		const scissor: c.VkRect2D = .{}; // overwritten dynamically
		const viewportState: c.VkPipelineViewportStateCreateInfo = .{
			.sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
			.viewportCount = 1,
			.pViewports = &viewport,
			.scissorCount = 1,
			.pScissors = &scissor,
		};
		const rasterState = self.rasterState.toVulkan();
		const multisampleState = self.multisampleState.toVulkan();
		const depthStencilState = self.depthStencilState.toVulkan();
		const attachments = main.stackAllocator.alloc(c.VkPipelineColorBlendAttachmentState, self.blendState.attachments.len);
		defer main.stackAllocator.free(attachments);
		for (attachments, self.blendState.attachments) |*dest, src| {
			dest.* = src.toVulkan();
		}
		const blendState = self.blendState.toVulkan(attachments);

		const descriptorSetLayoutInfo = c.VkDescriptorSetLayoutCreateInfo{
			.sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
			.bindingCount = @intCast(bindings.len),
			.pBindings = @ptrCast(bindings.ptr),
		};
		try vulkan.checkResultErr(c.vkCreateDescriptorSetLayout(vulkan.device, &descriptorSetLayoutInfo, null, &self.descriptorSetLayout));
		errdefer c.vkDestroyDescriptorSetLayout(vulkan.device, self.descriptorSetLayout, null);

		const pipelineLayoutInfo = c.VkPipelineLayoutCreateInfo{ // TODO: Configure push constants
			.sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
			.setLayoutCount = 1,
			.pSetLayouts = &self.descriptorSetLayout,
		};
		try vulkan.checkResultErr(c.vkCreatePipelineLayout(vulkan.device, &pipelineLayoutInfo, null, &self.pipelineLayout));
		errdefer c.vkDestroyPipelineLayout(vulkan.device, self.pipelineLayout, null);

		const pipelineInfo = c.VkGraphicsPipelineCreateInfo{
			.sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
			.stageCount = @intCast(shaderStages.len),
			.pStages = &shaderStages,
			.pVertexInputState = &vertexInputInfo,
			.pInputAssemblyState = &inputAssembly,
			.pViewportState = &viewportState,
			.pRasterizationState = &rasterState,
			.pMultisampleState = &multisampleState,
			.pDepthStencilState = &depthStencilState,
			.pColorBlendState = &blendState,
			.pDynamicState = &dynamicState,
			.layout = self.pipelineLayout,
			.renderPass = graphics.RenderPass.renderToWindow.renderPass, // TODO: Allow configuring this
			.subpass = 0,
		};
		try vulkan.checkResultErr(c.vkCreateGraphicsPipelines(vulkan.device, null, 1, &pipelineInfo, null, &self.graphicsPipeline));
		self.vulkanCreationSuccessful = true;
	}

	pub fn init(vertexPath: []const u8, fragmentPath: []const u8, defines: []const u8, uniformStruct: anytype, VertexType: type, bindings: []const DescriptorSetLayoutBinding, rasterState: RasterizationState, depthStencilState: DepthStencilState, blendState: ColorBlendState) Pipeline {
		std.debug.assert(depthStencilState.depthBoundsTest == null); // Only available in Vulkan 1.3
		std.debug.assert(depthStencilState.stencilTest == null); // TODO: Not yet implemented
		std.debug.assert(rasterState.lineWidth <= 1); // Larger values are poorly supported among drivers
		std.debug.assert(blendState.logicOp == null); // TODO: Not yet implemented
		var self: Pipeline = .{
			.shader = .init(vertexPath, fragmentPath, defines, uniformStruct),
			.rasterState = rasterState,
			.multisampleState = .{}, // TODO: Not implemented
			.depthStencilState = depthStencilState,
			.blendState = blendState,
		};
		if (main.settings.launchConfig.vulkanTestingMode) {
			self.initVulkan(vertexPath, fragmentPath, defines, VertexType, bindings) catch |err| {
				std.log.err("Vulkan pipeline creation for paths {s} {s} failed with error {s}", .{vertexPath, fragmentPath, @errorName(err)});
			};
		}
		return self;
	}

	pub fn deinit(self: Pipeline) void {
		self.shader.deinit();
		if (self.vulkanCreationSuccessful) {
			c.vkDestroyPipeline(vulkan.device, self.graphicsPipeline, null);
			c.vkDestroyPipelineLayout(vulkan.device, self.pipelineLayout, null);
			c.vkDestroyDescriptorSetLayout(vulkan.device, self.descriptorSetLayout, null);
		}
	}

	fn conditionalEnable(typ: c.GLenum, val: bool) void {
		if (val) {
			c.glEnable(typ);
		} else {
			c.glDisable(typ);
		}
	}

	pub fn bind(self: Pipeline, scissor: ?c.VkRect2D) void {
		self.shader.bind();
		if (scissor) |s| {
			c.glEnable(c.GL_SCISSOR_TEST);
			c.glScissor(s.offset.x, s.offset.y, @intCast(s.extent.width), @intCast(s.extent.height));
		} else {
			c.glDisable(c.GL_SCISSOR_TEST);
		}

		conditionalEnable(c.GL_DEPTH_CLAMP, self.rasterState.depthClamp);
		conditionalEnable(c.GL_RASTERIZER_DISCARD, self.rasterState.rasterizerDiscard);
		conditionalEnable(c.GL_RASTERIZER_DISCARD, self.rasterState.rasterizerDiscard);
		c.glPolygonMode(c.GL_FRONT_AND_BACK, switch (self.rasterState.polygonMode) {
			.fill => c.GL_FILL,
			.line => c.GL_LINE,
			.point => c.GL_POINT,
		});
		if (self.rasterState.cullMode != .none) {
			c.glEnable(c.GL_CULL_FACE);
			c.glCullFace(switch (self.rasterState.cullMode) {
				.front => c.GL_FRONT,
				.back => c.GL_BACK,
				.frontAndBack => c.GL_FRONT_AND_BACK,
				else => unreachable,
			});
		} else {
			c.glDisable(c.GL_CULL_FACE);
		}
		c.glFrontFace(switch (self.rasterState.frontFace) {
			.counterClockwise => c.GL_CCW,
			.clockwise => c.GL_CW,
		});
		if (self.rasterState.depthBias) |depthBias| {
			c.glEnable(c.GL_POLYGON_OFFSET_FILL);
			c.glEnable(c.GL_POLYGON_OFFSET_LINE);
			c.glEnable(c.GL_POLYGON_OFFSET_POINT);
			c.glPolygonOffset(depthBias.slopeFactor, depthBias.constantFactor);
		} else {
			c.glDisable(c.GL_POLYGON_OFFSET_FILL);
			c.glDisable(c.GL_POLYGON_OFFSET_LINE);
			c.glDisable(c.GL_POLYGON_OFFSET_POINT);
		}
		c.glLineWidth(self.rasterState.lineWidth);

		// TODO: Multisampling

		conditionalEnable(c.GL_DEPTH_TEST, self.depthStencilState.depthTest);
		c.glDepthMask(@intFromBool(self.depthStencilState.depthWrite));
		c.glDepthFunc(switch (self.depthStencilState.depthCompare) {
			.never => c.GL_NEVER,
			.less => c.GL_LESS,
			.equal => c.GL_EQUAL,
			.lessOrEqual => c.GL_LEQUAL,
			.greater => c.GL_GREATER,
			.notEqual => c.GL_NOTEQUAL,
			.greateOrEqual => c.GL_GEQUAL,
			.always => c.GL_ALWAYS,
		});
		// TODO: stencilTest

		// TODO: logicOp
		for (self.blendState.attachments, 0..) |attachment, i| {
			c.glColorMask(@intFromBool(attachment.colorWriteMask.r), @intFromBool(attachment.colorWriteMask.g), @intFromBool(attachment.colorWriteMask.b), @intFromBool(attachment.colorWriteMask.a));
			if (!attachment.enabled) {
				c.glDisable(c.GL_BLEND);
				continue;
			}
			c.glEnable(c.GL_BLEND);
			c.glBlendEquationSeparatei(@intCast(i), attachment.colorBlendOp.toGl(), attachment.alphaBlendOp.toGl());
			c.glBlendFuncSeparatei(@intCast(i), attachment.srcColorBlendFactor.toGl(), attachment.dstColorBlendFactor.toGl(), attachment.srcAlphaBlendFactor.toGl(), attachment.dstAlphaBlendFactor.toGl());
		}
		c.glBlendColor(self.blendState.blendConstants[0], self.blendState.blendConstants[1], self.blendState.blendConstants[2], self.blendState.blendConstants[3]);
	}
};

pub const ComputePipeline = struct { // MARK: ComputePipeline
	shader: Shader,

	pub fn init(computePath: []const u8, defines: []const u8, uniformStruct: anytype) ComputePipeline {
		return .{
			.shader = .initCompute(computePath, defines, uniformStruct),
		};
	}

	pub fn deinit(self: ComputePipeline) void {
		self.shader.deinit();
	}

	pub fn bind(self: ComputePipeline) void {
		self.shader.bind();
	}
};

pub fn init() void { // MARK: init()
	if (glslang.glslang_initialize_process() == glslang.false) std.log.err("glslang_initialize_process failed", .{});
}

pub fn deinit() void { // MARK: deinit()
	glslang.glslang_finalize_process();
}
