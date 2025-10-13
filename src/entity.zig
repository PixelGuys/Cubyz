const std = @import("std");

const chunk = @import("chunk.zig");
const game = @import("game.zig");
const graphics = @import("graphics.zig");
const c = graphics.c;
const ZonElement = @import("zon.zig").ZonElement;
const main = @import("main");
const renderer = @import("renderer.zig");
const settings = @import("settings.zig");
const utils = @import("utils.zig");
const vec = @import("vec.zig");
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const BinaryReader = main.utils.BinaryReader;

pub const EntityNetworkData = struct {
	id: u32,
	pos: Vec3d,
	vel: Vec3d,
	rot: Vec3f,
};

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

	pub fn init(self: *ClientEntity, zon: ZonElement, allocator: NeverFailingAllocator) void {
		self.* = ClientEntity{
			.id = zon.get(u32, "id", std.math.maxInt(u32)),
			.width = zon.get(f64, "width", 1),
			.height = zon.get(f64, "height", 1),
			.name = allocator.dupe(u8, zon.get([]const u8, "name", "")),
		};
		self._interpolationPos = [_]f64{
			self.pos[0],
			self.pos[1],
			self.pos[2],
			@floatCast(self.rot[0]),
			@floatCast(self.rot[1]),
			@floatCast(self.rot[2]),
		};
		self._interpolationVel = @splat(0);
		self.interpolatedValues.init(&self._interpolationPos, &self._interpolationVel);
	}

	pub fn deinit(self: ClientEntity, allocator: NeverFailingAllocator) void {
		allocator.free(self.name);
	}

	pub fn getRenderPosition(self: *const ClientEntity) Vec3d {
		return Vec3d{self.pos[0], self.pos[1], self.pos[2]};
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
		light: c_int,
		contrast: c_int,
		ambientLight: c_int,
	} = undefined;
	var modelBuffer: main.graphics.SSBO = undefined;
	var modelSize: c_int = 0;
	var modelTexture: main.graphics.Texture = undefined;
	var pipeline: graphics.Pipeline = undefined; // Entities are sometimes small and sometimes big. Therefor it would mean a lot of work to still use smooth lighting. Therefor the non-smooth shader is used for those.
	pub var entities: main.utils.VirtualList(ClientEntity, 1 << 20) = undefined;
	pub var mutex: std.Thread.Mutex = .{};

	pub fn init() void {
		entities = .init();
		pipeline = graphics.Pipeline.init(
			"assets/cubyz/shaders/entity_vertex.vert",
			"assets/cubyz/shaders/entity_fragment.frag",
			"",
			&uniforms,
			.{},
			.{.depthTest = true},
			.{.attachments = &.{.alphaBlending}},
		);

		modelTexture = main.graphics.Texture.initFromFile("assets/cubyz/entity/textures/snale.png");
		const modelFile = main.files.cwd().read(main.stackAllocator, "assets/cubyz/entity/models/snale.obj") catch |err| blk: {
			std.log.err("Error while reading player model: {s}", .{@errorName(err)});
			break :blk &.{};
		};
		defer main.stackAllocator.free(modelFile);
		const quadInfos = main.models.Model.loadRawModelDataFromObj(main.stackAllocator, modelFile);
		defer main.stackAllocator.free(quadInfos);
		modelBuffer = .initStatic(main.models.QuadInfo, quadInfos);
		modelBuffer.bind(11);
		modelSize = @intCast(quadInfos.len);
	}

	pub fn deinit() void {
		for(entities.items()) |ent| {
			ent.deinit(main.globalAllocator);
		}
		entities.deinit();
		pipeline.deinit();
	}

	pub fn clear() void {
		for(entities.items()) |ent| {
			ent.deinit(main.globalAllocator);
		}
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
				@floatCast(pos3d[2] + 1.0),
				1,
			};

			const rotatedPos = game.camera.viewMatrix.mulVec(pos4f);
			const projectedPos = projMatrix.mulVec(rotatedPos);
			if(projectedPos[2] < 0) continue;
			const xCenter = (1 + projectedPos[0]/projectedPos[3])*@as(f32, @floatFromInt(main.Window.width/2));
			const yCenter = (1 - projectedPos[1]/projectedPos[3])*@as(f32, @floatFromInt(main.Window.height/2));

			graphics.draw.setColor(0xff000000);
			var buf = graphics.TextBuffer.init(main.stackAllocator, ent.name, .{.color = 0xffffff}, false, .center);
			defer buf.deinit();
			const size = buf.calculateLineBreaks(32, 1024);
			buf.render(xCenter - size[0]/2, yCenter - size[1], 32);
		}
	}

	pub fn render(projMatrix: Mat4f, ambientLight: Vec3f, playerPos: Vec3d) void {
		mutex.lock();
		defer mutex.unlock();
		update();
		pipeline.bind(null);
		c.glBindVertexArray(main.renderer.chunk_meshing.vao);
		c.glUniformMatrix4fv(uniforms.projectionMatrix, 1, c.GL_TRUE, @ptrCast(&projMatrix));
		modelTexture.bindTo(0);
		c.glUniform3fv(uniforms.ambientLight, 1, @ptrCast(&ambientLight));
		c.glUniform1f(uniforms.contrast, 0.12);

		for(entities.items()) |ent| {
			if(ent.id == game.Player.id) continue; // don't render local player

			const blockPos: vec.Vec3i = @intFromFloat(@floor(ent.pos));
			const lightVals: [6]u8 = main.renderer.mesh_storage.getLight(blockPos[0], blockPos[1], blockPos[2]) orelse @splat(0);
			const light = (@as(u32, lightVals[0] >> 3) << 25 |
				@as(u32, lightVals[1] >> 3) << 20 |
				@as(u32, lightVals[2] >> 3) << 15 |
				@as(u32, lightVals[3] >> 3) << 10 |
				@as(u32, lightVals[4] >> 3) << 5 |
				@as(u32, lightVals[5] >> 3) << 0);

			c.glUniform1ui(uniforms.light, @bitCast(@as(u32, light)));

			const pos: Vec3d = ent.getRenderPosition() - playerPos;
			const modelMatrix = (Mat4f.identity()
				.mul(Mat4f.translation(Vec3f{
					@floatCast(pos[0]),
					@floatCast(pos[1]),
					@floatCast(pos[2] - 1.0 + 0.09375),
				}))
				.mul(Mat4f.rotationZ(-ent.rot[2]))
				//.mul(Mat4f.rotationY(-ent.rot[1]))
				//.mul(Mat4f.rotationX(-ent.rot[0]))
			);
			const modelViewMatrix = game.camera.viewMatrix.mul(modelMatrix);
			c.glUniformMatrix4fv(uniforms.viewMatrix, 1, c.GL_TRUE, @ptrCast(&modelViewMatrix));
			c.glDrawElements(c.GL_TRIANGLES, 6*modelSize, c.GL_UNSIGNED_INT, null);
		}
	}

	pub fn addEntity(zon: ZonElement) void {
		mutex.lock();
		defer mutex.unlock();
		var ent = entities.addOne();
		ent.init(zon, main.globalAllocator);
	}

	pub fn removeEntity(id: u32) void {
		mutex.lock();
		defer mutex.unlock();
		for(entities.items(), 0..) |*ent, i| {
			if(ent.id == id) {
				ent.deinit(main.globalAllocator);
				_ = entities.swapRemove(i);
				if(i != entities.len) {
					entities.items()[i].interpolatedValues.outPos = &entities.items()[i]._interpolationPos;
					entities.items()[i].interpolatedValues.outVel = &entities.items()[i]._interpolationVel;
				}
				break;
			}
		}
	}

	pub fn serverUpdate(time: i16, entityData: []EntityNetworkData) void {
		mutex.lock();
		defer mutex.unlock();
		timeDifference.addDataPoint(time);

		for(entityData) |data| {
			const pos = [_]f64{
				data.pos[0],
				data.pos[1],
				data.pos[2],
				@floatCast(data.rot[0]),
				@floatCast(data.rot[1]),
				@floatCast(data.rot[2]),
			};
			const vel = [_]f64{
				data.vel[0],
				data.vel[1],
				data.vel[2],
				0,
				0,
				0,
			};
			for(entities.items()) |*ent| {
				if(ent.id == data.id) {
					ent.updatePosition(&pos, &vel, time);
					break;
				}
			}
		}
	}
};
