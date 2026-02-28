const std = @import("std");

const main = @import("main");
const physics = @import("physics.zig");
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
const RandomRange = random.RandomRange;
const vec = @import("vec.zig");
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec4d = vec.Vec4d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const Vec3i = vec.Vec3i;
const Vec2f = vec.Vec2f;

var arena = main.heap.NeverFailingArenaAllocator.init(main.globalAllocator);
const arenaAllocator = arena.allocator();

pub const blockParticleUVGridSize: comptime_int = 8;

pub const ParticleManager = struct {
	var particleTypesSSBO: SSBO = undefined;
	var types: main.ListUnmanaged(ParticleType) = .{};
	var typesLocal: main.ListUnmanaged(ParticleTypeLocal) = .{};
	var textures: main.ListUnmanaged(Image) = .{};
	var emissionTextures: main.ListUnmanaged(Image) = .{};

	var textureArray: TextureArray = undefined;
	var emissionTextureArray: TextureArray = undefined;

	const ParticleIndex = u16;
	var particleTypeHashmap: std.StringHashMapUnmanaged(ParticleIndex) = .{};

	const UVRegion = struct {x: u16, y: u16};
	var blockTextureValidRegions: std.AutoHashMapUnmanaged(u16, main.List(UVRegion)) = .{};

	pub fn init() void {
		textureArray = .init();
		emissionTextureArray = .init();
		particleTypesSSBO = SSBO.init();
		ParticleSystem.init();
	}

	pub fn deinit() void {
		textureArray.deinit();
		emissionTextureArray.deinit();
		particleTypeHashmap.deinit(arenaAllocator.allocator);

		var it = blockTextureValidRegions.valueIterator();
		while(it.next()) |validRegions| {
			validRegions.deinit();
		}
		blockTextureValidRegions.deinit(arenaAllocator.allocator);

		ParticleSystem.deinit();
		particleTypesSSBO.deinit();
	}

	pub fn reset() void {
		types = .{};
		typesLocal = .{};
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
		var rotVel: RandomRange(f32) = RandomRange(f32).fromZon(zon.getChild("rotationVelocity")) orelse .init(20, 60);
		rotVel.min = std.math.degreesToRadians(rotVel.min);
		rotVel.max = std.math.degreesToRadians(rotVel.max);
		const particleTypeLocal = ParticleTypeLocal{
			.density = RandomRange(f32).fromZon(zon.getChild("density")) orelse .init(2, 3),
			.rotVel = rotVel,
			.dragCoefficient = RandomRange(f32).fromZon(zon.getChild("dragCoefficient")) orelse .init(0.5, 0.6),
		};

		particleTypeHashmap.put(main.worldArena.allocator, id, @intCast(types.items.len)) catch unreachable;
		types.append(main.worldArena, particleType);
		typesLocal.append(main.worldArena, particleTypeLocal);

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

		if (base.height%base.width != 0) {
			std.log.err("Particle base texture has incorrect dimensions ({}x{}) expected height to be multiple of width for {s} ({s})", .{base.width, base.height, textureId, assetsFolder});
			isBaseBroken = true;
		}
		if (hasEmission and emission.height%emission.width != 0) {
			std.log.err("Particle emission texture has incorrect dimensions ({}x{}) expected height to be multiple of width for {s} ({s})", .{base.width, base.height, textureId, assetsFolder});
			isEmissionBroken = true;
		}
		if (hasEmission and baseAnimationFrameCount != emissionAnimationFrameCount) {
			std.log.err("Particle base texture and emission texture frame count mismatch ({} vs {}) for {s} ({s})", .{baseAnimationFrameCount, emissionAnimationFrameCount, textureId, assetsFolder});
			isEmissionBroken = true;
		}

		createAnimationFrames(&textures, baseAnimationFrameCount, base, isBaseBroken);
		createAnimationFrames(&emissionTextures, baseAnimationFrameCount, emission, isBaseBroken or isEmissionBroken or !hasEmission);

		return typ;
	}

	fn readTexture(assetsFolder: []const u8, textureId: []const u8, suffix: []const u8, default: graphics.Image, status: enum { isOptional, isMandatory }) graphics.Image {
		var splitter = std.mem.splitScalar(u8, textureId, ':');
		const mod = splitter.first();
		const id = splitter.rest();

		const gameAssetsPath = std.fmt.allocPrint(main.stackAllocator.allocator, "assets/{s}/particles/textures/{s}{s}", .{mod, id, suffix}) catch unreachable;
		defer main.stackAllocator.free(gameAssetsPath);

		const worldAssetsPath = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/{s}/particles/textures/{s}{s}", .{assetsFolder, mod, id, suffix}) catch unreachable;
		defer main.stackAllocator.free(worldAssetsPath);

		return graphics.Image.readFromFile(main.worldArena, worldAssetsPath) catch graphics.Image.readFromFile(main.worldArena, gameAssetsPath) catch {
			if (status == .isMandatory) std.log.err("Particle texture not found in {s} and {s}.", .{worldAssetsPath, gameAssetsPath});
			return default;
		};
	}

	fn createAnimationFrames(container: *main.ListUnmanaged(Image), frameCount: usize, image: Image, isBroken: bool) void {
		for (0..frameCount) |i| {
			container.append(main.worldArena, if (isBroken) image else extractAnimationSlice(image, i));
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

	fn computeValidUVRegions(image: Image) main.List(UVRegion) {
		var validRegions = main.List(UVRegion).init(arenaAllocator);

		const gridSize = blockParticleUVGridSize;
		const regionWidth = image.width/gridSize;
		const regionHeight = image.height/gridSize;
		const minVisiblePixels = (regionWidth*regionHeight)/4; // At least 25% visible

		var gridY: u16 = 0;
		while(gridY < gridSize) : (gridY += 1) {
			var gridX: u16 = 0;
			while(gridX < gridSize) : (gridX += 1) {
				// Count visible pixels in this region
				var visibleCount: u32 = 0;
				const startX = gridX*regionWidth;
				const startY = gridY*regionHeight;

				var y: u32 = 0;
				while(y < regionHeight) : (y += 1) {
					var x: u32 = 0;
					while(x < regionWidth) : (x += 1) {
						const pixelX = startX + x;
						const pixelY = startY + y;
						if(pixelX < image.width and pixelY < image.height) {
							const pixel = image.getRGB(pixelX, pixelY);
							if(pixel.a >= 128) {// Consider semi-transparent as visible
								visibleCount += 1;
							}
						}
					}
				}

				if(visibleCount >= minVisiblePixels) {
					validRegions.append(.{.x = gridX, .y = gridY});
				}
			}
		}

		// If no valid regions found, add the center region as fallback
		if(validRegions.items.len == 0) {
			validRegions.append(.{.x = gridSize/2, .y = gridSize/2});
		}

		return validRegions;
	}

	pub fn registerBlockTextureAsParticle(blockId: []const u8, textureIndex: u16, image: Image) void {
		const particleType = ParticleType{
			.frameCount = 1,
			.startFrame = -@as(f32, @floatFromInt(textureIndex)) - 1, // negative to indicate block texture
			.size = 1.0/@as(f32, blockParticleUVGridSize),
		};

		const particleId = std.fmt.allocPrint(arenaAllocator.allocator, "block:{s}", .{blockId}) catch unreachable;
		particleTypeHashmap.put(arenaAllocator.allocator, particleId, @intCast(types.items.len)) catch unreachable;
		types.append(arenaAllocator, particleType);

		const validRegions = computeValidUVRegions(image);
		blockTextureValidRegions.put(arenaAllocator.allocator, textureIndex, validRegions) catch unreachable;
	}

	pub fn getRandomValidUVOffset(textureIndex: u16, randomSeed: *u64) u32 {
		const validRegions = blockTextureValidRegions.get(textureIndex) orelse {
			// Fallback: return center region
			const center = blockParticleUVGridSize/2;
			return center | (@as(u32, center) << 16) | (1 << 31);
		};

		if(validRegions.items.len == 0) {
			// Fallback: return center region
			const center = blockParticleUVGridSize/2;
			return center | (@as(u32, center) << 16) | (1 << 31);
		}

		const idx = main.random.nextIntBounded(u32, randomSeed, @as(u32, @intCast(validRegions.items.len)));
		const region = validRegions.items[idx];
		return region.x | (@as(u32, region.y) << 16) | (1 << 31);
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
	var networkCreationQueue: main.ListUnmanaged(struct { emitter: Emitter, pos: Vec3d, count: u32 }) = .{};

	var particlesSSBO: SSBO = undefined;

	var pipeline: graphics.Pipeline = undefined;
	const UniformStruct = struct {
		projectionAndViewMatrix: c_int,
		billboardMatrix: c_int,
		ambientLight: c_int,
	};
	var uniforms: UniformStruct = undefined;

	pub fn init() void {
		const defines = std.fmt.comptimePrint("#define BLOCK_PARTICLE_UV_GRID_SIZE {d}\n", .{blockParticleUVGridSize});
		pipeline = graphics.Pipeline.init(
			"assets/cubyz/shaders/particles/particles.vert",
			"assets/cubyz/shaders/particles/particles.frag",
			defines,
			&uniforms,
			.{},
			.{.depthTest = true, .depthWrite = true},
			.{.attachments = &.{.noBlending}},
		);

		particlesSSBO = SSBO.init();
		particlesSSBO.createDynamicBuffer(Particle, maxCapacity);
		particlesSSBO.bind(13);
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
		if (networkCreationQueue.items.len != 0) {
			for (networkCreationQueue.items) |creation| {
				creation.emitter.spawnParticles(creation.pos, creation.count);
			}
			networkCreationQueue.clearRetainingCapacity();
		}
		mutex.unlock();

		const vecDeltaTime: Vec4f = @as(Vec4f, @splat(deltaTime));
		const playerPos = game.Player.getEyePosBlocking();
		const prevPlayerPosDifference: Vec3f = @floatCast(previousPlayerPos - playerPos);

		var i: u32 = 0;
		while (i < particleCount) {
			const particle = &particles[i];
			const particleLocal = &particlesLocal[i];
			particle.lifeRatio -= particleLocal.lifeVelocity*deltaTime;
			if (particle.lifeRatio < 0) {
				particleCount -= 1;
				particles[i] = particles[particleCount];
				particlesLocal[i] = particlesLocal[particleCount];
				continue;
			}

			var pos: Vec3f = particle.pos;
			var rot = particle.rot;
			const rotVel = particleLocal.velAndRotationVel[3];
			rot += rotVel*deltaTime;

			const airDensity: f32 = physics.airDensity;
			const frictionCoefficient = physics.gravity/physics.airTerminalVelocity*particleLocal.dragCoefficient;
			particleLocal.velAndRotationVel[3] = 0;
			const effectiveGravity: f32 = @floatCast(physics.gravity*(particleLocal.density - airDensity)/particleLocal.density);
			particleLocal.velAndRotationVel[2] -= effectiveGravity*deltaTime;
			particleLocal.velAndRotationVel *= @splat(@exp(-frictionCoefficient*deltaTime));

			if (particleLocal.collides) {
				var v3Pos = playerPos + @as(Vec3d, @floatCast(pos + prevPlayerPosDifference));
				const size = ParticleManager.types.items[particle.typ].size;
				const hitBox: game.collision.Box = .{.min = @splat(size*-0.5), .max = @splat(size*0.5)};

				const posDelta = particleLocal.velAndRotationVel*vecDeltaTime;

				v3Pos[0] += posDelta[0];
				if (game.collision.collides(.client, .x, -posDelta[0], v3Pos, hitBox)) |box| {
					v3Pos[0] = if (posDelta[0] < 0)
						box.max[0] - hitBox.min[0]
					else
						box.min[0] - hitBox.max[0];
				}
				v3Pos[1] += posDelta[1];
				if (game.collision.collides(.client, .y, -posDelta[1], v3Pos, hitBox)) |box| {
					v3Pos[1] = if (posDelta[1] < 0)
						box.max[1] - hitBox.min[1]
					else
						box.min[1] - hitBox.max[1];
				}
				v3Pos[2] += posDelta[2];
				if (game.collision.collides(.client, .z, -posDelta[2], v3Pos, hitBox)) |box| {
					v3Pos[2] = if (posDelta[2] < 0)
						box.max[2] - hitBox.min[2]
					else
						box.min[2] - hitBox.max[2];
				}
				pos = @as(Vec3f, @floatCast(v3Pos - playerPos));
			} else {
				const posDelta = particleLocal.velAndRotationVel*vecDeltaTime;

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

	fn addParticle(typ: u32, particleType: ParticleTypeLocal, pos: Vec3d, vel: Vec3f, collides: bool, properties: EmitterProperties, uvOffset: u32) void {
		const lifeTime = properties.lifeTime.get(&main.seed);
		const density = particleType.density.get(&main.seed);
		const rot = if (properties.randomizeRotation) random.nextFloat(&main.seed)*std.math.pi*2 else 0;
		const rotVel = particleType.rotVel.get(&main.seed);
		const dragCoeff = particleType.dragCoefficient.get(&main.seed);

		particles[particleCount] = Particle{
			.pos = @as(Vec3f, @floatCast(pos - previousPlayerPos)),
			.rot = rot,
			.typ = typ,
			.uvOffset = uvOffset,
		};
		particlesLocal[particleCount] = ParticleLocal{
			.velAndRotationVel = vec.combine(vel, rotVel),
			.lifeVelocity = 1/lifeTime,
			.density = density,
			.dragCoefficient = dragCoeff,
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
		c.glActiveTexture(c.GL_TEXTURE2);
		@import("blocks.zig").meshes.blockTextureArray.bind();

		c.glBindVertexArray(chunk_meshing.vao);

		const maxQuads = chunk_meshing.maxQuadsInIndexBuffer;
		const count = std.math.divCeil(u32, particleCount, maxQuads) catch unreachable;
		for (0..count) |i| {
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
	speed: RandomRange(f32),
	lifeTime: RandomRange(f32),
	randomizeRotation: bool,

	pub fn parse(zon: ZonElement) EmitterProperties {
		return EmitterProperties{
			.speed = RandomRange(f32).fromZon(zon.getChild("speed")) orelse .init(1, 1.5),
			.lifeTime = RandomRange(f32).fromZon(zon.getChild("lifeTime")) orelse .init(0.75, 1),
			.randomizeRotation = zon.get(bool, "randomRotate", true),
		};
	}
};

pub const DirectionMode = union(enum) {
	// The particle goes in the direction away from the center
	spread: void,
	// The particle goes in a random direction
	scatter: void,
	// The particle goes in the specified direction
	direction: Vec3f,

	pub fn parse(zon: ZonElement) !DirectionMode {
		const dirModeName = zon.get([]const u8, "mode", @tagName(DirectionMode.spread));
		const dirMode = std.meta.stringToEnum(std.meta.Tag(DirectionMode), dirModeName) orelse return error.InvalidDirectionMode;
		return switch (dirMode) {
			.direction => .{.direction = zon.get(Vec3f, "direction", .{0, 0, 1})},
			inline else => |mode| @unionInit(DirectionMode, @tagName(mode), {}),
		};
	}
};

pub const Emitter = struct {
	typ: u16 = 0,
	particleType: ParticleTypeLocal,
	collides: bool,
	spawnShape: SpawnShape,
	properties: EmitterProperties,
	mode: DirectionMode,

	pub const SpawnShape = union(enum) {
		point: SpawnPoint,
		sphere: SpawnSphere,
		cube: SpawnCube,

		pub fn spawn(self: SpawnShape, pos: Vec3d, properties: EmitterProperties, mode: DirectionMode) struct { Vec3d, Vec3f } {
			return switch (self) {
				inline else => |shape| shape.spawn(pos, properties, mode),
			};
		}

		pub fn parse(zon: ZonElement) !SpawnShape {
			const typeZon = zon.get([]const u8, "shape", @tagName(SpawnShape.point));
			const spawnType = std.meta.stringToEnum(std.meta.Tag(SpawnShape), typeZon) orelse return error.InvalidType;
			return switch (spawnType) {
				inline else => |shape| @unionInit(SpawnShape, @tagName(shape), try @FieldType(SpawnShape, @tagName(shape)).parse(zon)),
			};
		}
	};

	pub const SpawnPoint = struct {
		pub fn spawn(_: SpawnPoint, pos: Vec3d, properties: EmitterProperties, mode: DirectionMode) struct { Vec3d, Vec3f } {
			const particlePos = pos;
			const speed: Vec3f = @splat(properties.speed.get(&main.seed));
			const dir: Vec3f = switch (mode) {
				.direction => |dir| vec.normalize(dir),
				.scatter, .spread => vec.normalize(random.nextFloatVectorSigned(3, &main.seed)),
			};
			const particleVel = dir*speed;

			return .{particlePos, particleVel};
		}

		pub fn parse(_: ZonElement) !SpawnPoint {
			return SpawnPoint{};
		}
	};

	pub const SpawnSphere = struct {
		radius: f32,

		pub fn spawn(self: SpawnSphere, pos: Vec3d, properties: EmitterProperties, mode: DirectionMode) struct { Vec3d, Vec3f } {
			const spawnPos: Vec3f = @splat(self.radius);
			var offsetPos: Vec3f = undefined;
			while (true) {
				offsetPos = random.nextFloatVectorSigned(3, &main.seed);
				if (vec.lengthSquare(offsetPos) <= 1) break;
			}
			const particlePos = pos + @as(Vec3d, @floatCast(offsetPos*spawnPos));
			const speed: Vec3f = @splat(properties.speed.get(&main.seed));
			const dir: Vec3f = switch (mode) {
				.direction => |dir| vec.normalize(dir),
				.scatter => vec.normalize(random.nextFloatVectorSigned(3, &main.seed)),
				.spread => @floatCast(offsetPos),
			};
			const particleVel = dir*speed;

			return .{particlePos, particleVel};
		}

		pub fn parse(zon: ZonElement) !SpawnSphere {
			return SpawnSphere{
				.radius = zon.get(f32, "radius", 1),
			};
		}
	};

	pub const SpawnCube = struct {
		size: Vec3f,

		pub fn spawn(self: SpawnCube, pos: Vec3d, properties: EmitterProperties, mode: DirectionMode) struct { Vec3d, Vec3f } {
			const spawnPos: Vec3f = self.size;
			const offsetPos: Vec3f = random.nextFloatVectorSigned(3, &main.seed);
			const particlePos = pos + @as(Vec3d, @floatCast(offsetPos*spawnPos));
			const speed: Vec3f = @splat(properties.speed.get(&main.seed));
			const dir: Vec3f = switch (mode) {
				.direction => |dir| vec.normalize(dir),
				.scatter => vec.normalize(random.nextFloatVectorSigned(3, &main.seed)),
				.spread => vec.normalize(@as(Vec3f, @floatCast(offsetPos))),
			};
			const particleVel = dir*speed;

			return .{particlePos, particleVel};
		}

		pub fn parse(zon: ZonElement) !SpawnCube {
			return SpawnCube{
				.size = zon.get(?Vec3f, "size", null) orelse @splat(zon.get(f32, "size", 1)),
			};
		}
	};

	pub fn init(id: []const u8, collides: bool, spawnShape: SpawnShape, properties: EmitterProperties, mode: DirectionMode) Emitter {
		const typ = ParticleManager.particleTypeHashmap.get(id) orelse 0;

		return Emitter{
			.typ = typ,
			.particleType = ParticleManager.typesLocal.items[typ],
			.collides = collides,
			.spawnShape = spawnShape,
			.properties = properties,
			.mode = mode,
		};
	}

	pub fn initFromZon(id: []const u8, collides: bool, zon: ZonElement) Emitter {
		const typ = ParticleManager.particleTypeHashmap.get(id) orelse 0;
		const mode = DirectionMode.parse(zon) catch |err| blk: {
			std.log.err("Error while parsing direction mode: \"{s}\"", .{@errorName(err)});
			break :blk .spread;
		};
		const spawnShape = Emitter.SpawnShape.parse(zon) catch |err| blk: {
			std.log.err("Error while parsing particle spawn data: \"{s}\"", .{@errorName(err)});
			break :blk Emitter.SpawnShape{.point = .{}};
		};

		return Emitter{
			.typ = typ,
			.particleType = ParticleManager.typesLocal.items[typ],
			.collides = collides,
			.spawnShape = spawnShape,
			.properties = EmitterProperties.parse(zon),
			.mode = mode,
		};
	}

	pub fn spawnParticles(self: Emitter, pos: Vec3d, spawnCount: u32) void {
		const count = @min(spawnCount, ParticleSystem.maxCapacity - ParticleSystem.particleCount);
		for (0..count) |_| {
			const particlePos, const particleVel = self.spawnShape.spawn(pos, self.properties, self.mode);

			ParticleSystem.addParticle(self.typ, self.particleType, particlePos, particleVel, self.collides, self.properties, 0);
		}
	}

	pub fn spawnParticlesWithUV(self: Emitter, pos: Vec3d, spawnCount: u32, uvOffset: u32) void {
		const count = @min(spawnCount, ParticleSystem.maxCapacity - ParticleSystem.particleCount);
		for (0..count) |_| {
			const particlePos, const particleVel = self.spawnShape.spawn(pos, self.properties, self.mode);

			ParticleSystem.addParticle(self.typ, self.particleType, particlePos, particleVel, self.collides, self.properties, uvOffset);
		}
	}
};

pub const ParticleType = struct {
	frameCount: f32,
	startFrame: f32,
	size: f32,
};

pub const ParticleTypeLocal = struct {
	density: RandomRange(f32),
	rotVel: RandomRange(f32),
	dragCoefficient: RandomRange(f32),
};

pub const Particle = extern struct {
	pos: [3]f32 align(16),
	rot: f32 = 0,
	lifeRatio: f32 = 1,
	light: u32 = 0,
	typ: u32,
	uvOffset: u32 = 0, // packed: bit 31 = has UV offset, bits 0-15 = x offset, bits 16-30 = y offset
};

pub const ParticleLocal = struct {
	velAndRotationVel: Vec4f,
	lifeVelocity: f32,
	density: f32,
	dragCoefficient: f32,
	collides: bool,
};
