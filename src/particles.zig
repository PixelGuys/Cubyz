const std = @import("std");
const main = @import("main");
const graphics = @import("graphics.zig");
const SSBO = graphics.SSBO;
const TextureArray = graphics.TextureArray;
const Shader = graphics.Shader;
const Image = graphics.Image;
const game = @import("game.zig");
const ZonElement = @import("zon.zig").ZonElement;
const c = graphics.c;
const random = @import("random.zig");
const ColorRGB = graphics.ColorRGB;
const vec = @import("vec.zig");
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

var arena = main.heap.NeverFailingArenaAllocator.init(main.globalAllocator);
const allocator = arena.allocator();

pub const ParticleManager = struct {
	// so i will probably have to store all of the particles in a single texture array and just index in it??
	pub var particleTypesSSBO: ?SSBO = null; 
	pub var types: main.List(ParticleType) = undefined;
	var textureIDs: main.List([]const u8) = undefined;
	var textures: main.List(Image) = undefined;
	var emissionTextures: main.List(Image) = undefined;
	var arenaForWorld: main.heap.NeverFailingArenaAllocator = undefined;

	pub var textureArray: TextureArray = undefined;
	pub var emissionTextureArray: TextureArray = undefined;

	pub var particleTypeHashmap = std.StringHashMap(u16).init(allocator.allocator);
	
	// have a hashmap for particle types to create them easily
	pub fn init() void {
		types = .init(main.globalAllocator);
		textureIDs = .init(main.globalAllocator);
		textures = .init(main.globalAllocator);
		emissionTextures = .init(main.globalAllocator);
		arenaForWorld = .init(main.globalAllocator);
		textureArray = .init();
		emissionTextureArray = .init();
		ParticleSystem.init(EmmiterProperties{
			.gravity = .{0, 0, 20},
			.drag = 0.2,
			.sizeStart = 0.4,
			.sizeEnd = 0.02,
			.lifeTime = 10,
		});
	}

	pub fn deinit() void {
		types.deinit();
		textureIDs.deinit();
		textures.deinit();
		emissionTextures.deinit();
		arenaForWorld.deinit();
		textureArray.deinit();
		emissionTextureArray.deinit();
		ParticleSystem.deinit();
	}

	pub fn register(_: []const u8, id: []const u8, zon: ZonElement) u16 {
		std.log.debug("Registered particle: {s}", .{id});
		var particleType: ParticleType = undefined;

		particleType.isBlockTexture = zon.get(bool, "isBlockTexture", false);
		particleType.animationFrames = zon.get(u32, "animationFrames", 1);

		const textureId = zon.get([]const u8, "texture", "cubyz:spark");
		// std.log.debug("name: {s} id: {s}", .{textureName, id});
		var splitter = std.mem.splitScalar(u8, textureId, ':');
		const mod = splitter.first();
		const _id = splitter.rest();

		var buffer: [1024]u8 = undefined;
		// this is so confusing i just hardcoded that thing
		const path = std.fmt.bufPrint(&buffer, "assets/{s}/particles/textures/{s}.png", .{mod, _id}) catch unreachable;
		textureIDs.append(arenaForWorld.allocator().dupe(u8, path));
		readTextureData(path, &particleType);
		
		particleTypeHashmap.put(id, @intCast(types.items.len)) catch unreachable;
		types.append(particleType);
		return @intCast(types.items.len-1);
	}

	fn generateBlockParticleTypes() void {
		
	}

	fn readTextureData(_path: []const u8, typ: *ParticleType) void {
		const animationFrames = typ.animationFrames;
		const path = _path[0 .. _path.len - ".png".len];
		typ.startFrame = @intCast(textures.items.len);
		const base = readTextureFile(path, ".png", Image.defaultImage);
		const emission = readTextureFile(path, "_emission.png", Image.emptyImage);
		for(0..animationFrames) |i| {
			textures.append(extractAnimationSlice(base, i, animationFrames));
			emissionTextures.append(extractAnimationSlice(emission, i, animationFrames));
		}
	}

	fn extendedPath(_allocator: main.heap.NeverFailingAllocator, path: []const u8, ending: []const u8) []const u8 {
		return std.fmt.allocPrint(_allocator.allocator, "{s}{s}", .{path, ending}) catch unreachable;
	}

	fn readTextureFile(_path: []const u8, ending: []const u8, default: Image) Image {
		const path = extendedPath(main.stackAllocator, _path, ending);
		defer main.stackAllocator.free(path);
		return Image.readFromFile(arenaForWorld.allocator(), path) catch default;
	}

	fn extractAnimationSlice(image: Image, frame: usize, frames: usize) Image {
		if(image.height < frames) return image;
		var startHeight = image.height/frames*frame;
		if(image.height%frames > frame) startHeight += frame else startHeight += image.height%frames;
		var endHeight = image.height/frames*(frame + 1);
		if(image.height%frames > frame + 1) endHeight += frame + 1 else endHeight += image.height%frames;
		var result = image;
		result.height = @intCast(endHeight - startHeight);
		result.imageData = result.imageData[startHeight*image.width .. endHeight*image.width];
		return result;
	}

	pub fn generateTextureArray() void {
		std.log.debug("Particle texture sizes: {d} {d}", .{textures.items.len, emissionTextures.items.len});
		textureArray.generate(textures.items, true, true);
		c.glTexParameterf(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_MAX_ANISOTROPY, @floatFromInt(main.settings.anisotropicFiltering));
		emissionTextureArray.generate(emissionTextures.items, true, false);
		c.glTexParameterf(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_MAX_ANISOTROPY, @floatFromInt(main.settings.anisotropicFiltering));

		particleTypesSSBO = SSBO.initStatic(ParticleType, ParticleManager.types.items);
		particleTypesSSBO.?.bind(13);
	}

	pub fn update(deltaTime: f64) void {
		const dt: f32 = @floatCast(deltaTime);
		ParticleSystem.update(dt);
	}

	pub fn render(playerPosition: Vec3d, ambientLight: Vec3f) void {
		ParticleSystem.render(playerPosition, ambientLight);
	}
};

pub const ParticleSystem = struct {
	const maxCapacity: u32 = 65536;
	var particles: []Particle = undefined;
	var properties: EmmiterProperties = undefined;

	var particlesSSBO: SSBO = undefined;

	var shader: Shader = undefined;
	const UniformStruct = struct {
		projectionMatrix: c_int,
		viewMatrix: c_int,
		billboardMatrix: c_int,
		playerPositionInteger: c_int,
		playerPositionFraction: c_int,
		ambientLight: c_int,
	};
	var uniforms: UniformStruct = undefined;

	pub fn init(props: EmmiterProperties) void {
		std.log.debug("Particle alignment: {d} size: {d}\n", .{@alignOf(Particle), @sizeOf(Particle)});
		shader = Shader.initAndGetUniforms("assets/cubyz/shaders/particles/particles.vs", "assets/cubyz/shaders/particles/particles.fs", "", &uniforms);
		
		properties = props;
		particles = main.globalAllocator.alloc(Particle, maxCapacity);
		particlesSSBO = SSBO.init();
		particlesSSBO.createDynamicBuffer(maxCapacity*@sizeOf(Particle));
		particlesSSBO.bind(12);
	}

	pub fn deinit() void {
		shader.deinit();
		particlesSSBO.deinit();
		particles.len = maxCapacity;
		main.globalAllocator.free(particles);
	}

	pub fn update(deltaTime: f32) void {
		const vdt: Vec3f = @as(Vec3f, @splat(deltaTime));

		var i: u32 = 0;
		while(i < particles.len) {
			var particle = particles[i];
			particle.lifeLeft -= deltaTime;
			if(particle.lifeLeft < 0) {
				particles[i] = particles[particles.len - 1];
				particles.len -= 1;
				continue;
			}

			particle.vel += properties.gravity * vdt;
			particle.vel *= @as(Vec3f, @splat(std.math.pow(f32, properties.drag, deltaTime)));
			const vel = particle.vel * vdt;

			// TODO: OPTIMIZE THE HELL OUT OF THIS
			if (particle.collides) {
				const hitBox: game.collision.Box = .{.min = @splat(-0.5), .max = @splat(0.5)};
				particle.pos[0] += vel[0];
				if (game.collision.collides(.client, .x, -vel[0], particle.pos, hitBox)) |box| {
					if (vel[0] < 0) {
						particle.pos[0] = @floatCast(box.max[0] - hitBox.min[0]);
					} else {
						particle.pos[0] = @floatCast(box.min[0] - hitBox.max[0]);
					}
				}
				particle.pos[1] += vel[1];
				if (game.collision.collides(.client, .y, -vel[1], particle.pos, hitBox)) |box| {
					if (vel[1] < 0) {
						particle.pos[1] = @floatCast(box.max[1] - hitBox.min[1]);
					} else {
						particle.pos[1] = @floatCast(box.min[1] - hitBox.max[1]);
					}
				}
				particle.pos[2] += vel[2];
				if (game.collision.collides(.client, .z, -vel[2], particle.pos, hitBox)) |box| {
					if (vel[2] < 0) {
						particle.pos[2] = @floatCast(box.max[2] - hitBox.min[2]);
					} else {
						particle.pos[2] = @floatCast(box.min[2] - hitBox.max[2]);
					}
				}
			}

			const intPos: Vec3i = @intFromFloat(@floor(particle.pos));
			const light: [6]u8 = main.renderer.mesh_storage.getLight(intPos[0], intPos[1], intPos[2]) orelse @splat(0);
			var rawVals: [6]u5 = undefined;
			inline for(0..6) |j| {
				rawVals[j] = @intCast(light[j]>>3);
			}
			particle.light = (@as(u32, rawVals[0]) << 25 |
				@as(u32, rawVals[1]) << 20 |
				@as(u32, rawVals[2]) << 15 |
				@as(u32, rawVals[3]) << 10 |
				@as(u32, rawVals[4]) << 5 |
				@as(u32, rawVals[5]) << 0);
			
			// std.log.debug("x: {d} y: {d} z: {d}", .{particle.pos[0], particle.pos[1], particle.pos[2]});

			particles[i] = particle;
			i += 1; // makes things simplier
		}
	}

	pub fn addParticle(id: []const u8, pos: Vec3f) void {
		if (particles.len >= maxCapacity) {
			return;
		}
		const typ = ParticleManager.particleTypeHashmap.get(id) orelse 0;
		particles.len += 1;
		particles[particles.len-1] = Particle{
			.pos = pos,
			.vel = random.nextFloatVectorSigned(3, &main.seed)*@as(Vec3f, @splat(20)),
			.lifeTime = properties.lifeTime,
			.lifeLeft = properties.lifeTime,
			.typ = typ,
			.collides = true,
		};
	}

	pub fn render(playerPosition: Vec3d, ambientLight: Vec3f) void {
		particlesSSBO.bufferDataDynamic(Particle, particles);

		shader.bind();

		c.glActiveTexture(c.GL_TEXTURE0);
		ParticleManager.textureArray.bind();
		c.glActiveTexture(c.GL_TEXTURE1);
		ParticleManager.emissionTextureArray.bind();
		
		c.glUniformMatrix4fv(uniforms.projectionMatrix, 1, c.GL_TRUE, @ptrCast(&game.projectionMatrix));
		c.glUniform3fv(uniforms.ambientLight, 1, @ptrCast(&ambientLight));
		c.glUniformMatrix4fv(uniforms.viewMatrix, 1, c.GL_TRUE, @ptrCast(&game.camera.viewMatrix));

		const playerPos = playerPosition;
		c.glUniform3i(uniforms.playerPositionInteger, @intFromFloat(@floor(playerPos[0])), @intFromFloat(@floor(playerPos[1])), @intFromFloat(@floor(playerPos[2])));
		c.glUniform3f(uniforms.playerPositionFraction, @floatCast(@mod(playerPos[0], 1)), @floatCast(@mod(playerPos[1], 1)), @floatCast(@mod(playerPos[2], 1)));

		const billboardMatrix = Mat4f.rotationZ(-game.camera.rotation[2] + std.math.pi*0.5)
			.mul(Mat4f.rotationY(game.camera.rotation[0]-std.math.pi*0.5));
		c.glUniformMatrix4fv(uniforms.billboardMatrix, 1, c.GL_TRUE, @ptrCast(&billboardMatrix));

		// std.log.debug("count: {d}", .{particles.len});
		c.glDrawArrays(c.GL_TRIANGLES, 0, @intCast(particles.len*6));
	}

	pub fn getParticleCount() u32 {
		return @intCast(particles.len);
	}
};

pub const EmmiterProperties = struct {
	gravity: Vec3f = @splat(0),
	// colorStart: Vec3f = @splat(0),
	// colorEnd: Vec3f = @splat(0),
	drag: f32 = 0,
	rotVelMin: f32 = 0,
	rotVelMax: f32 = 0,
	velMin: f32 = 0,
	velMax: f32 = 0,
	
	lifeTime: f32 = 0,
	sizeStart: f32 = 0,
	sizeEnd: f32 = 0,

	texture: graphics.TextureArray = undefined,
};

// so ig we need to create a particle type for each block type
pub const ParticleType = struct {
	texture: u32,
	animationFrames: u32,
	startFrame: u32,
	isBlockTexture: bool,
};

// needs more thinking about the data needed here, im not sure how to use block textures for when you are breaking blocks
// TODO?: separate the data which is sent to the gpu into another struct
pub const Particle = struct {
	pos: Vec3f,
	vel: Vec3f,
	lifeTime: f32,
	lifeLeft: f32,
	// used for identifying the particle animation things
	typ: u32, 
	// anotherTyp: u16 = 0,
	light: u32 = 0,
	collides: bool,
	// uv: u16 = 0,
	// 15 bytes left for use due to alignment
};