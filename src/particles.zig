const std = @import("std");
const main = @import("main");
const chunk_meshing = @import("renderer/chunk_meshing.zig");
const graphics = @import("graphics.zig");
const SSBO = graphics.SSBO;
const TextureArray = graphics.TextureArray;
const Shader = graphics.Shader;
const Image = graphics.Image;
const game = @import("game.zig");
const ZonElement = @import("zon.zig").ZonElement;
const c = graphics.c;
const random = @import("random.zig");
const vec = @import("vec.zig");
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const Vec3i = vec.Vec3i;

var arena = main.heap.NeverFailingArenaAllocator.init(main.globalAllocator);
const arenaAllocator = arena.allocator();

pub const ParticleManager = struct {
	var particleTypesSSBO: SSBO = undefined;
	var types: main.List(ParticleType) = undefined;
	var textureIDs: main.List([]const u8) = undefined;
	var textures: main.List(Image) = undefined;
	var emissionTextures: main.List(Image) = undefined;

	var textureArray: TextureArray = undefined;
	var emissionTextureArray: TextureArray = undefined;

	const ParticleIndex = u16;
	var particleTypeHashmap: std.StringHashMapUnmanaged(ParticleIndex) = undefined;

	pub fn init() void {
		types = .init(main.globalAllocator);
		textureIDs = .init(main.globalAllocator);
		textures = .init(main.globalAllocator);
		emissionTextures = .init(main.globalAllocator);
		textureArray = .init();
		emissionTextureArray = .init();
		ParticleSystem.init();
	}

	pub fn deinit() void {
		types.deinit();
		textureIDs.deinit();
		textures.deinit();
		emissionTextures.deinit();
		textureArray.deinit();
		emissionTextureArray.deinit();
		particleTypeHashmap.deinit(arenaAllocator.allocator);
		ParticleSystem.deinit();
		arena.deinit();
	}

	pub fn register(_: []const u8, id: []const u8, zon: ZonElement) void {
		const animationFrames = zon.get(u32, "animationFrames", 1);

		const textureId = zon.get([]const u8, "texture", "cubyz:spark");
		var splitter = std.mem.splitScalar(u8, textureId, ':');
		const mod = splitter.first();
		const _id = splitter.rest();

		// this is so confusing i just hardcoded that thing
		const path = std.fmt.allocPrint(main.stackAllocator.allocator, "assets/{s}/particles/textures/{s}.png", .{ mod, _id }) catch unreachable;
		defer main.stackAllocator.free(path);
		textureIDs.append(arenaAllocator.dupe(u8, path));
		const particleType = readTextureDataAndParticleType(path, animationFrames);

		particleTypeHashmap.put(arenaAllocator.allocator, id, @intCast(types.items.len)) catch unreachable;
		types.append(particleType);

		std.log.debug("Registered particle type: {s}", .{id});
	}

	fn readTextureDataAndParticleType(_path: []const u8, animationFrames: u32) ParticleType {
		const path = _path[0 .. _path.len - ".png".len];
		var typ: ParticleType = undefined;

		const base = readTextureFile(path, ".png", Image.defaultImage);
		const emission = readTextureFile(path, "_emission.png", Image.emptyImage);
		typ.startFrame = @intCast(textures.items.len);
		typ.size = @as(f32, @floatFromInt(base.width))/16;
		for(0..animationFrames) |i| {
			textures.append(extractAnimationSlice(base, i, animationFrames));
			emissionTextures.append(extractAnimationSlice(emission, i, animationFrames));
		}
		
		typ.animationFrames = animationFrames;
		return typ;
	}

	fn extendedPath(_allocator: main.heap.NeverFailingAllocator, path: []const u8, ending: []const u8) []const u8 {
		return std.mem.concat(_allocator.allocator, u8, &.{ path, ending }) catch unreachable;
	}

	fn readTextureFile(_path: []const u8, ending: []const u8, default: Image) Image {
		const path = extendedPath(main.stackAllocator, _path, ending);
		defer main.stackAllocator.free(path);
		return Image.readFromFile(arenaAllocator, path) catch default;
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
		textureArray.generate(textures.items, true, true);
		c.glTexParameterf(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_MAX_ANISOTROPY, @floatFromInt(main.settings.anisotropicFiltering));
		emissionTextureArray.generate(emissionTextures.items, true, false);
		c.glTexParameterf(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_MAX_ANISOTROPY, @floatFromInt(main.settings.anisotropicFiltering));

		particleTypesSSBO = SSBO.initStatic(ParticleType, ParticleManager.types.items);
		particleTypesSSBO.bind(14);
	}

	pub fn update(deltaTime: f64) void {
		const dt: f32 = @floatCast(deltaTime);
		ParticleSystem.update(dt);
	}

	pub fn render(projectionMatrix: Mat4f, viewMatrix: Mat4f, playerPosition: Vec3d, ambientLight: Vec3f) void {
		ParticleSystem.render(projectionMatrix, viewMatrix, playerPosition, ambientLight);
	}
};

pub const ParticleSystem = struct {
	pub const maxCapacity: u32 = 4194304;
	var particleCount: u32 = 0;
	var particles: [maxCapacity]Particle = undefined;
	var particlesLocal: [maxCapacity]ParticleLocal = undefined;
	var properties: EmmiterProperties = undefined;
	var seed: u64 = undefined;

	var particlesSSBO: SSBO = undefined;

	var shader: Shader = undefined;
	const UniformStruct = struct {
		projectionAndViewMatrix: c_int,
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
			.gravity = .{0, 0, 2},
			.drag = 0.5,
			.lifeTimeMin = 1,
			.lifeTimeMax = 1,
			.velMin = 2,
			.velMax = 2,
			.rotVelMin = std.math.pi*0.2,
			.rotVelMax = std.math.pi*0.6,
		};
		particlesSSBO = SSBO.init();
		particlesSSBO.createDynamicBuffer(Particle, maxCapacity);
		particlesSSBO.bind(13);

		seed = @bitCast(@as(i64, @truncate(std.time.nanoTimestamp())));
	}

	pub fn deinit() void {
		shader.deinit();
		particlesSSBO.deinit();
	}

	pub fn update(deltaTime: f32) void {
		const vecDeltaTime: Vec4f = @as(Vec4f, @splat(deltaTime));

		var i: u32 = 0;
		while(i < particleCount) {
			var particle = particles[i];
			var particleLocal = particlesLocal[i];
			particle.lifeRatio -= particleLocal.lifeVelocity*deltaTime;
			if(particle.lifeRatio < 0) {
				particleCount -= 1;
				particles[i] = particles[particleCount];
				particlesLocal[i] = particlesLocal[particleCount];
				continue;
			}

			var rot = particle.posAndRotation[3];
			const rotVel = particleLocal.velAndRotationVel[3];
			rot += rotVel*deltaTime;

			particleLocal.velAndRotationVel += vec.combine(properties.gravity, 0)*vecDeltaTime;
			particleLocal.velAndRotationVel *= @splat(@max(0, 1 - properties.drag*deltaTime));
			const vel = particleLocal.velAndRotationVel*vecDeltaTime;

			// TODO: OPTIMIZE THE HELL OUT OF THIS
			if(particleLocal.collides) {
				const size = ParticleManager.types.items[particle.typ].size;
				const hitBox: game.collision.Box = .{.min = @splat(size*-0.5), .max = @splat(size*0.5)};
				var v3Pos = Vec3f{particle.posAndRotation[0], particle.posAndRotation[1], particle.posAndRotation[2]};
				v3Pos[0] += vel[0];
				if(game.collision.collides(.client, .x, -vel[0], v3Pos, hitBox)) |box| {
					if(vel[0] < 0) {
						v3Pos[0] = @floatCast(box.max[0] - hitBox.min[0]);
					} else {
						v3Pos[0] = @floatCast(box.min[0] - hitBox.max[0]);
					}
				}
				v3Pos[1] += vel[1];
				if(game.collision.collides(.client, .y, -vel[1], v3Pos, hitBox)) |box| {
					if(vel[1] < 0) {
						v3Pos[1] = @floatCast(box.max[1] - hitBox.min[1]);
					} else {
						v3Pos[1] = @floatCast(box.min[1] - hitBox.max[1]);
					}
				}
				v3Pos[2] += vel[2];
				if(game.collision.collides(.client, .z, -vel[2], v3Pos, hitBox)) |box| {
					if(vel[2] < 0) {
						v3Pos[2] = @floatCast(box.max[2] - hitBox.min[2]);
					} else {
						v3Pos[2] = @floatCast(box.min[2] - hitBox.max[2]);
					}
				}
				particle.posAndRotation = vec.combine(v3Pos, 0);
			} else {
				particle.posAndRotation += vel;
			}

			particle.posAndRotation[3] = rot;
			particleLocal.velAndRotationVel[3] = rotVel;

			// TODO: optimize
			const intPos: vec.Vec4i = @intFromFloat(@floor(particle.posAndRotation));
			const light: [6]u8 = main.renderer.mesh_storage.getLight(intPos[0], intPos[1], intPos[2]) orelse @splat(0);
			const compressedLight = (@as(u32, light[0] >> 3) << 25 |
				@as(u32, light[1] >> 3) << 20 |
				@as(u32, light[2] >> 3) << 15 |
				@as(u32, light[3] >> 3) << 10 |
				@as(u32, light[4] >> 3) << 5 |
				@as(u32, light[5] >> 3));
			particle.light = compressedLight;

			particles[i] = particle;
			particlesLocal[i] = particleLocal;
			i += 1;
		}
	}

	pub fn spawn(id: []const u8, count: u32, pos: Vec3f, collides: bool, shape: EmmiterShape) void {
		const typ = ParticleManager.particleTypeHashmap.get(id) orelse 0;

		const to: u32 = @intCast(@min(particleCount + count, maxCapacity));
		for(particleCount..to) |_| {
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

			particles[particleCount] = Particle{
				.posAndRotation = vec.combine(particlePos, 0),
				.typ = typ,
			};
			particlesLocal[particleCount] = ParticleLocal{
				.velAndRotationVel = vec.combine(vel, properties.rotVelMin + random.nextFloatSigned(&seed)*properties.rotVelMax),
				.lifeVelocity = 1/lifeTime,
				.collides = collides,
			};
			particleCount += 1;
		}
	}

	pub fn render(projectionMatrix: Mat4f, viewMatrix: Mat4f, playerPosition: Vec3d, ambientLight: Vec3f) void {
		particlesSSBO.bufferSubData(Particle, &particles, particleCount);

		shader.bind();

		c.glUniform1i(uniforms.textureSampler, 0);
		c.glUniform1i(uniforms.emissionTextureSampler, 1);

		const projectionAndViewMatrix = Mat4f.mul(projectionMatrix, viewMatrix);
		c.glUniformMatrix4fv(uniforms.projectionAndViewMatrix, 1, c.GL_TRUE, @ptrCast(&projectionAndViewMatrix));
		c.glUniform3fv(uniforms.ambientLight, 1, @ptrCast(&ambientLight));

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

		c.glBindVertexArray(chunk_meshing.vao);

		for (0..std.math.divCeil(u32, particleCount, chunk_meshing.maxQuadsInIndexBuffer) catch unreachable) |_| {
			c.glDrawElements(c.GL_TRIANGLES, @intCast(particleCount*4), c.GL_UNSIGNED_INT, null);
		}
	}

	pub fn getParticleCount() u32 {
		return particleCount;
	}
};

pub const EmmiterProperties = struct {
	gravity: Vec3f = @splat(0),
	drag: f32 = 0,
	velMin: f32 = 0,
	velMax: f32 = 0,
	rotVelMin: f32 = 0,
	rotVelMax: f32 = 0,
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
	animationFrames: u32,
	startFrame: u32,
	size: f32,
};

pub const Particle = struct {
	posAndRotation: Vec4f,
	lifeRatio: f32 = 1,
	light: u32 = 0,
	typ: u32,
};

pub const ParticleLocal = struct {
	velAndRotationVel: Vec4f,
	lifeVelocity: f32,
	collides: bool,
};
