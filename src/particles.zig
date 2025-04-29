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
	pub var particleTypesSSBO: ?SSBO = null;
	pub var types: main.List(ParticleType) = undefined;
	var textureIDs: main.List([]const u8) = undefined;
	var textures: main.List(Image) = undefined;
	var emissionTextures: main.List(Image) = undefined;
	var arenaForWorld: main.heap.NeverFailingArenaAllocator = undefined;

	pub var textureArray: TextureArray = undefined;
	pub var emissionTextureArray: TextureArray = undefined;

	pub var particleTypeHashmap = std.StringHashMap(u16).init(allocator.allocator);

	pub fn init() void {
		types = .init(main.globalAllocator);
		textureIDs = .init(main.globalAllocator);
		textures = .init(main.globalAllocator);
		emissionTextures = .init(main.globalAllocator);
		arenaForWorld = .init(main.globalAllocator);
		textureArray = .init();
		emissionTextureArray = .init();
		ParticleSystem.init();
	}

	pub fn deinit() void {
		types.deinit();
		textureIDs.deinit();
		textures.deinit();
		emissionTextures.deinit();
		arenaForWorld.deinit();
		textureArray.deinit();
		emissionTextureArray.deinit();
		particleTypeHashmap.deinit();
		ParticleSystem.deinit();
	}

	pub fn register(_: []const u8, id: []const u8, zon: ZonElement) u16 {
		std.log.debug("Registered particle: {s}", .{id});
		var particleType: ParticleType = undefined;

		particleType.isBlockTexture = zon.get(bool, "isBlockTexture", false);
		particleType.animationFrames = zon.get(u32, "animationFrames", 1);

		const textureId = zon.get([]const u8, "texture", "cubyz:spark");
		var splitter = std.mem.splitScalar(u8, textureId, ':');
		const mod = splitter.first();
		const _id = splitter.rest();

		// this is so confusing i just hardcoded that thing
		const path = std.fmt.allocPrint(main.stackAllocator.allocator, "assets/{s}/particles/textures/{s}.png", .{mod, _id}) catch unreachable;
		defer main.stackAllocator.free(path);
		textureIDs.append(arenaForWorld.allocator().dupe(u8, path));
		readTextureData(path, &particleType);

		particleTypeHashmap.put(id, @intCast(types.items.len)) catch unreachable;
		types.append(particleType);
		return @intCast(types.items.len - 1);
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
		particleTypesSSBO.?.bind(14);
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
	pub const maxCapacity: u32 = 65536;
	var particles: []Particle = undefined;
	var properties: EmmiterProperties = undefined;
	var seed: u64 = undefined;

	var particlesSSBO: SSBO = undefined;

	var shader: Shader = undefined;
	const UniformStruct = struct {
		projectionMatrix: c_int,
		viewMatrix: c_int,
		billboardMatrix: c_int,
		playerPositionInteger: c_int,
		playerPositionFraction: c_int,
		ambientLight: c_int,
		textureSampler: c_int,
		emissionTextureSampler: c_int,
	};
	var uniforms: UniformStruct = undefined;

	pub fn init() void {
		std.log.debug("Particle alignment: {d} size: {d}\n", .{@alignOf(Particle), @sizeOf(Particle)});
		shader = Shader.initAndGetUniforms("assets/cubyz/shaders/particles/particles.vs", "assets/cubyz/shaders/particles/particles.fs", "", &uniforms);

		properties = EmmiterProperties{
			.gravity = .{0, 0, 4},
			.drag = 2,
			.lifeTimeMin = 5,
			.lifeTimeMax = 5,
			.velMin = 5,
			.velMax = 10,
		};
		particles = main.globalAllocator.alloc(Particle, maxCapacity);
		particlesSSBO = SSBO.init();
		particlesSSBO.createDynamicBuffer(maxCapacity*@sizeOf(Particle));
		particlesSSBO.bind(13);

		seed = @bitCast(@as(i64, @truncate(std.time.nanoTimestamp())));
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

			particle.vel += properties.gravity*vdt;
			particle.vel *= @splat(@max(0, 1 - properties.drag*deltaTime));
			const vel = particle.vel*vdt;

			// TODO: OPTIMIZE THE HELL OUT OF THIS
			if(particle.collides) {
				const hitBox: game.collision.Box = .{.min = @splat(particle.size*-0.5), .max = @splat(particle.size*0.5)};
				particle.pos[0] += vel[0];
				if(game.collision.collides(.client, .x, -vel[0], particle.pos, hitBox)) |box| {
					if(vel[0] < 0) {
						particle.pos[0] = @floatCast(box.max[0] - hitBox.min[0]);
					} else {
						particle.pos[0] = @floatCast(box.min[0] - hitBox.max[0]);
					}
				}
				particle.pos[1] += vel[1];
				if(game.collision.collides(.client, .y, -vel[1], particle.pos, hitBox)) |box| {
					if(vel[1] < 0) {
						particle.pos[1] = @floatCast(box.max[1] - hitBox.min[1]);
					} else {
						particle.pos[1] = @floatCast(box.min[1] - hitBox.max[1]);
					}
				}
				particle.pos[2] += vel[2];
				if(game.collision.collides(.client, .z, -vel[2], particle.pos, hitBox)) |box| {
					if(vel[2] < 0) {
						particle.pos[2] = @floatCast(box.max[2] - hitBox.min[2]);
					} else {
						particle.pos[2] = @floatCast(box.min[2] - hitBox.max[2]);
					}
				}
			} else {
				particle.pos += vel;
			}

			// TODO: optimize
			const intPos: Vec3i = @intFromFloat(@floor(particle.pos));
			const light: [6]u8 = main.renderer.mesh_storage.getLight(intPos[0], intPos[1], intPos[2]) orelse @splat(0);
			particle.light = (@as(u32, light[0] >> 3) << 25 |
				@as(u32, light[1] >> 3) << 20 |
				@as(u32, light[2] >> 3) << 15 |
				@as(u32, light[3] >> 3) << 10 |
				@as(u32, light[4] >> 3) << 5 |
				@as(u32, light[5] >> 3));

			particles[i] = particle;
			i += 1;
		}
	}

	pub fn spawn(id: []const u8, count: u32, pos: Vec3f, size: f32, collides: bool, shape: EmmiterShape) void {
		const typ = ParticleManager.particleTypeHashmap.get(id) orelse 0;

		const to: u32 = @intCast(@min(particles.len + count, maxCapacity));
		for(particles.len..to) |_| {
			var vel: Vec3f = @splat(0);
			var particlePos: Vec3f = @splat(0);

			switch(shape.shapeType) {
				.point => {
					particlePos = pos;
					const speed: Vec3f = @splat(properties.velMin + random.nextFloat(&seed)*properties.velMax);
					const dir: Vec3f = switch(shape.directionMode) {
						.direction => shape.dir,
						.scatter => vec.normalize(random.nextFloatVectorSigned(3, &seed)),
						.spread => vec.normalize(random.nextFloatVectorSigned(3, &seed)),
					};
					vel = dir*speed;
				},
				.sphere => {
					// this has a non uniform way of distribution, not sure how to fix that
					const spawnPos: Vec3f = @splat(random.nextFloat(&seed)*shape.size);
					const offsetPos: Vec3f = vec.normalize(random.nextFloatVectorSigned(3, &seed));
					particlePos = pos + offsetPos*spawnPos;
					const speed: Vec3f = @splat(properties.velMin + random.nextFloat(&seed)*properties.velMax);
					const dir: Vec3f = switch(shape.directionMode) {
						.direction => shape.dir,
						.scatter => vec.normalize(random.nextFloatVectorSigned(3, &seed)),
						.spread => offsetPos,
					};
					vel = dir*speed;
				},
				.cube => {
					const spawnPos: Vec3f = @splat(random.nextFloat(&seed)*shape.size);
					const offsetPos: Vec3f = random.nextFloatVectorSigned(3, &seed);
					particlePos = pos + offsetPos*spawnPos;
					const speed: Vec3f = @splat(properties.velMin + random.nextFloat(&seed)*properties.velMax);
					const dir: Vec3f = switch(shape.directionMode) {
						.direction => shape.dir,
						.scatter => vec.normalize(random.nextFloatVectorSigned(3, &seed)),
						.spread => vec.normalize(offsetPos),
					};
					vel = dir*speed;
				},
			}

			const lifeTime = properties.lifeTimeMin + random.nextFloat(&seed)*properties.lifeTimeMax;

			particles.len += 1;
			particles[particles.len - 1] = Particle{
				.pos = particlePos,
				.vel = vel,
				.lifeTime = lifeTime,
				.lifeLeft = lifeTime,
				.typ = typ,
				.size = size,
				.collides = collides,
			};
		}
	}

	pub fn render(playerPosition: Vec3d, ambientLight: Vec3f) void {
		particlesSSBO.bufferDataDynamic(Particle, particles);

		shader.bind();

		c.glUniform1i(uniforms.textureSampler, 0);
		c.glUniform1i(uniforms.emissionTextureSampler, 1);

		c.glUniformMatrix4fv(uniforms.projectionMatrix, 1, c.GL_TRUE, @ptrCast(&game.projectionMatrix));
		c.glUniform3fv(uniforms.ambientLight, 1, @ptrCast(&ambientLight));
		c.glUniformMatrix4fv(uniforms.viewMatrix, 1, c.GL_TRUE, @ptrCast(&game.camera.viewMatrix));

		const playerPos = playerPosition;
		c.glUniform3i(uniforms.playerPositionInteger, @intFromFloat(@floor(playerPos[0])), @intFromFloat(@floor(playerPos[1])), @intFromFloat(@floor(playerPos[2])));
		c.glUniform3f(uniforms.playerPositionFraction, @floatCast(@mod(playerPos[0], 1)), @floatCast(@mod(playerPos[1], 1)), @floatCast(@mod(playerPos[2], 1)));

		const billboardMatrix = Mat4f.rotationZ(-game.camera.rotation[2] + std.math.pi*0.5)
			.mul(Mat4f.rotationY(game.camera.rotation[0] - std.math.pi*0.5));
		c.glUniformMatrix4fv(uniforms.billboardMatrix, 1, c.GL_TRUE, @ptrCast(&billboardMatrix));

		c.glActiveTexture(c.GL_TEXTURE0);
		ParticleManager.textureArray.bind();
		c.glActiveTexture(c.GL_TEXTURE1);
		ParticleManager.emissionTextureArray.bind();

		c.glDrawArrays(c.GL_TRIANGLES, 0, @intCast(particles.len*6));
	}

	pub fn getParticleCount() u32 {
		return @intCast(particles.len);
	}
};

pub const EmmiterProperties = struct {
	gravity: Vec3f = @splat(0),
	drag: f32 = 0,
	velMin: f32 = 0,
	velMax: f32 = 0,
	lifeTimeMin: f32 = 0,
	lifeTimeMax: f32 = 0,
};

pub const EmmiterShapeEnum = enum(u8) {
	point,
	sphere,
	cube,
};
pub const DirectionModeEnum = enum(u8) {
	spread,
	scatter,
	direction,
};

pub const EmmiterShape = struct {
	shapeType: EmmiterShapeEnum = .point,
	directionMode: DirectionModeEnum = .spread,
	size: f32 = 0,
	dir: Vec3f = @splat(0),
};

pub const ParticleType = struct {
	texture: u32,
	animationFrames: u32,
	startFrame: u32,
	isBlockTexture: bool,
};

// TODO?: separate the data which is sent to the gpu into another struct
pub const Particle = struct {
	pos: Vec3f,
	vel: Vec3f,
	lifeTime: f32,
	lifeLeft: f32,
	typ: u32,
	light: u32 = 0,
	size: f32,
	collides: bool,
	// 15 bytes left for use due to alignment
};
