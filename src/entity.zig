const std = @import("std");

const chunk = @import("chunk.zig");
const game = @import("game.zig");
const graphics = @import("graphics.zig");
const c = graphics.c;
const JsonElement = @import("json.zig").JsonElement;
const main = @import("main.zig");
const renderer = @import("renderer.zig");
const settings = @import("settings.zig");
const utils = @import("utils.zig");
const vec = @import("vec.zig");
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;

pub const ClientEntity = struct {
	interpolatedValues: utils.GenericInterpolation(6) = undefined,
	_interpolationPos: [6]f64 = undefined,
	_interpolationVel: [6]f64 = undefined,

	width: f64,
	height: f64,
	
	pos: Vec3d = undefined,
	rot: Vec3f = undefined,

	id: u32,
	name: []const u8,

	pub fn init(self: *ClientEntity, json: JsonElement, allocator: NeverFailingAllocator) void {
		self.* = ClientEntity{
			.id = json.get(u32, "id", std.math.maxInt(u32)),
			.width = json.get(f64, "width", 1),
			.height = json.get(f64, "height", 1),
			.name = allocator.dupe(u8, json.get([]const u8, "name", "")),
		};
		self._interpolationPos = [_]f64 {
			self.pos[0],
			self.pos[1],
			self.pos[2],
			@floatCast(self.rot[0]),
			@floatCast(self.rot[1]),
			@floatCast(self.rot[2]),
		};
		self._interpolationVel = [_]f64{0} ** 6;
		self.interpolatedValues.init(&self._interpolationPos, &self._interpolationVel);
	}

	pub fn deinit(self: ClientEntity, allocator: NeverFailingAllocator) void {
		allocator.free(self.name);
	}

	pub fn getRenderPosition(self: *const ClientEntity) Vec3d {
		return Vec3d{self.pos[0], self.pos[1], self.pos[2] + self.height/2};
	}

	pub fn updatePosition(self: *ClientEntity, pos: *const [6]f64, vel: *const [6]f64, time: i16) void {
		self.interpolatedValues.updatePosition(pos, vel, time);
	}

	pub fn update(self: *ClientEntity, time: i16, lastTime: i16) void {
		self.interpolatedValues.update(time, lastTime);
		self.pos[0] = self.interpolatedValues.outPos[0];
		self.pos[1] = self.interpolatedValues.outPos[1];
		self.pos[2] = self.interpolatedValues.outPos[2];
		self.rot[0] = @floatCast(self.interpolatedValues.outPos[3]);
		self.rot[1] = @floatCast(self.interpolatedValues.outPos[4]);
		self.rot[2] = @floatCast(self.interpolatedValues.outPos[5]);
	}
};

pub const ClientEntityManager = struct {
	var lastTime: i16 = 0;
	var timeDifference: utils.TimeDifference = utils.TimeDifference{};
	var uniforms: struct {
		projectionMatrix: c_int,
		viewMatrix: c_int,
		texture_sampler: c_int,
		materialHasTexture: c_int,
		light: c_int,
		ambientLight: c_int,
		directionalLight: c_int,
	} = undefined;
	var shader: graphics.Shader = undefined; // Entities are sometimes small and sometimes big. Therefor it would mean a lot of work to still use smooth lighting. Therefor the non-smooth shader is used for those.
	pub var entities: main.VirtualList(ClientEntity, 1 << 20) = undefined;
	pub var mutex: std.Thread.Mutex = std.Thread.Mutex{};

	pub fn init() void {
		entities = main.VirtualList(ClientEntity, 1 << 20).init();
		shader = graphics.Shader.initAndGetUniforms("assets/cubyz/shaders/entity_vertex.vs", "assets/cubyz/shaders/entity_fragment.fs", "", &uniforms);
	}

	pub fn deinit() void {
		for(entities.items()) |ent| {
			ent.deinit(main.globalAllocator);
		}
		entities.deinit();
		shader.deinit();
	}

	pub fn clear() void {
		entities.clearRetainingCapacity();
		timeDifference = utils.TimeDifference{};
	}

	fn update() void {
		main.utils.assertLocked(&mutex);
		var time: i16 = @truncate(std.time.milliTimestamp() -% settings.entityLookback);
		time -%= timeDifference.difference.load(.monotonic);
		for(entities.items()) |*ent| {
			ent.update(time, lastTime);
		}
		lastTime = time;
	}

	pub fn renderNames(projMatrix: Mat4f, playerPos: Vec3d) void {
		mutex.lock();
		defer mutex.unlock();

		for(entities.items()) |ent| {
			if(ent.id == game.Player.id or ent.name.len == 0) continue; // don't render local player
			const pos3d = ent.getRenderPosition() - playerPos;
			const pos4f = Vec4f{
				@floatCast(pos3d[0]),
				@floatCast(pos3d[1]),
				@floatCast(pos3d[2] + 1.5),
				1,
			};

			const rotatedPos = game.camera.viewMatrix.mulVec(pos4f);
			const projectedPos = projMatrix.mulVec(rotatedPos);
			if(projectedPos[2] < 0) continue;
			const xCenter = (1 + projectedPos[0]/projectedPos[3])*@as(f32, @floatFromInt(main.Window.width/2));
			const yCenter = (1 - projectedPos[1]/projectedPos[3])*@as(f32, @floatFromInt(main.Window.height/2));
			
			graphics.draw.setColor(0xff000000);
			graphics.draw.text(ent.name, xCenter, yCenter, 32, .center);
		}
	}

	pub fn render(projMatrix: Mat4f, ambientLight: Vec3f, directionalLight: Vec3f, playerPos: Vec3d) void {
		mutex.lock();
		defer mutex.unlock();
		update();
		shader.bind();
		c.glUniformMatrix4fv(uniforms.projectionMatrix, 1, c.GL_TRUE, @ptrCast(&projMatrix));
		c.glUniform1i(uniforms.texture_sampler, 0);
		c.glUniform3fv(uniforms.ambientLight, 1, @ptrCast(&ambientLight));
		c.glUniform3fv(uniforms.directionalLight, 1, @ptrCast(&directionalLight));

		for(entities.items()) |ent| {
			if(ent.id == game.Player.id) continue; // don't render local player

			// TODO: Entity meshes.
			// TODO: c.glBindVertexArray(vao);
			c.glUniform1i(uniforms.materialHasTexture, c.GL_TRUE);
			c.glUniform1i(uniforms.light, @bitCast(@as(u32, 0xffffffff))); // TODO: Lighting

			const pos: Vec3d = ent.getRenderPosition() - playerPos;
			const modelMatrix = (
				Mat4f.identity() // TODO: .scale(scale);
				.mul(Mat4f.rotationZ(-ent.rot[2]))
				.mul(Mat4f.rotationY(-ent.rot[1]))
				.mul(Mat4f.rotationX(-ent.rot[0]))
				.mul(Mat4f.translation(Vec3f{
					@floatCast(pos[0]),
					@floatCast(pos[1]),
					@floatCast(pos[2]),
				}))
			);
			const modelViewMatrix = modelMatrix.mul(game.camera.viewMatrix);
			c.glUniformMatrix4fv(uniforms.viewMatrix, 1, c.GL_TRUE, @ptrCast(&modelViewMatrix));
			// TODO: c.glDrawElements(...);
		}
	}

	pub fn addEntity(json: JsonElement) void {
		mutex.lock();
		defer mutex.unlock();
		var ent = entities.addOne();
		ent.init(json, main.globalAllocator);
	}

	pub fn removeEntity(id: u32) void {
		mutex.lock();
		defer mutex.unlock();
		for(entities.items(), 0..) |*ent, i| {
			if(ent.id == id) {
				ent.deinit(main.globalAllocator);
				_ = entities.swapRemove(i);
				break;
			}
		}
	}

	pub fn serverUpdate(time: i16, data: []const u8) void {
		mutex.lock();
		defer mutex.unlock();
		timeDifference.addDataPoint(time);
		std.debug.assert(data.len%(4 + 24 + 12 + 24) == 0);
		var remaining = data;
		while(remaining.len != 0) {
			const id = std.mem.readInt(u32, remaining[0..4], .big);
			remaining = remaining[4..];
			const pos = [_]f64 {
				@bitCast(std.mem.readInt(u64, remaining[0..8], .big)),
				@bitCast(std.mem.readInt(u64, remaining[8..16], .big)),
				@bitCast(std.mem.readInt(u64, remaining[16..24], .big)),
				@floatCast(@as(f32, @bitCast(std.mem.readInt(u32, remaining[24..28], .big)))),
				@floatCast(@as(f32, @bitCast(std.mem.readInt(u32, remaining[28..32], .big)))),
				@floatCast(@as(f32, @bitCast(std.mem.readInt(u32, remaining[32..36], .big)))),
			};
			remaining = remaining[36..];
			const vel = [_]f64 {
				@bitCast(std.mem.readInt(u64, remaining[0..8], .big)),
				@bitCast(std.mem.readInt(u64, remaining[8..16], .big)),
				@bitCast(std.mem.readInt(u64, remaining[16..24], .big)),
				0, 0, 0,
			};
			remaining = remaining[24..];
			for(entities.items()) |*ent| {
				if(ent.id == id) {
					ent.updatePosition(&pos, &vel, time);
					break;
				}
			}
		}
	}
};