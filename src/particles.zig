const std = @import("std");
const main = @import("main");
const graphics = @import("graphics.zig");
const SSBO = graphics.SSBO;
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

pub const ParticleManager = struct {
	// so i will probably have to store all of the particles in a single texture array and just index in it??
	pub var system: ParticleSystem = undefined;
	var types: main.List(ParticleType) = undefined;
	var textureIDs: main.List([]const u8) = undefined;
	var textures: main.List(Image) = undefined;
	var emissionTextures: main.List(Image) = undefined;
	var arenaForWorld: main.heap.NeverFailingArenaAllocator = undefined;

	// pub var blockTextureArray: TextureArray = undefined;
	// pub var emissionTextureArray: TextureArray = undefined;
	
	// have a hashmap for particle types to create them

	pub fn init() void {
		types = .init(main.globalAllocator);
		textureIDs = .init(main.globalAllocator);
		textures = .init(main.globalAllocator);
		emissionTextures = .init(main.globalAllocator);
		arenaForWorld = .init(main.globalAllocator);
		system.init(EmmiterProperties{
			.gravity = .{0, 0, 3},
			.drag = 0.97,
			.sizeStart = 0.4,
			.sizeEnd = 0.1,
			.lifeTime = 10,
		});
	}

	pub fn deinit() void {
		types.deinit();
		textureIDs.deinit();
		textures.deinit();
		emissionTextures.deinit();
		arenaForWorld.deinit();
		system.deinit();
	}

	pub fn register(assetFolder: []const u8, id: []const u8, zon: ZonElement) u16 {
		std.log.debug("Registered particle: {s}", .{id});
		var particleType: ParticleType = undefined;

		particleType.isBlockTexture = zon.get(bool, "isBlockTexture", false);
		particleType.animationFrames = zon.get(u32, "animationFrames", 1);

		const textureId = zon.get([]const u8, "texture", "cubyz:spark");
		// std.log.debug("name: {s} id: {s}", .{textureName, id});
		var splitter = std.mem.splitScalar(u8, textureId, ':');
		const mod = splitter.first();
		const _id = splitter.rest();
		particleType.texture = @intCast(types.items.len);

		var buffer: [1024]u8 = undefined;
		const path = std.fmt.bufPrint(&buffer, "{s}/{s}/particles/textures/{s}.png", .{assetFolder, mod, _id}) catch unreachable;
		textureIDs.append(arenaForWorld.allocator().dupe(u8, path));
		readTextureData(path, particleType.animationFrames);
		
		types.append(particleType);
		return @intCast(types.items.len-1);
	}

	fn generateBlockParticleTypes() void {
		
	}

	fn readTextureData(_path: []const u8, animationFrames: u32) void {
		const path = _path[0 .. _path.len - ".png".len];
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

	pub fn update(deltaTime: f64) void {
		const dt: f32 = @floatCast(deltaTime);
		system.update(dt);
	}

	pub fn render() void {
		system.render();
	}
};

const ParticleSystem = struct {
	// const maxCapacity = 131072;
	particles: main.List(Particle),
	properties: EmmiterProperties = undefined,

	var particlesSSBO: ?SSBO = null;

	var shader: Shader = undefined;
	const UniformStruct = struct {
		projectionMatrix: c_int,
		viewMatrix: c_int,
		billboardMatrix: c_int,
		playerPositionInteger: c_int,
		playerPositionFraction: c_int,
		// screenSize: c_int,
		ambientLight: c_int,
		// contrast: c_int,
		// texture_sampler: c_int,
		// emissionSampler: c_int,
		// zNear: c_int,
		// zFar: c_int,
	};
	var uniforms: UniformStruct = undefined;

	

	pub fn init(self: *ParticleSystem, props: EmmiterProperties) void {
		std.debug.print("Particle alignment: {d} size: {d}\n", .{@alignOf(Particle), @sizeOf(Particle)});
		shader = Shader.initAndGetUniforms("assets/cubyz/shaders/particles/particles.vs", "assets/cubyz/shaders/particles/particles.fs", "", &uniforms);
		
		// self.isDead = .initFull();
		self.properties = props;
		self.particles = .init(main.globalAllocator);
		particlesSSBO = SSBO.init();
		particlesSSBO.?.bind(12);
	}

	pub fn deinit(self: *ParticleSystem) void {
		shader.deinit();
		self.particles.deinit();
	}

	pub fn update(self: *ParticleSystem, deltaTime: f32) void {
		var i: u32 = 0;
		while(i < self.particles.items.len) {
			var particle = self.particles.items[i];
			particle.lifeLeft -= deltaTime;
			if(particle.lifeLeft < 0) {
				// self.isDead.set(self.particleCount-1); 
				self.particles.items[i] = self.particles.items[self.particles.items.len - 1];
				self.particles.items.len -= 1;
				continue;
			}

			particle.vel += self.properties.gravity * @as(Vec3f, @splat(deltaTime));
			particle.vel *= @as(Vec3f, @splat(self.properties.drag));
			particle.pos += particle.vel * @as(Vec3f, @splat(deltaTime));
			
			self.particles.items[i] = particle;
			i += 1; // makes things simplier
		}
		// self.particles.shrinkAndFree(self.particleCount);
	}

	// probably a good idea to add an AddQueue so that it doesnt resize the particle array constantly
	pub fn addParticle(self: *ParticleSystem, pos: Vec3f) void {
		self.particles.append(Particle{
			.pos = pos,
			.vel = random.nextFloatVectorSigned(3, &main.seed)*@as(Vec3f, @splat(4)),
			.lifeLeft = self.properties.lifeTime,
			.typ = 0,
			.collides = false,
		});
	}

	pub fn render(self: *ParticleSystem) void {
		particlesSSBO.?.bufferData(Particle, self.particles.items);

		shader.bind();
		c.glUniformMatrix4fv(uniforms.projectionMatrix, 1, c.GL_TRUE, @ptrCast(&game.projectionMatrix));
		c.glUniform3fv(uniforms.ambientLight, 1, @ptrCast(&game.world.?.ambientLight));
		c.glUniformMatrix4fv(uniforms.viewMatrix, 1, c.GL_TRUE, @ptrCast(&game.camera.viewMatrix));

		const playerPos = game.Player.super.pos;
		c.glUniform3i(uniforms.playerPositionInteger, @intFromFloat(@floor(playerPos[0])), @intFromFloat(@floor(playerPos[1])), @intFromFloat(@floor(playerPos[2])));
		c.glUniform3f(uniforms.playerPositionFraction, @floatCast(@mod(playerPos[0], 1)), @floatCast(@mod(playerPos[1], 1)), @floatCast(@mod(playerPos[2], 1)));

		const billboardMatrix = Mat4f.rotationZ(-game.camera.rotation[2] + std.math.pi*0.5)
			.mul(Mat4f.rotationY(game.camera.rotation[0]-std.math.pi*0.5));
		c.glUniformMatrix4fv(uniforms.billboardMatrix, 1, c.GL_TRUE, @ptrCast(&billboardMatrix));

		c.glDrawArrays(c.GL_TRIANGLES, 0, @intCast(self.particles.items.len*6));
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
	isBlockTexture: bool,
	texture: u32,
	animationFrames: u32,
};

// needs more thinking about the data needed here, im not sure how to use block textures for when you are breaking blocks
// TODO?: separate the data which is sent to the gpu into another struct
pub const Particle = struct {
	pos: Vec3f,
	vel: Vec3f,
	lifeLeft: f32,
	// used for identifying the particle animation things
	typ: i32, 
	light: u32 = 0,
	collides: bool,
	uv: u16 = 0,
	// 1 byte left for use due to alignment
};