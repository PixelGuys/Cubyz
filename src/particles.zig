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
const Vec2f = vec.Vec2f;

var seed: u64 = undefined;

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
	var particleTypeHashmap: std.StringHashMapUnmanaged(ParticleIndex) = .{};

	pub fn init() void {
		types = .init(arenaAllocator);
		textures = .init(arenaAllocator);
		emissionTextures = .init(arenaAllocator);
		textureArray = .init();
		emissionTextureArray = .init();
		particleTypesSSBO = SSBO.init();
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
		particleTypesSSBO.deinit();
		arena.deinit();
	}

	pub fn register(assetsFolder: []const u8, id: []const u8, zon: ZonElement) void {
		const textureId = zon.get(?[]const u8, "texture", null) orelse {
			std.log.err("Particle texture id was not specified for {s} ({s})", .{id, assetsFolder});
			return;
		};

		const particleType = readTextureDataAndParticleType(assetsFolder, textureId);

		particleTypeHashmap.put(arenaAllocator.allocator, id, @intCast(types.items.len)) catch unreachable;
		types.append(particleType);

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

		return graphics.Image.readFromFile(arenaAllocator, worldAssetsPath) catch graphics.Image.readFromFile(arenaAllocator, gameAssetsPath) catch {
			if(status == .isMandatory) std.log.err("Particle texture not found in {s} and {s}.", .{worldAssetsPath, gameAssetsPath});
			return default;
		};
	}

	fn createAnimationFrames(container: *main.List(Image), frameCount: usize, image: Image, isBroken: bool) void {
		for(0..frameCount) |i| {
			container.append(if(isBroken) image else extractAnimationSlice(image, i));
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
	var previousPlayerPos: Vec3d = undefined;

	var mutex: std.Thread.Mutex = .{};
	var networkCreationQueue: main.List(struct {emitter: Emitter, pos: Vec3d, count: u32}) = undefined;

	var particlesSSBO: SSBO = undefined;

	var pipeline: graphics.Pipeline = undefined;
	const UniformStruct = struct {
		projectionAndViewMatrix: c_int,
		billboardMatrix: c_int,
		ambientLight: c_int,
		particleOffset: c_int,
	};
	var uniforms: UniformStruct = undefined;

	const gravity: Vec3f = .{0, 0, -9.8};

	pub fn init() void {
		pipeline = graphics.Pipeline.init(
			"assets/cubyz/shaders/particles/particles.vert",
			"assets/cubyz/shaders/particles/particles.frag",
			"",
			&uniforms,
			.{},
			.{.depthTest = true, .depthWrite = true},
			.{.attachments = &.{.noBlending}},
		);

		particlesSSBO = SSBO.init();
		particlesSSBO.createDynamicBuffer(Particle, maxCapacity);
		particlesSSBO.bind(13);

		seed = @bitCast(@as(i64, @truncate(std.time.nanoTimestamp())));

		networkCreationQueue = .init(arenaAllocator);
	}

	pub fn deinit() void {
		pipeline.deinit();
		particlesSSBO.deinit();
		networkCreationQueue.deinit();
	}

	pub fn update(deltaTime: f32) void {
		mutex.lock();
		if(networkCreationQueue.items.len != 0) {
			for(networkCreationQueue.items) |creation| {
				creation.emitter.spawnParticles(creation.pos, creation.count);
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

			var posAndRotation = particle.posAndRotationVec();
			const prevPos = Vec3d{posAndRotation[0], posAndRotation[1], posAndRotation[2]};
			var rot = posAndRotation[3];
			const rotVel = particleLocal.velAndRotationVel[3];
			rot += rotVel*deltaTime;

			particleLocal.velAndRotationVel += @as(Vec4f, @splat(particleLocal.density))*vec.combine(gravity, 0)*vecDeltaTime;
			particleLocal.velAndRotationVel *= @splat(@exp(-particleLocal.drag*deltaTime));
			const posDelta = particleLocal.velAndRotationVel*vecDeltaTime;

			if(particleLocal.collides) {
				const size = ParticleManager.types.items[particle.typ].size;
				const hitBox: game.collision.Box = .{.min = @splat(size*-0.5), .max = @splat(size*0.5)};
				var v3Pos = playerPos + @as(Vec3d, @floatCast(Vec3f{posAndRotation[0], posAndRotation[1], posAndRotation[2]} + prevPlayerPosDifference));
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
				posAndRotation = vec.combine(@as(Vec3f, @floatCast(v3Pos - playerPos)), 0);
			} else {
				posAndRotation += posDelta + vec.combine(prevPlayerPosDifference, 0);
			}

			particle.posAndRotation = posAndRotation;
			particle.posAndRotation[3] = rot;
			particleLocal.velAndRotationVel[3] = rotVel;

			const newPos = Vec3d{posAndRotation[0], posAndRotation[1], posAndRotation[2]};
			if(@reduce(.Or, @floor(prevPos) != @floor(newPos))) {
				const worldPos = @as(Vec3d, @floatCast(newPos)) + playerPos;
				particle.light = getCompressedLight(worldPos);
			}
			i += 1;
		}
		previousPlayerPos = playerPos;
	}

	fn getCompressedLight(worldPos: Vec3d) u32 {
		const intPos: vec.Vec3i = @intFromFloat(@floor(worldPos));
		const light: [6]u8 = main.renderer.mesh_storage.getLight(intPos[0], intPos[1], intPos[2]) orelse @splat(0);
		const compressedLight =
			@as(u32, light[0] >> 3) << 25 |
			@as(u32, light[1] >> 3) << 20 |
			@as(u32, light[2] >> 3) << 15 |
			@as(u32, light[3] >> 3) << 10 |
			@as(u32, light[4] >> 3) << 5 |
			@as(u32, light[5] >> 3);

		return compressedLight;
	}

	fn addParticle(typ: u32, pos: Vec3d, vel: Vec3f, collides: bool, properties: EmitterProperties) void {
		const lifeTime = properties.lifeTimeMin + (properties.lifeTimeMax - properties.lifeTimeMin)*random.nextFloat(&seed);
		const drag = properties.dragMin + (properties.dragMax - properties.dragMin)*random.nextFloat(&seed);
		const density = properties.densityMin + (properties.densityMax - properties.densityMin)*random.nextFloat(&seed);
		const rot = if(properties.randomizeRotation) random.nextFloat(&seed)*std.math.pi*2 else 0;
		const rotVel = (properties.rotVelMin + (properties.rotVelMax - properties.rotVelMin)*random.nextFloatSigned(&seed))*(std.math.pi/180.0);
		const color = properties.colorMin + (properties.colorMax - properties.colorMin)*if(properties.randomColorPerChannel)
			random.nextFloatVector(3, &seed)
		else
			@as(Vec3f, @splat(random.nextFloat(&seed)));
		const colorInt: @Vector(3, u5) = @intFromFloat(color*@as(Vec3f, @splat(31)));

		particles[particleCount] = Particle{
			.posAndRotation = vec.combine(@as(Vec3f, @floatCast(pos - previousPlayerPos)), rot),
			.typ = typ,
			.light = getCompressedLight(pos),
			.color = @as(u16, colorInt[0]) << 10 |
				@as(u16, colorInt[1]) << 5 |
				@as(u16, colorInt[2]),
		};
		particlesLocal[particleCount] = ParticleLocal{
			.velAndRotationVel = vec.combine(vel, rotVel),
			.lifeVelocity = 1/lifeTime,
			.density = density,
			.drag = drag,
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
			const particleOffset = maxQuads*i;
			const particleCurrentCount: u32 = @min(maxQuads, particleCount - maxQuads*i);
			c.glUniform1ui(uniforms.particleOffset, @intCast(particleOffset));
			c.glDrawElements(c.GL_TRIANGLES, @intCast(particleCurrentCount*6), c.GL_UNSIGNED_INT, null);
		}
	}

	pub fn getParticleCount() u32 {
		return particleCount;
	}

	pub fn addParticlesFromNetwork(emitter: Emitter, pos: Vec3d, count: u32) void {
		mutex.lock();
		defer mutex.unlock();
		networkCreationQueue.append(.{.emitter = emitter, .pos = pos, .count = count});
	}
};

pub const EmitterProperties = struct {
	dragMin: f32 = 0.1,
	dragMax: f32 = 0.2,
	densityMin: f32 = 0.1,
	densityMax: f32 = 0.2,
	velMin: f32 = 1,
	velMax: f32 = 1.5,
	rotVelMin: f32 = 20,
	rotVelMax: f32 = 60,
	lifeTimeMin: f32 = 0.75,
	lifeTimeMax: f32 = 1,
	colorMin: Vec3f = .{1, 1, 1},
	colorMax: Vec3f = .{1, 1, 1},
	randomizeRotation: bool = true,
	randomColorPerChannel: bool = false,

	pub fn parse(zon: ZonElement) EmitterProperties {
		const drag = zon.get(Vec2f, "drag", .{0.1, 0.2});
		const density = zon.get(Vec2f, "density", .{0.1, 0.2});
		const velocity = zon.get(Vec2f, "velocity", .{1, 1.5});
		const rotVel = zon.get(Vec2f, "rotationVel", .{20, 60});
		const lifeTime = zon.get(Vec2f, "lifeTime", .{0.75, 1});
		const color = zon.get(@Vector(2, u24), "color", .{std.math.maxInt(u24), std.math.maxInt(u24)});
		const randomizeRotation = zon.get(bool, "randomRotate", true);
		const colorRandomnessStr = zon.get(?[]const u8, "colorRandom", null);

		return EmitterProperties{
			.dragMin = drag[0],
			.dragMax = drag[1],
			.densityMin = density[0],
			.densityMax = density[1],
			.velMin = velocity[0],
			.velMax = velocity[1],
			.rotVelMin = rotVel[0],
			.rotVelMax = rotVel[1],
			.lifeTimeMin = lifeTime[0],
			.lifeTimeMax = lifeTime[1],
			.colorMin = Vec3f{(@floatFromInt(color[0] >> 16 & 0xff)), (@floatFromInt(color[0] >> 8 & 0xff)), (@floatFromInt(color[0] & 0xff))}/@as(Vec3f, @splat(255)),
			.colorMax = Vec3f{(@floatFromInt(color[1] >> 16 & 0xff)), (@floatFromInt(color[1] >> 8 & 0xff)), (@floatFromInt(color[1] & 0xff))}/@as(Vec3f, @splat(255)),
			.randomizeRotation = randomizeRotation,
			.randomColorPerChannel = if(colorRandomnessStr) |str| std.mem.eql(u8, str, "channel") else false, // TODO: redesign?
		};
	}
};

pub const DirectionMode = union(enum(u8)) {
	// The particle goes in the direction away from the center
	spread: void,
	// The particle goes in a random direction
	scatter: void,
	// The particle goes in the specified direction
	direction: DirectionData,

	pub const DirectionData = struct {
		dir: Vec3f,
		radius: f32,

		pub fn getConeVel(self: DirectionData) Vec3f {
			if(self.radius == 0) return self.dir;

			const dir = vec.normalize(self.dir);

			var u: Vec3f = if(@abs(self.dir[0]) > 0.7) Vec3f{0, 1, 0} else Vec3f{1, 0, 0};
			const v: Vec3f = vec.normalize(Vec3f{u[1]*dir[2] - u[2]*dir[1], u[2]*dir[0] - u[0]*dir[2], u[0]*dir[1] - u[1]*dir[0]});
			u = vec.normalize(Vec3f{dir[1]*v[2] - dir[2]*v[1], dir[2]*v[0] - dir[0]*v[2], dir[0]*v[1] - dir[1]*v[0]});

			var sample: Vec2f = undefined;
			while(true) {
				sample = random.nextFloatVectorSigned(2, &seed);
				if(vec.lengthSquare(sample) < 1) break;
			}

			const cosTheta: f32 = std.math.cos(self.radius);
			const z: f32 = cosTheta + (1.0 - cosTheta)*random.nextFloat(&seed);
			const scale: f32 = @sqrt(1.0 - z*z);

			return (u*@as(Vec3f, @splat(sample[0]*scale)) + v*@as(Vec3f, @splat(sample[1]*scale)) + dir*@as(Vec3f, @splat(z)));
		}
	};

	pub fn parse(zon: ZonElement) !DirectionMode {
		const dirModeName = zon.get(?[]const u8, "mode", null) orelse return error.ModeNotFound;
		const dirMode = std.meta.stringToEnum(std.meta.Tag(DirectionMode), dirModeName) orelse return error.DirectionModeNotFound;
		return switch(dirMode) {
			.direction => {
				const dir = zon.get(Vec3f, "direction", .{0, 0, 1});
				const radius = zon.get(f32, "coneRadius", 10);
				return @unionInit(DirectionMode, @tagName(DirectionMode.direction), DirectionData{.dir = dir, .radius = radius});
			},
			inline else => |mode| @unionInit(DirectionMode, @tagName(mode), {}),
		};
	}
};

pub const Emitter = struct {
	typ: u16 = 0,
	collides: bool,
	spawnType: SpawnType,
	properties: EmitterProperties,

	pub const SpawnType = union(enum(u8)) {
		point: SpawnPoint,
		sphere: SpawnSphere,
		cube: SpawnCube,

		pub fn spawn(self: SpawnType, pos: Vec3d, properties: EmitterProperties) struct {Vec3d, Vec3f} {
			return switch(self) {
				inline else => |typ| typ.spawn(pos, properties),
			};
		}

		pub fn parse(zon: ZonElement) !SpawnType {
			const typeZon = zon.get(?[]const u8, "type", null) orelse return error.TypeNotFound;
			const spawnType = std.meta.stringToEnum(std.meta.Tag(SpawnType), typeZon) orelse return error.InvalidType;
			return switch(spawnType) {
				inline else => |typ| @unionInit(SpawnType, @tagName(typ), try @FieldType(SpawnType, @tagName(typ)).parse(zon)),
			};
		}
	};

	pub const SpawnPoint = struct {
		mode: DirectionMode,

		pub fn spawn(self: SpawnPoint, pos: Vec3d, properties: EmitterProperties) struct {Vec3d, Vec3f} {
			const particlePos = pos;
			const speed: Vec3f = @splat(properties.velMin + random.nextFloat(&seed)*properties.velMax);
			const dir: Vec3f = switch(self.mode) {
				.direction => |dir| dir.getConeVel(),
				.scatter, .spread => vec.normalize(random.nextFloatVectorSigned(3, &seed)),
			};
			const particleVel = dir*speed;

			return .{particlePos, particleVel};
		}

		pub fn parse(zon: ZonElement) !SpawnPoint {
			return SpawnPoint{
				.mode = try DirectionMode.parse(zon),
			};
		}
	};

	pub const SpawnSphere = struct {
		radius: f32,
		mode: DirectionMode,

		pub fn spawn(self: SpawnSphere, pos: Vec3d, properties: EmitterProperties) struct {Vec3d, Vec3f} {
			const spawnPos: Vec3f = @splat(self.radius);
			var offsetPos: Vec3f = undefined;
			while(true) {
				offsetPos = random.nextFloatVectorSigned(3, &seed);
				if(vec.lengthSquare(offsetPos) <= 1) break;
			}
			const particlePos = pos + @as(Vec3d, @floatCast(offsetPos*spawnPos));
			const speed: Vec3f = @splat(properties.velMin + random.nextFloat(&seed)*properties.velMax);
			const dir: Vec3f = switch(self.mode) {
				.direction => |dir| dir.getConeVel(),
				.scatter => vec.normalize(random.nextFloatVectorSigned(3, &seed)),
				.spread => @floatCast(offsetPos),
			};
			const particleVel = dir*speed;

			return .{particlePos, particleVel};
		}

		pub fn parse(zon: ZonElement) !SpawnSphere {
			return SpawnSphere{
				.mode = try DirectionMode.parse(zon),
				.radius = zon.get(f32, "radius", 0),
			};
		}
	};

	pub const SpawnCube = struct {
		size: Vec3f,
		mode: DirectionMode,

		pub fn spawn(self: SpawnCube, pos: Vec3d, properties: EmitterProperties) struct {Vec3d, Vec3f} {
			const spawnPos: Vec3f = self.size;
			const offsetPos: Vec3f = random.nextFloatVectorSigned(3, &seed);
			const particlePos = pos + @as(Vec3d, @floatCast(offsetPos*spawnPos));
			const speed: Vec3f = @splat(properties.velMin + random.nextFloat(&seed)*properties.velMax);
			const dir: Vec3f = switch(self.mode) {
				.direction => |dir| dir.getConeVel(),
				.scatter => vec.normalize(random.nextFloatVectorSigned(3, &seed)),
				.spread => vec.normalize(@as(Vec3f, @floatCast(offsetPos))),
			};
			const particleVel = dir*speed;

			return .{particlePos, particleVel};
		}

		pub fn parse(zon: ZonElement) !SpawnCube {
			return SpawnCube{
				.mode = try DirectionMode.parse(zon),
				.size = zon.get(Vec3f, "size", .{0, 0, 0}),
			};
		}
	};

	pub fn init(id: []const u8, collides: bool, spawnType: SpawnType, properties: EmitterProperties) Emitter {
		const emitter = Emitter{
			.typ = ParticleManager.particleTypeHashmap.get(id) orelse 0,
			.collides = collides,
			.spawnType = spawnType,
			.properties = properties,
		};

		return emitter;
	}

	pub fn spawnParticles(self: Emitter, pos: Vec3d, spawnCount: u32) void {
		const count = @min(spawnCount, ParticleSystem.maxCapacity - ParticleSystem.particleCount);
		for(0..count) |_| {
			const particlePos, const particleVel = self.spawnType.spawn(pos, self.properties);

			ParticleSystem.addParticle(self.typ, particlePos, particleVel, self.collides, self.properties);
		}
	}
};

pub const ParticleType = struct {
	frameCount: f32,
	startFrame: f32,
	size: f32,
};

pub const Particle = extern struct {
	posAndRotation: [4]f32 align(16),
	lifeRatio: f32 = 1,
	light: u32 = 0,
	typ: u32,
	color: u16 = @as(u16, 255 >> 3) << 10 |
		@as(u16, 255 >> 3) << 5 |
		@as(u16, 255 >> 3),

	// 2 bytes left for use

	pub fn posAndRotationVec(self: Particle) Vec4f {
		return self.posAndRotation;
	}
};

pub const ParticleLocal = struct {
	velAndRotationVel: Vec4f,
	lifeVelocity: f32,
	density: f32,
	drag: f32,
	collides: bool,
};
