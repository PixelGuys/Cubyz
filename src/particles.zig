const std = @import("std");
const main = @import("main");
const graphics = @import("graphics.zig");
const Shader = graphics.Shader;
const random = @import("random.zig");
const Color = graphics.Color;
const vec = @import("vec.zig");
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

const ParticleManager = struct {
	// so i will probably have to store all of the particles in a single texture array and just index in it??
	const system: ParticleSystem = undefined;

	const shader: Shader = undefined;
	const UniformStruct = struct {
		projectionMatrix: c_int,
		viewMatrix: c_int,
		playerPositionInteger: c_int,
		playerPositionFraction: c_int,
		screenSize: c_int,
		ambientLight: c_int,
		contrast: c_int,
		texture_sampler: c_int,
		emissionSampler: c_int,
		lodDistance: c_int,
		zNear: c_int,
		zFar: c_int,
	};

	pub fn init() void {
		shader = Shader.initAndGetUniforms("assets/cubyz/shaders/chunks/chunk_vertex.vs", "assets/cubyz/shaders/chunks/chunk_fragment.fs", "", &uniforms);

		system.init(ParticleProperties{
			.gravity = 1,
			.colorStart = .{1, 1, 1},
			.colorEnd = .{0.5, 0.5, 0.5},
			.drag = 0.95,
			.sizeStart = 0.4,
			.sizeEnd = 0.1,
			.lifeTime = 3,
		});
	}

	pub fn updateParticles(deltaTime: f64) void {
		const dt: f32 = @floatCast(deltaTime);
		system.update(dt);
	}

	pub fn renderParticles() void {
		system.render();
	}
};

const ParticleSystem = struct {
	const maxCapacity = 16384;
	particleCount: u32 = 0,
	particles: main.List(Particle),
	// particles: std.MultiArrayList(Particle),
	properties: ParticleProperties = undefined,
	isDead: std.bit_set.ArrayBitSet(usize, maxCapacity),

	pub fn init(self: *ParticleSystem, props: ParticleProperties) void {
		std.debug.print("Particle alignment: {d} size: {d}\n", .{@alignOf(Particle), @sizeOf(Particle)});
		
		self.properties = props;
		self.particles = .init(main.globalAllocator);
	}

	pub fn deinit(self: *ParticleSystem) void {
		self.particles.deinit();
	}

	pub fn update(self: ParticleSystem, deltaTime: f32) void {
		// const pos = self.particles.items(.pos);
		// const vel = self.particles.items(.vel);
		// const color = self.particles.items(.color);
		// const rot = self.particles.items(.rot);
		// const size = self.particles.items(.size);
		// const lifeLeft = self.particles.items(.lifeLeft);
		var i: u32 = 0;
		while(i < self.particleCount) : (i += 1) {
			const particle = self.particles.items[i];
			particle.lifeLeft -= deltaTime;
			if(particle.lifeLeft < 0) {
				self.isDead.set(self.particleCount-1); 
				self.particles.items[i] = self.particles.items[self.particleCount-1];
				self.particleCount -= 1;
				i -= 1;
				continue;
			}

			particle.vel += self.properties.gravity * deltaTime;
			particle.vel *= self.properties.drag;
			particle.pos += particle.vel * deltaTime;
			
			particle.rotVel *= self.properties.drag;
			particle.rot += particle.rotVel;

			self.particles.items[i] = particle;
		}
		self.particles.resize(self.particleCount);
	}

	// probably a good idea to add an AddQueue so that it doesnt resize the particle array constantly
	pub fn addParticle(self: ParticleSystem, pos: Vec3f, color: Color) void {
		self.particles.append(Particle{
			.pos = pos,
			.vel = random.nextFloatVectorSigned(3, &main.seed),
			.color = color,
			.rot = @splat(0),
			.rotVel = random.nextFloatSigned(&main.seed),
			.lifeLeft = self.properties.lifeTime,
		});
	}

	pub fn render(self: ParticleSystem) void {
		
	}
};

pub const ParticleProperties = struct {
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

// needs more thinking about the data needed here, im not sure how to use block textures for when you are breaking blocks
pub const Particle = struct {
	pos: Vec3f,
	vel: Vec3f,
	// alpha is unused
	color: Color,
	rot: f32,
	rotVel: f32,
	lifeLeft: f32,
};