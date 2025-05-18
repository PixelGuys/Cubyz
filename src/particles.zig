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
const Vec4d = vec.Vec4d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const Vec3i = vec.Vec3i;

var arena = main.heap.NeverFailingArenaAllocator.init(main.globalAllocator);
const arenaAllocator = arena.allocator();

pub const ParticleManager = struct {
	var particleTypesSSBO: SSBO = undefined;
	var types: main.List(ParticleType) = undefined;
	var textures: main.List(Image) = undefined;
	var emissionTextures: main.List(Image) = undefined;

	var textureArray: TextureArray = undefined;
	var emissionTextureArray: TextureArray = undefined;

	const ParticleIndex = u16;
	var particleTypeHashmap: std.StringHashMapUnmanaged(ParticleIndex) = undefined;

	pub fn init() void {
		types = .init(arenaAllocator);
		textures = .init(arenaAllocator);
		emissionTextures = .init(arenaAllocator);
		textureArray = .init();
		emissionTextureArray = .init();
		ParticleSystem.init();
	}

	pub fn deinit() void {
		types.deinit();
		textures.deinit();
		emissionTextures.deinit();
		textureArray.deinit();
		emissionTextureArray.deinit();
		particleTypeHashmap.deinit(arenaAllocator.allocator);
		ParticleSystem.deinit();
		arena.deinit();
	}

	pub fn register(assetsFolder: []const u8, id: []const u8, zon: ZonElement) void {
		const animationFrames = zon.get(u32, "animationFrames", 1);
		const textureId = zon.get([]const u8, "texture", "cubyz:spark");

		const particleType = readTextureDataAndParticleType(assetsFolder, textureId, animationFrames);

		particleTypeHashmap.put(arenaAllocator.allocator, id, @intCast(types.items.len)) catch unreachable;
		types.append(particleType);

		std.log.debug("Registered particle type: {s}", .{id});
	}
	fn readTextureDataAndParticleType(assetsFolder: []const u8, textureId: []const u8, animationFrames: u32) ParticleType {
		var typ: ParticleType = undefined;

		const base = readTexture(assetsFolder, textureId, ".png", Image.defaultImage, .isMandatory);
		const emission = readTexture(assetsFolder, textureId, "_emission.png", Image.emptyImage, .isOptional);

		typ.startFrame = @floatFromInt(textures.items.len);
		typ.size = @as(f32, @floatFromInt(base.width))/16;
		for(0..animationFrames) |i| {
			textures.append(extractAnimationSlice(base, i, animationFrames, textureId, .base));

			const emmisionSlice = if(emission.imageData.ptr != Image.emptyImage.imageData.ptr)
				extractAnimationSlice(emission, i, animationFrames, textureId, .emmision)
			else
				Image.emptyImage;
			emissionTextures.append(emmisionSlice);
		}

		typ.animationFrames = @floatFromInt(animationFrames);
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

		return graphics.Image.readFromFile(arenaAllocator, worldAssetsPath) catch graphics.Image.readFromFile(arenaAllocator, gameAssetsPath) catch {
			if(status == .isMandatory) std.log.err("Particle texture not found in {s} and {s}.", .{worldAssetsPath, gameAssetsPath});
			return default;
		};
	}

	fn extractAnimationSlice(image: Image, frame: usize, frames: usize, imageName: []const u8, textureType: enum {base, emmision}) Image {
		if(image.height%frames != 0) {
			std.log.err("Particle texture size is not divisible by its frame count for {s} in {s} texture", .{imageName, @tagName(textureType)});
			return Image.defaultImage;
		}
		const frameHeight = image.height/frames;
		const startHeight = frameHeight*frame;
		const endHeight = frameHeight*(frame + 1);
		var result = image;
		result.height = @intCast(frameHeight);
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
};

pub const ParticleSystem = struct {
	pub const maxCapacity: u32 = 524288;
	var particleCount: u32 = 0;
	var particles: [maxCapacity]Particle = undefined;
	var particlesLocal: [maxCapacity]ParticleLocal = undefined;
	// TODO: add different emitters for different types of movements like windy, normal, no collisions and etc.
	var properties: EmitterProperties = undefined;
	var seed: u64 = undefined;
	var previousPlayerPos: Vec3d = undefined;

	var particlesSSBO: SSBO = undefined;

	var pipeline: graphics.Pipeline = undefined;
	const UniformStruct = struct {
		projectionAndViewMatrix: c_int,
		billboardMatrix: c_int,
		ambientLight: c_int,
	};
	var uniforms: UniformStruct = undefined;

	pub fn init() void {
		std.log.debug("Particle alignment: {d} size: {d}\n", .{@alignOf(Particle), @sizeOf(Particle)});
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
			.drag = 0.5,
			.lifeTimeMin = 5,
			.lifeTimeMax = 5,
			.velMin = 0.1,
			.velMax = 0.3,
			.rotVelMin = std.math.pi*0.2,
			.rotVelMax = std.math.pi*0.6,
		};
		particlesSSBO = SSBO.init();
		particlesSSBO.createDynamicBuffer(Particle, maxCapacity);
		particlesSSBO.bind(13);

		seed = @bitCast(@as(i64, @truncate(std.time.nanoTimestamp())));
	}

	pub fn deinit() void {
		pipeline.deinit();
		particlesSSBO.deinit();
	}

	pub fn update(deltaTime: f32) void {
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

			var rot = particle.posAndRotation[3];
			const rotVel = particleLocal.velAndRotationVel[3];
			rot += rotVel*deltaTime;

			particleLocal.velAndRotationVel += vec.combine(properties.gravity, 0)*vecDeltaTime;
			particleLocal.velAndRotationVel *= @splat(@max(0, 1 - properties.drag*deltaTime));
			const posDelta = particleLocal.velAndRotationVel*vecDeltaTime;

			// TODO: OPTIMIZE THE HELL OUT OF THIS
			if(particleLocal.collides) {
				const size = ParticleManager.types.items[particle.typ].size;
				const hitBox: game.collision.Box = .{.min = @splat(size*-0.5), .max = @splat(size*0.5)};
				var v3Pos = playerPos + @as(Vec3d, @floatCast(Vec3f{particle.posAndRotation[0], particle.posAndRotation[1], particle.posAndRotation[2]} + prevPlayerPosDifference));
				v3Pos[0] += posDelta[0];
				if(game.collision.collides(.client, .x, -posDelta[0], v3Pos, hitBox)) |box| {
					if(posDelta[0] < 0) {
						v3Pos[0] = box.max[0] - hitBox.min[0];
					} else {
						v3Pos[0] = box.min[0] - hitBox.max[0];
					}
				}
				v3Pos[1] += posDelta[1];
				if(game.collision.collides(.client, .y, -posDelta[1], v3Pos, hitBox)) |box| {
					if(posDelta[1] < 0) {
						v3Pos[1] = box.max[1] - hitBox.min[1];
					} else {
						v3Pos[1] = box.min[1] - hitBox.max[1];
					}
				}
				v3Pos[2] += posDelta[2];
				if(game.collision.collides(.client, .z, -posDelta[2], v3Pos, hitBox)) |box| {
					if(posDelta[2] < 0) {
						v3Pos[2] = box.max[2] - hitBox.min[2];
					} else {
						v3Pos[2] = box.min[2] - hitBox.max[2];
					}
				}
				particle.posAndRotation = vec.combine(@as(Vec3f, @floatCast(v3Pos - playerPos)), 0);
			} else {
				particle.posAndRotation += posDelta + vec.combine(prevPlayerPosDifference, 0);
			}

			particle.posAndRotation[3] = rot;
			particleLocal.velAndRotationVel[3] = rotVel;

			// TODO: optimize
			const positionf64 = @as(Vec4d, @floatCast(particle.posAndRotation)) + Vec4d{playerPos[0], playerPos[1], playerPos[2], 0};
			const intPos: vec.Vec4i = @intFromFloat(@floor(positionf64));
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

	pub fn addParticle(typ: u32, pos: Vec3d, vel: Vec3f, collides: bool) void {
		const lifeTime = properties.lifeTimeMin + random.nextFloat(&seed)*properties.lifeTimeMax;

		particles[particleCount] = Particle{
			.posAndRotation = vec.combine(@as(Vec3f, @floatCast(pos - previousPlayerPos)), 0),
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

		for(0..std.math.divCeil(u32, particleCount, chunk_meshing.maxQuadsInIndexBuffer) catch unreachable) |_| {
			c.glDrawElements(c.GL_TRIANGLES, @intCast(particleCount*4), c.GL_UNSIGNED_INT, null);
		}
	}

	pub fn getParticleCount() u32 {
		return particleCount;
	}
};

pub const EmitterProperties = struct {
	// TODO: move gravity and drag into particle type, and other things into spawn logic which would allow for more flexibility
	gravity: Vec3f = @splat(0),
	drag: f32 = 0,
	velMin: f32 = 0,
	velMax: f32 = 0,
	rotVelMin: f32 = 0,
	rotVelMax: f32 = 0,
	lifeTimeMin: f32 = 0,
	lifeTimeMax: f32 = 0,
};

pub const EmitterShapeEnum = enum(u8) {
	point,
	sphere,
	cube,
};
pub const DirectionModeEnum = enum(u8) {
	spread,
	scatter,
	direction,
};

pub const Emitter = struct {
	shapeType: EmitterShapeEnum,
	directionMode: DirectionModeEnum = .spread,
	count: u32,
	size: f32 = 0,
	dir: Vec3f = @splat(0),
	id: []const u8,
	collides: bool,

	pub fn spawn(self: Emitter, pos: Vec3d,) void {
		const typ = ParticleManager.particleTypeHashmap.get(self.id) orelse 0;
		const properties = ParticleSystem.properties;

		const to: u32 = @intCast(@min(ParticleSystem.particleCount + self.count, ParticleSystem.maxCapacity));
		for(ParticleSystem.particleCount..to) |_| {
			var particleVel: Vec3f = @splat(0);
			var particlePos: Vec3d = @splat(0);

			switch(self.shapeType) {
				.point => {
					particlePos = pos;
					const speed: Vec3f = @splat(properties.velMin + random.nextFloat(&ParticleSystem.seed)*properties.velMax);
					const dir: Vec3f = switch(self.directionMode) {
						.direction => self.dir,
						.scatter => vec.normalize(random.nextFloatVectorSigned(3, &ParticleSystem.seed)),
						.spread => vec.normalize(random.nextFloatVectorSigned(3, &ParticleSystem.seed)),
					};
					particleVel = dir*speed;
				},
				.sphere => {
					// this has a non uniform way of distribution, not sure how to fix that
					const spawnPos: Vec3d = @splat(random.nextDouble(&ParticleSystem.seed)*self.size);
					const offsetPos: Vec3d = vec.normalize(random.nextDoubleVectorSigned(3, &ParticleSystem.seed));
					particlePos = pos + offsetPos*spawnPos;
					const speed: Vec3f = @splat(properties.velMin + random.nextFloat(&ParticleSystem.seed)*properties.velMax);
					const dir: Vec3f = switch(self.directionMode) {
						.direction => self.dir,
						.scatter => vec.normalize(random.nextFloatVectorSigned(3, &ParticleSystem.seed)),
						.spread => @floatCast(offsetPos),
					};
					particleVel = dir*speed;
				},
				.cube => {
					const spawnPos: Vec3d = @splat(random.nextDouble(&ParticleSystem.seed)*self.size);
					const offsetPos: Vec3d = random.nextDoubleVectorSigned(3, &ParticleSystem.seed);
					particlePos = pos + offsetPos*spawnPos;
					const speed: Vec3f = @splat(properties.velMin + random.nextFloat(&ParticleSystem.seed)*properties.velMax);
					const dir: Vec3f = switch(self.directionMode) {
						.direction => self.dir,
						.scatter => vec.normalize(random.nextFloatVectorSigned(3, &ParticleSystem.seed)),
						.spread => vec.normalize(@as(Vec3f, @floatCast(offsetPos))),
					};
					particleVel = dir*speed;
				},
			}
			
			ParticleSystem.addParticle(typ, particlePos, particleVel, self.collides);
		}
	}
};

pub const ParticleType = struct {
	animationFrames: f32,
	startFrame: f32,
	size: f32,
};

pub const Particle = struct {
	posAndRotation: Vec4f,
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
