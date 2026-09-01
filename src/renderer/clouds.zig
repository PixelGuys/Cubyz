const std = @import("std");

const main = @import("main");
const chunk = main.chunk;
const graphics = main.graphics;
const random = main.random;
const settings = main.settings;
const vec = main.vec;
const Vec2i = vec.Vec2i;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;

const c = @import("c");

const configPath = "assets/cubyz/clouds.txt";
const ssboBinding = 16;
const maxClouds = 4096;
const maxCellsPerAxis = 80;
const reloadInterval: std.Io.Duration = .fromMilliseconds(500);
const cubeVertexCount = 36;

const Config = struct {
	height: f32 = 256,
	speed: f32 = 1,
	windX: f32 = 1,
	windY: f32 = 0,
	cellSize: f32 = 96,
	density: f32 = 0.55,
	minSizeXy: f32 = 24,
	maxSizeXy: f32 = 88,
	minSizeZ: f32 = 4,
	maxSizeZ: f32 = 22,
	opacity: f32 = 0.7,
	colorR: f32 = 1,
	colorG: f32 = 1,
	colorB: f32 = 1,
	seed: u64 = 1,
	debug: f32 = 0,
};

const GpuCloud = extern struct {
	min: [4]f32,
	size: [4]f32,
};

var depthPipeline: graphics.Pipeline = undefined;
var pipeline: graphics.Pipeline = undefined;
var uniforms: struct {
	ambientLight: c_int,
	cloudColor: c_int,
	screenSize: c_int,
	skipDepthTests: c_int,
	@"fog.color": c_int,
	@"fog.density": c_int,
	@"fog.fogLower": c_int,
	@"fog.fogHigher": c_int,
} = undefined;
var depthUniforms: struct {
	ambientLight: c_int,
	cloudColor: c_int,
	screenSize: c_int,
	skipDepthTests: c_int,
} = undefined;
var cloudSsbo: graphics.SSBO = undefined;
var cubeVao: graphics.VertexArray = undefined;
var cloudDepthTexture: c_uint = undefined;
var cloudDepthFbo: c_uint = undefined;
var cloudDepthWidth: i32 = 0;
var cloudDepthHeight: i32 = 0;
var config: Config = .{};
var lastReloadNs: i96 = 0;
var lastDebugLogNs: i96 = 0;
var cloudTime: f64 = 0;

const DummyVertex = struct {
	pad: f32 = 0,
	pub const attributeDescriptions: []const c.VkVertexInputAttributeDescription = &.{};
};

pub fn init() void {
	const vertexPath = "assets/cubyz/shaders/clouds/clouds.vert";
	const fragmentPath = "assets/cubyz/shaders/clouds/clouds.frag";
	depthPipeline = graphics.Pipeline.init(
		vertexPath,
		fragmentPath,
		"",
		&depthUniforms,
		graphics.VertexArray.EmptyVertex,
		.{
			.rasterState = .{.cullMode = .none},
			.depthStencilState = .{.depthTest = true, .depthWrite = true},
			.blendState = .{.attachments = &.{.{
				.srcColorBlendFactor = .zero,
				.dstColorBlendFactor = .zero,
				.colorBlendOp = .add,
				.srcAlphaBlendFactor = .zero,
				.dstAlphaBlendFactor = .zero,
				.alphaBlendOp = .add,
				.colorWriteMask = .none,
			}}, .formats = &.{.world}},
		},
	);
	pipeline = graphics.Pipeline.init(
		vertexPath,
		fragmentPath,
		"#define COLOR_PASS\n",
		&uniforms,
		graphics.VertexArray.EmptyVertex,
		.{
			.rasterState = .{.cullMode = .none},
			.depthStencilState = .{.depthTest = false, .depthWrite = false},
			.blendState = .{.attachments = &.{.alphaBlending}, .formats = &.{.swapChain}},
		},
	);
	cloudSsbo = graphics.SSBO.initDynamicSize(GpuCloud, maxClouds);
	cubeVao = .init(DummyVertex, &.{.{}}, null);
	c.glGenTextures(1, &cloudDepthTexture);
	c.glBindTexture(c.GL_TEXTURE_2D, cloudDepthTexture);
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
	c.glGenFramebuffers(1, &cloudDepthFbo);
	loadConfig();
}

pub fn deinit() void {
	depthPipeline.deinit();
	pipeline.deinit();
	cloudSsbo.deinit();
	cubeVao.deinit();
	c.glDeleteFramebuffers(1, &cloudDepthFbo);
	c.glDeleteTextures(1, &cloudDepthTexture);
}

pub fn render(frustum: *const main.renderer.Frustum, playerPos: Vec3d, ambientLight: Vec3f, deltaTime: f64) void {
	maybeReloadConfig();
	if (main.game.world) |world| {
		if (!world.paused) {
			cloudTime += deltaTime;
		}
	}

	const lodExtent = @as(u32, settings.renderDistance)*chunk.chunkSize*(@as(u32, 1) << settings.highestLod);
	const renderRadius: f64 = @floatFromInt(lodExtent);
	const cellSize: f64 = @floatCast(@max(config.cellSize, 32));
	const windLength: f64 = @sqrt(@as(f64, @floatCast(config.windX*config.windX + config.windY*config.windY)));
	const windDirX: f64 = if (windLength > 0) @as(f64, @floatCast(config.windX))/windLength else 1;
	const windDirY: f64 = if (windLength > 0) @as(f64, @floatCast(config.windY))/windLength else 0;
	const drift = cloudTime*@as(f64, @floatCast(config.speed));
	const originX = playerPos[0] - windDirX*drift;
	const originY = playerPos[1] - windDirY*drift;

	var minCx: i32 = @intFromFloat(@floor((originX - renderRadius)/cellSize));
	var maxCx: i32 = @intFromFloat(@floor((originX + renderRadius)/cellSize));
	var minCy: i32 = @intFromFloat(@floor((originY - renderRadius)/cellSize));
	var maxCy: i32 = @intFromFloat(@floor((originY + renderRadius)/cellSize));
	if (maxCx - minCx > maxCellsPerAxis) {
		const mid = @divTrunc(minCx + maxCx, 2);
		minCx = mid - @divTrunc(maxCellsPerAxis, 2);
		maxCx = minCx + maxCellsPerAxis;
	}
	if (maxCy - minCy > maxCellsPerAxis) {
		const mid = @divTrunc(minCy + maxCy, 2);
		minCy = mid - @divTrunc(maxCellsPerAxis, 2);
		maxCy = minCy + maxCellsPerAxis;
	}

	var gpuClouds: main.ListManaged(GpuCloud) = .initCapacity(main.stackAllocator, maxClouds);
	defer gpuClouds.deinit();

	const radiusSq = renderRadius*renderRadius;
	var cy = minCy;
	while (cy <= maxCy) : (cy += 1) {
		var cx = minCx;
		while (cx <= maxCx) : (cx += 1) {
			if (gpuClouds.items.len >= maxClouds) break;
			appendCloudIfVisible(&gpuClouds, cx, cy, cellSize, drift, windDirX, windDirY, playerPos, frustum, radiusSq);
		}
	}

	if (gpuClouds.items.len == 0) return;

	c.glDepthRange(0, 1);
	c.glDepthMask(c.GL_TRUE);

	var viewport: [4]c_int = undefined;
	c.glGetIntegerv(c.GL_VIEWPORT, &viewport);
	var targetFbo: c_int = 0;
	c.glGetIntegerv(c.GL_FRAMEBUFFER_BINDING, &targetFbo);
	ensureCloudDepthBuffer(viewport[2], viewport[3]);
	main.renderer.bindWorldDepthTexture(c.GL_TEXTURE4);

	cloudSsbo.bufferSubData(GpuCloud, gpuClouds.items, gpuClouds.items.len);
	cloudSsbo.bind(ssboBinding);
	cubeVao.bind();
	const instanceCount: c_int = @intCast(gpuClouds.items.len);
	const skipDepthTests: c_int = if (config.debug != 0) 1 else 0;
	if (config.debug != 0) {
		const now = main.timestamp().toNanoseconds();
		if (now - lastDebugLogNs > 2_000_000_000) {
			lastDebugLogNs = now;
			std.log.info("Cloud debug: drawing {} clouds, viewport {}x{}, player {d:.1} {d:.1} {d:.1}", .{
				gpuClouds.items.len,
				viewport[2],
				viewport[3],
				playerPos[0],
				playerPos[1],
				playerPos[2],
			});
		}
	}

	c.glBindFramebuffer(c.GL_FRAMEBUFFER, cloudDepthFbo);
	c.glViewport(0, 0, viewport[2], viewport[3]);
	depthPipeline.bind(null);
	c.glClear(c.GL_DEPTH_BUFFER_BIT);
	c.glUniform3f(depthUniforms.ambientLight, ambientLight[0], ambientLight[1], ambientLight[2]);
	c.glUniform4f(depthUniforms.cloudColor, config.colorR, config.colorG, config.colorB, config.opacity);
	c.glUniform2f(depthUniforms.screenSize, @floatFromInt(viewport[2]), @floatFromInt(viewport[3]));
	c.glUniform1i(depthUniforms.skipDepthTests, skipDepthTests);
	c.glDrawArraysInstanced(c.GL_TRIANGLES, 0, cubeVertexCount, instanceCount);

	c.glBindFramebuffer(c.GL_FRAMEBUFFER, @intCast(targetFbo));
	c.glViewport(viewport[0], viewport[1], viewport[2], viewport[3]);
	c.glActiveTexture(c.GL_TEXTURE5);
	c.glBindTexture(c.GL_TEXTURE_2D, cloudDepthTexture);
	main.renderer.bindWorldDepthTexture(c.GL_TEXTURE4);
	pipeline.bind(null);
	c.glUniform3f(uniforms.ambientLight, ambientLight[0], ambientLight[1], ambientLight[2]);
	c.glUniform4f(uniforms.cloudColor, config.colorR, config.colorG, config.colorB, config.opacity);
	c.glUniform2f(uniforms.screenSize, @floatFromInt(viewport[2]), @floatFromInt(viewport[3]));
	c.glUniform1i(uniforms.skipDepthTests, skipDepthTests);
	const fog = if (main.game.world) |world| world.dayTime.fog else graphics.Fog{.fogColor = .{1, 1, 1}, .skyColor = .{1, 1, 1}, .density = 0, .fogLower = 0, .fogHigher = 1};
	c.glUniform3fv(uniforms.@"fog.color", 1, @ptrCast(&fog.fogColor));
	c.glUniform1f(uniforms.@"fog.density", fog.density);
	c.glUniform1f(uniforms.@"fog.fogLower", fog.fogLower);
	c.glUniform1f(uniforms.@"fog.fogHigher", fog.fogHigher);
	c.glDrawArraysInstanced(c.GL_TRIANGLES, 0, cubeVertexCount, instanceCount);
}

fn ensureCloudDepthBuffer(width: i32, height: i32) void {
	if (width == cloudDepthWidth and height == cloudDepthHeight) return;
	cloudDepthWidth = @max(width, 1);
	cloudDepthHeight = @max(height, 1);
	c.glBindTexture(c.GL_TEXTURE_2D, cloudDepthTexture);
	c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_DEPTH_COMPONENT32F, cloudDepthWidth, cloudDepthHeight, 0, c.GL_DEPTH_COMPONENT, c.GL_FLOAT, null);
	c.glBindFramebuffer(c.GL_FRAMEBUFFER, cloudDepthFbo);
	c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_TEXTURE_2D, cloudDepthTexture, 0);
	c.glDrawBuffer(c.GL_NONE);
	c.glReadBuffer(c.GL_NONE);
}

fn appendCloudIfVisible(
	gpuClouds: *main.ListManaged(GpuCloud),
	cx: i32,
	cy: i32,
	cellSize: f64,
	drift: f64,
	windDirX: f64,
	windDirY: f64,
	playerPos: Vec3d,
	frustum: *const main.renderer.Frustum,
	radiusSq: f64,
) void {
	var seed = random.initSeed2D(config.seed, Vec2i{cx, cy});
	if (random.nextFloat(&seed) >= config.density) return;

	const minSizeXy: f64 = @floatCast(@min(config.minSizeXy, config.maxSizeXy));
	const maxSizeXy: f64 = @floatCast(@max(config.minSizeXy, config.maxSizeXy));
	const minSizeZ: f64 = @floatCast(@min(config.minSizeZ, config.maxSizeZ));
	const maxSizeZ: f64 = @floatCast(@max(config.minSizeZ, config.maxSizeZ));
	const sizeX = @max(1, minSizeXy + (maxSizeXy - minSizeXy)*@as(f64, @floatCast(random.nextFloat(&seed))));
	const sizeY = @max(1, minSizeXy + (maxSizeXy - minSizeXy)*@as(f64, @floatCast(random.nextFloat(&seed))));
	const sizeZ = @max(1, minSizeZ + (maxSizeZ - minSizeZ)*@as(f64, @floatCast(random.nextFloat(&seed))));
	const slackX = cellSize - sizeX;
	const slackY = cellSize - sizeY;
	const offsetX = if (slackX > 0) @as(f64, @floatCast(random.nextFloat(&seed)))*slackX else slackX*0.5;
	const offsetY = if (slackY > 0) @as(f64, @floatCast(random.nextFloat(&seed)))*slackY else slackY*0.5;

	const minX = @as(f64, @floatFromInt(cx))*cellSize + offsetX + windDirX*drift;
	const minY = @as(f64, @floatFromInt(cy))*cellSize + offsetY + windDirY*drift;
	const minZ: f64 = @floatCast(config.height);
	const relMin = Vec3d{minX, minY, minZ} - playerPos;
	const size = Vec3d{sizeX, sizeY, sizeZ};
	const center = relMin + size*@as(Vec3d, @splat(0.5));
	if (vec.lengthSquare(center) > radiusSq) return;

	const relMinF: Vec3f = @floatCast(relMin);
	const sizeF: Vec3f = @floatCast(size);
	if (!frustum.testAAB(relMinF, sizeF)) return;

	gpuClouds.append(.{
		.min = .{relMinF[0], relMinF[1], relMinF[2], 0},
		.size = .{sizeF[0], sizeF[1], sizeF[2], 0},
	});
}

fn maybeReloadConfig() void {
	const now = main.timestamp().toNanoseconds();
	if (now - lastReloadNs < reloadInterval.toNanoseconds()) return;
	lastReloadNs = now;
	loadConfig();
}

fn loadConfig() void {
	const file = main.files.cwd().read(main.stackAllocator, configPath) catch |err| {
		if (err != error.FileNotFound) {
			std.log.err("Could not read {s}: {s}", .{configPath, @errorName(err)});
		}
		return;
	};
	defer main.stackAllocator.free(file);

	var parsed: Config = .{};
	var lines = std.mem.splitScalar(u8, file, '\n');
	while (lines.next()) |rawLine| {
		const line = std.mem.trim(u8, std.mem.trim(u8, rawLine, "\r"), " \t");
		if (line.len == 0 or line[0] == '#') continue;
		const eq = std.mem.indexOfScalar(u8, line, '=') orelse {
			std.log.err("Invalid line in {s}: {s}", .{configPath, line});
			continue;
		};
		const key = std.mem.trim(u8, line[0..eq], " \t");
		const value = std.mem.trim(u8, line[eq + 1 ..], " \t");
		assignConfigValue(&parsed, key, value);
	}
	clampConfig(&parsed);
	config = parsed;
}

fn assignConfigValue(parsed: *Config, key: []const u8, value: []const u8) void {
	if (std.mem.eql(u8, key, "seed")) {
		parsed.seed = std.fmt.parseInt(u64, value, 10) catch {
			std.log.err("Invalid seed in {s}: {s}", .{configPath, value});
			return;
		};
		return;
	}
	const number = std.fmt.parseFloat(f32, value) catch {
		std.log.err("Invalid number in {s} for {s}: {s}", .{configPath, key, value});
		return;
	};
	if (std.mem.eql(u8, key, "height")) {
		parsed.height = number;
	} else if (std.mem.eql(u8, key, "speed")) {
		parsed.speed = number;
	} else if (std.mem.eql(u8, key, "wind_x")) {
		parsed.windX = number;
	} else if (std.mem.eql(u8, key, "wind_y")) {
		parsed.windY = number;
	} else if (std.mem.eql(u8, key, "cell_size")) {
		parsed.cellSize = number;
	} else if (std.mem.eql(u8, key, "density")) {
		parsed.density = number;
	} else if (std.mem.eql(u8, key, "min_size_xy")) {
		parsed.minSizeXy = number;
	} else if (std.mem.eql(u8, key, "max_size_xy")) {
		parsed.maxSizeXy = number;
	} else if (std.mem.eql(u8, key, "min_size_z")) {
		parsed.minSizeZ = number;
	} else if (std.mem.eql(u8, key, "max_size_z")) {
		parsed.maxSizeZ = number;
	} else if (std.mem.eql(u8, key, "opacity")) {
		parsed.opacity = number;
	} else if (std.mem.eql(u8, key, "color_r")) {
		parsed.colorR = number;
	} else if (std.mem.eql(u8, key, "color_g")) {
		parsed.colorG = number;
	} else if (std.mem.eql(u8, key, "color_b")) {
		parsed.colorB = number;
	} else if (std.mem.eql(u8, key, "debug")) {
		parsed.debug = number;
	} else {
		std.log.err("Unknown cloud setting {s}", .{key});
	}
}

fn clampConfig(parsed: *Config) void {
	parsed.cellSize = @max(parsed.cellSize, 16);
	parsed.density = std.math.clamp(parsed.density, 0, 1);
	parsed.minSizeXy = @max(parsed.minSizeXy, 1);
	parsed.maxSizeXy = @max(parsed.maxSizeXy, 1);
	parsed.minSizeZ = @max(parsed.minSizeZ, 1);
	parsed.maxSizeZ = @max(parsed.maxSizeZ, 1);
	parsed.opacity = std.math.clamp(parsed.opacity, 0, 1);
	parsed.colorR = std.math.clamp(parsed.colorR, 0, 1);
	parsed.colorG = std.math.clamp(parsed.colorG, 0, 1);
	parsed.colorB = std.math.clamp(parsed.colorB, 0, 1);
	parsed.speed = @max(parsed.speed, 0);
}
