const std = @import("std");

const main = @import("main");
const chunk_meshing = @import("renderer/chunk_meshing.zig");
const graphics = @import("graphics.zig");
const SSBO = graphics.SSBO;
const TextureArray = graphics.TextureArray;
const Shader = graphics.Shader;
const Image = graphics.Image;
const c = graphics.c;
const game = @import("game.zig");
const ZonElement = @import("zon.zig").ZonElement;
const random = @import("random.zig");
const vec = @import("vec.zig");
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec4d = vec.Vec4d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const Vec3i = vec.Vec3i;

var seed: u64 = undefined;

pub const ParticleManager = struct {
	var particleTypesSSBO: SSBO = undefined;
	var types: main.ListUnmanaged(ParticleType) = .{};
	var textures: main.ListUnmanaged(Image) = .{};
	var emissionTextures: main.ListUnmanaged(Image) = .{};

	var textureArray: TextureArray = undefined;
	var emissionTextureArray: TextureArray = undefined;

	const ParticleIndex = u16;
	var particleTypeHashmap: std.StringHashMapUnmanaged(ParticleIndex) = .{};

	pub fn init() void {
		textureArray = .init();
		emissionTextureArray = .init();
		particleTypesSSBO = SSBO.init();
		ParticleSystem.init();
	}

	pub fn deinit() void {
		textureArray.deinit();
		emissionTextureArray.deinit();
		ParticleSystem.deinit();
		particleTypesSSBO.deinit();
	}

	pub fn reset() void {
		types = .{};
		textures = .{};
		emissionTextures = .{};
		particleTypeHashmap = .{};
		ParticleSystem.reset();
	}

	pub fn register(assetsFolder: []const u8, id: []const u8, zon: ZonElement) void {
		const textureId = zon.get(?[]const u8, "texture", null) orelse {
			std.log.err("Particle texture id was not specified for {s} ({s})", .{id, assetsFolder});
			return;
		};

		const particleType = readTextureDataAndParticleType(assetsFolder, textureId);

		particleTypeHashmap.put(main.worldArena.allocator, id, @intCast(types.items.len)) catch unreachable;
		types.append(main.worldArena, particleType);

		std.log.debug("Registered particle type: {s}", .{id});
	}
	fn readTextureDataAndParticleType(assetsFolder: []const u8, textureId: []const u8) ParticleType {
		var typ: ParticleType = undefined;

		const base = readTexture(assetsFolder, textureId, ".png", Image.defaultImage, .isMandatory);
		const emission = readTexture(assetsFolder, textureId, "_emission.png", Image.emptyImage, .isOptional);
		const hasEmission = (emission.imageData.ptr != Image.emptyImage.imageData.ptr);
		const baseAnimationFrameCount = base.height/base.width;
		const emissionAnimationFrameCount = emission.height/emission.width;

		typ.frameCount = @floatFromInt(baseAnimationFrameCount);
		typ.startFrame = @floatFromInt(textures.items.len);
		typ.size = @as(f32, @floatFromInt(base.width))/16;

		var isBaseBroken = false;
		var isEmissionBroken = false;

		if(base.height%base.width != 0) {
			std.log.err("Particle base texture has incorrect dimensions ({}x{}) expected height to be multiple of width for {s} ({s})", .{base.width, base.height, textureId, assetsFolder});
			isBaseBroken = true;
		}
		if(hasEmission and emission.height%emission.width != 0) {
			std.log.err("Particle emission texture has incorrect dimensions ({}x{}) expected height to be multiple of width for {s} ({s})", .{base.width, base.height, textureId, assetsFolder});
			isEmissionBroken = true;
		}
		if(hasEmission and baseAnimationFrameCount != emissionAnimationFrameCount) {
			std.log.err("Particle base texture and emission texture frame count mismatch ({} vs {}) for {s} ({s})", .{baseAnimationFrameCount, emissionAnimationFrameCount, textureId, assetsFolder});
			isEmissionBroken = true;
		}

		createAnimationFrames(&textures, baseAnimationFrameCount, base, isBaseBroken);
		createAnimationFrames(&emissionTextures, baseAnimationFrameCount, emission, isBaseBroken or isEmissionBroken or !hasEmission);

		return typ;
	}

	fn readTexture(assetsFolder: []const u8, textureId: []const u8, suffix: []const u8, default: graphics.Image, status: enum {isOptional, isMandatory}) graphics.Image {
		var splitter = std.mem.splitScalar(u8, textureId, ':');
		const mod = splitter.first();
		const id = splitter.rest();

		const gameAssetsPath = std.fmt.allocPrint(main.stackAllocator.allocator, "assets/{s}/particles/textures/{s}{s}", .{mod, id, suffix}) catch unreachable;
		defer main.stackAllocator.free(gameAssetsPath);

		const worldAssetsPath = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/{s}/particles/textures/{s}{s}", .{assetsFolder, mod, id, suffix}) catch unreachable;
		defer main.stackAllocator.free(worldAssetsPath);

		return graphics.Image.readFromFile(main.worldArena, worldAssetsPath) catch graphics.Image.readFromFile(main.worldArena, gameAssetsPath) catch {
			if(status == .isMandatory) std.log.err("Particle texture not found in {s} and {s}.", .{worldAssetsPath, gameAssetsPath});
			return default;
		};
	}

	fn createAnimationFrames(container: *main.ListUnmanaged(Image), frameCount: usize, image: Image, isBroken: bool) void {
		for(0..frameCount) |i| {
			container.append(main.worldArena, if(isBroken) image else extractAnimationSlice(image, i));
		}
	}

	fn extractAnimationSlice(image: Image, frameIndex: usize) Image {
		const frameCount = image.height/image.width;
		const frameHeight = image.height/frameCount;
		const startHeight = frameHeight*frameIndex;
		const endHeight = frameHeight*(frameIndex + 1);
		var result = image;
		result.height = @intCast(frameHeight);
		result.imageData = result.imageData[startHeight*image.width .. endHeight*image.width];
		return result;
	}

	pub fn generateTextureArray() void {
		textureArray.generate(textures.items, true, true);
		emissionTextureArray.generate(emissionTextures.items, true, false);

		particleTypesSSBO.bufferData(ParticleType, ParticleManager.types.items);
		particleTypesSSBO.bind(14);
	}
};

pub const ParticleSystem = struct {
	pub const maxCapacity: u32 = 524288;
	var particleCount: u32 = 0;
	var particles: [maxCapacity]Particle = undefined;
	var particlesLocal: [maxCapacity]ParticleLocal = undefined;
	var properties: EmitterProperties = undefined;
	var previousPlayerPos: Vec3d = undefined;

	var mutex: std.Thread.Mutex = .{};
	var networkCreationQueue: main.ListUnmanaged(struct {emitter: Emitter, pos: Vec3d, count: u32}) = .{};

	var particlesSSBO: SSBO = undefined;

	var pipeline: graphics.Pipeline = undefined;
	const UniformStruct = struct {
		projectionAndViewMatrix: c_int,
		billboardMatrix: c_int,
		ambientLight: c_int,
	};
	var uniforms: UniformStruct = undefined;

	fn init() void {
		pipeline = graphics.Pipeline.init(
			"assets/cubyz/shaders/particles/particles.vert",
			"assets/cubyz/shaders/particles/particles.frag",
			"",
			&uniforms,
			.{},
			.{.depthTest = true, .depthWrite = true},
			.{.attachments = &.{.noBlending}},
		);

		properties = EmitterProperties{
			.gravity = .{0, 0, -2},
			.drag = 0.2,
			.lifeTimeMin = 10,
			.lifeTimeMax = 10,
			.velMin = 0.1,
			.velMax = 0.3,
			.rotVelMin = std.math.pi*0.2,
			.rotVelMax = std.math.pi*0.6,
			.randomizeRotationOnSpawn = true,
		};
		particlesSSBO = SSBO.init();
		particlesSSBO.createDynamicBuffer(Particle, maxCapacity);
		particlesSSBO.bind(13);

		seed = @bitCast(@as(i64, @truncate(std.time.nanoTimestamp())));
	}

	fn deinit() void {
		pipeline.deinit();
		particlesSSBO.deinit();
	}

	fn reset() void {
		networkCreationQueue = .{};
	}

	pub fn update(deltaTime: f32) void {
		mutex.lock();
		if(networkCreationQueue.items.len != 0) {
			for(networkCreationQueue.items) |creation| {
				creation.emitter.spawnParticles(creation.count, Emitter.SpawnPoint, .{
					.mode = .spread,
					.position = creation.pos,
				});
			}
			networkCreationQueue.clearRetainingCapacity();
		}
		mutex.unlock();

		const vecDeltaTime: Vec4f = @as(Vec4f, @splat(deltaTime));
		const playerPos = game.Player.getEyePosBlocking();
		const prevPlayerPosDifference: Vec3f = @floatCast(previousPlayerPos - playerPos);

		var i: u32 = 0;
		while(i < particleCount) {
			const particle = &particles[i];
			const particleLocal = &particlesLocal[i];
			particle.lifeRatio -= particleLocal.lifeVelocity*deltaTime;
			if(particle.lifeRatio < 0) {
				particleCount -= 1;
				particles[i] = particles[particleCount];
				particlesLocal[i] = particlesLocal[particleCount];
				continue;
			}

			var pos: Vec3f = particle.pos;
			var rot = particle.rot;
			const rotVel = particleLocal.velAndRotationVel[3];
			rot += rotVel*deltaTime;

			particleLocal.velAndRotationVel += vec.combine(properties.gravity, 0)*vecDeltaTime;
			particleLocal.velAndRotationVel *= @splat(@exp(-properties.drag*deltaTime));
			const posDelta = particleLocal.velAndRotationVel*vecDeltaTime;

			if(particleLocal.collides) {
				const size = ParticleManager.types.items[particle.typ].size;
				const hitBox: game.collision.Box = .{.min = @splat(size*-0.5), .max = @splat(size*0.5)};
				var v3Pos = playerPos + @as(Vec3d, @floatCast(pos + prevPlayerPosDifference));
				v3Pos[0] += posDelta[0];
				if(game.collision.collides(.client, .x, -posDelta[0], v3Pos, hitBox)) |box| {
					v3Pos[0] = if(posDelta[0] < 0)
						box.max[0] - hitBox.min[0]
					else
						box.min[0] - hitBox.max[0];
				}
				v3Pos[1] += posDelta[1];
				if(game.collision.collides(.client, .y, -posDelta[1], v3Pos, hitBox)) |box| {
					v3Pos[1] = if(posDelta[1] < 0)
						box.max[1] - hitBox.min[1]
					else
						box.min[1] - hitBox.max[1];
				}
				v3Pos[2] += posDelta[2];
				if(game.collision.collides(.client, .z, -posDelta[2], v3Pos, hitBox)) |box| {
					v3Pos[2] = if(posDelta[2] < 0)
						box.max[2] - hitBox.min[2]
					else
						box.min[2] - hitBox.max[2];
				}
				pos = @as(Vec3f, @floatCast(v3Pos - playerPos));
			} else {
				pos += Vec3f{posDelta[0], posDelta[1], posDelta[2]} + prevPlayerPosDifference;
			}

			particle.pos = pos;
			particle.rot = rot;
			particleLocal.velAndRotationVel[3] = rotVel;

			const positionf64 = @as(Vec3d, @floatCast(pos)) + playerPos;
			const intPos: vec.Vec3i = @intFromFloat(@floor(positionf64));
			const light: [6]u8 = main.renderer.mesh_storage.getLight(intPos[0], intPos[1], intPos[2]) orelse @splat(0);
			const compressedLight =
				@as(u32, light[0] >> 3) << 25 |
				@as(u32, light[1] >> 3) << 20 |
				@as(u32, light[2] >> 3) << 15 |
				@as(u32, light[3] >> 3) << 10 |
				@as(u32, light[4] >> 3) << 5 |
				@as(u32, light[5] >> 3);
			particle.light = compressedLight;

			i += 1;
		}
		previousPlayerPos = playerPos;
	}

	fn addParticle(typ: u32, pos: Vec3d, vel: Vec3f, collides: bool) void {
		const lifeTime = properties.lifeTimeMin + random.nextFloat(&seed)*properties.lifeTimeMax;
		const rot = if(properties.randomizeRotationOnSpawn) random.nextFloat(&seed)*std.math.pi*2 else 0;

		particles[particleCount] = Particle{
			.pos = @as(Vec3f, @floatCast(pos - previousPlayerPos)),
			.rot = rot,
			.typ = typ,
		};
		particlesLocal[particleCount] = ParticleLocal{
			.velAndRotationVel = vec.combine(vel, properties.rotVelMin + random.nextFloatSigned(&seed)*properties.rotVelMax),
			.lifeVelocity = 1/lifeTime,
			.collides = collides,
		};
		particleCount += 1;
	}

	pub fn render(projectionMatrix: Mat4f, viewMatrix: Mat4f, ambientLight: Vec3f) void {
		particlesSSBO.bufferSubData(Particle, &particles, particleCount);

		pipeline.bind(null);

		const projectionAndViewMatrix = Mat4f.mul(projectionMatrix, viewMatrix);
		c.glUniformMatrix4fv(uniforms.projectionAndViewMatrix, 1, c.GL_TRUE, @ptrCast(&projectionAndViewMatrix));
		c.glUniform3fv(uniforms.ambientLight, 1, @ptrCast(&ambientLight));

		const billboardMatrix = Mat4f.rotationZ(-game.camera.rotation[2] + std.math.pi*0.5)
			.mul(Mat4f.rotationY(game.camera.rotation[0] - std.math.pi*0.5));
		c.glUniformMatrix4fv(uniforms.billboardMatrix, 1, c.GL_TRUE, @ptrCast(&billboardMatrix));

		c.glActiveTexture(c.GL_TEXTURE0);
		ParticleManager.textureArray.bind();
		c.glActiveTexture(c.GL_TEXTURE1);
		ParticleManager.emissionTextureArray.bind();

		c.glBindVertexArray(chunk_meshing.vao);

		const maxQuads = chunk_meshing.maxQuadsInIndexBuffer;
		const count = std.math.divCeil(u32, particleCount, maxQuads) catch unreachable;
		for(0..count) |i| {
			const particleOffset = (maxQuads*4)*i;
			const particleCurrentCount: u32 = @min(maxQuads, particleCount - maxQuads*i);
			c.glDrawElementsBaseVertex(c.GL_TRIANGLES, @intCast(particleCurrentCount*6), c.GL_UNSIGNED_INT, null, @intCast(particleOffset));
		}
	}

	pub fn getParticleCount() u32 {
		return particleCount;
	}

	pub fn addParticlesFromNetwork(emitter: Emitter, pos: Vec3d, count: u32) void {
		mutex.lock();
		defer mutex.unlock();
		networkCreationQueue.append(main.worldArena, .{.emitter = emitter, .pos = pos, .count = count});
	}
};

pub const EmitterProperties = struct {
	gravity: Vec3f = @splat(0),
	drag: f32 = 0,
	velMin: f32 = 0,
	velMax: f32 = 0,
	rotVelMin: f32 = 0,
	rotVelMax: f32 = 0,
	lifeTimeMin: f32 = 0,
	lifeTimeMax: f32 = 0,
	randomizeRotationOnSpawn: bool = false,
};

pub const DirectionMode = union(enum(u8)) {
	// The particle goes in the direction away from the center
	spread: void,
	// The particle goes in a random direction
	scatter: void,
	// The particle goes in the specified direction
	direction: Vec3f,
};

pub const Emitter = struct {
	typ: u16 = 0,
	collides: bool,

	pub const SpawnPoint = struct {
		mode: DirectionMode,
		position: Vec3d,

		pub fn spawn(self: SpawnPoint) struct {Vec3d, Vec3f} {
			const particlePos = self.position;
			const speed: Vec3f = @splat(ParticleSystem.properties.velMin + random.nextFloat(&seed)*ParticleSystem.properties.velMax);
			const dir: Vec3f = switch(self.mode) {
				.direction => |dir| dir,
				.scatter, .spread => vec.normalize(random.nextFloatVectorSigned(3, &seed)),
			};
			const particleVel = dir*speed;

			return .{particlePos, particleVel};
		}
	};

	pub const SpawnSphere = struct {
		radius: f32,
		mode: DirectionMode,
		position: Vec3d,

		pub fn spawn(self: SpawnSphere) struct {Vec3d, Vec3f} {
			const spawnPos: Vec3f = @splat(self.radius);
			var offsetPos: Vec3f = undefined;
			while(true) {
				offsetPos = random.nextFloatVectorSigned(3, &seed);
				if(vec.lengthSquare(offsetPos) <= 1) break;
			}
			const particlePos = self.position + @as(Vec3d, @floatCast(offsetPos*spawnPos));
			const speed: Vec3f = @splat(ParticleSystem.properties.velMin + random.nextFloat(&seed)*ParticleSystem.properties.velMax);
			const dir: Vec3f = switch(self.mode) {
				.direction => |dir| dir,
				.scatter => vec.normalize(random.nextFloatVectorSigned(3, &seed)),
				.spread => @floatCast(offsetPos),
			};
			const particleVel = dir*speed;

			return .{particlePos, particleVel};
		}
	};

	pub const SpawnCube = struct {
		size: Vec3f,
		mode: DirectionMode,
		position: Vec3d,

		pub fn spawn(self: SpawnCube) struct {Vec3d, Vec3f} {
			const spawnPos: Vec3f = self.size;
			const offsetPos: Vec3f = random.nextFloatVectorSigned(3, &seed);
			const particlePos = self.position + @as(Vec3d, @floatCast(offsetPos*spawnPos));
			const speed: Vec3f = @splat(ParticleSystem.properties.velMin + random.nextFloat(&seed)*ParticleSystem.properties.velMax);
			const dir: Vec3f = switch(self.mode) {
				.direction => |dir| dir,
				.scatter => vec.normalize(random.nextFloatVectorSigned(3, &seed)),
				.spread => vec.normalize(@as(Vec3f, @floatCast(offsetPos))),
			};
			const particleVel = dir*speed;

			return .{particlePos, particleVel};
		}
	};

	pub fn init(id: []const u8, collides: bool) Emitter {
		const emitter = Emitter{
			.typ = ParticleManager.particleTypeHashmap.get(id) orelse 0,
			.collides = collides,
		};

		return emitter;
	}

	pub fn spawnParticles(self: Emitter, spawnCount: u32, comptime T: type, spawnRules: T) void {
		const count = @min(spawnCount, ParticleSystem.maxCapacity - ParticleSystem.particleCount);
		for(0..count) |_| {
			const particlePos, const particleVel = spawnRules.spawn();

			ParticleSystem.addParticle(self.typ, particlePos, particleVel, self.collides);
		}
	}
};

pub const ParticleType = struct {
	frameCount: f32,
	startFrame: f32,
	size: f32,
};

pub const Particle = extern struct {
	pos: [3]f32 align(16),
	rot: f32 = 0,
	lifeRatio: f32 = 1,
	light: u32 = 0,
	typ: u32,
	// 4 bytes left for use
};

pub const ParticleLocal = struct {
	velAndRotationVel: Vec4f,
	lifeVelocity: f32,
	collides: bool,
};
