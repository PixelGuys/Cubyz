const std = @import("std");

const chunk = @import("chunk.zig");
const game = @import("game.zig");
const graphics = @import("graphics.zig");
const Shader = graphics.Shader;
const Image = graphics.Image;
const Color = graphics.Color;
const Texture = graphics.Texture;
const TextureArray = graphics.TextureArray;
const c = graphics.c;
const ZonElement = @import("zon.zig").ZonElement;
const main = @import("main");
const renderer = @import("renderer.zig");
const settings = @import("settings.zig");
const utils = @import("utils.zig");
const models = @import("models.zig");
const ModelIndex = models.ModelIndex;
const rotation = @import("rotation.zig");
const RotationMode = rotation.RotationMode;
const vec = @import("vec.zig");
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const BinaryReader = main.utils.BinaryReader;

pub const maxEntityCount: usize = 65536; // 16 bit limit

var arena = main.heap.NeverFailingArenaAllocator.init(main.globalAllocator);
const arenaAllocator = arena.allocator();

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

	entityType: u16 = undefined,

	id: u32,
	name: []const u8,

	pub fn init(self: *ClientEntity, zon: ZonElement, allocator: NeverFailingAllocator) void {
		self.* = ClientEntity{
			.id = zon.get(u32, "id", std.math.maxInt(u32)),
			.width = zon.get(f64, "width", 1),
			.height = zon.get(f64, "height", 1),
			.name = allocator.dupe(u8, zon.get([]const u8, "name", "")),
			.entityType = zon.get(u16, "entityType", 0),
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
		texture_sampler: c_int,
		light: c_int,
		contrast: c_int,
		ambientLight: c_int,
		directionalLight: c_int,
	} = undefined;

	var shader: graphics.Shader = undefined; // Entities are sometimes small and sometimes big. Therefor it would mean a lot of work to still use smooth lighting. Therefor the non-smooth shader is used for those.
	pub var entities: main.utils.VirtualList(ClientEntity, 1 << 20) = undefined;
	pub var mutex: std.Thread.Mutex = .{};
	
	var entityModel: graphics.SSBO = undefined;

	pub fn init() void {
		entities = .init();
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

	pub fn generateModel() void {
		entityModel = .initStatic(models.QuadInfo, entityModelQuads.items);
		entityModel.bind(11);
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

			const texture = meshes.entityTextureArray.items[meshes.textureIndex(ent)];
			texture.bindTo(0);
			
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
			var buf = graphics.TextBuffer.init(main.stackAllocator, ent.name, .{.color = 0}, false, .center);
			defer buf.deinit();
			const size = buf.calculateLineBreaks(32, 1024);
			buf.render(xCenter - size[0]/2, yCenter - size[1], 32);
		}
	}

	pub fn render(projMatrix: Mat4f, ambientLight: Vec3f, directionalLight: Vec3f, playerPos: Vec3d) void {
		mutex.lock();
		defer mutex.unlock();
		update();
		shader.bind();

		c.glBindVertexArray(main.renderer.chunk_meshing.vao);
		c.glUniformMatrix4fv(uniforms.projectionMatrix, 1, c.GL_TRUE, @ptrCast(&projMatrix));
		c.glUniform1i(uniforms.texture_sampler, 0);
		c.glUniform3fv(uniforms.ambientLight, 1, @ptrCast(&ambientLight));
		c.glUniform3fv(uniforms.directionalLight, 1, @ptrCast(&directionalLight));
		c.glUniform1f(uniforms.contrast, 0.12);

		for(entities.items()) |ent| {
			if(ent.id == game.Player.id) continue; // don't render local player
			
			meshes.entityTextureArray.items[meshes.textureIndex(ent)].bindTo(0);
			
			const model = entityModels.items()[ent.entityType];
			
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
			c.glDrawElements(c.GL_TRIANGLES, 6*model.size, c.GL_UNSIGNED_INT, @ptrFromInt(@sizeOf(c_uint) * model.start * 6));
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

const EntityModel = struct {
	start: usize,
	size: c_int,
};

var entityModels: utils.VirtualList(EntityModel, 1 << 20) = undefined;
var entityModelNameToIndex: std.StringHashMap(u16) = .init(arenaAllocator.allocator);
var entityModelQuads: main.List(models.QuadInfo) = .init(arenaAllocator);

pub fn registerModel(id: []const u8, data: []const u8) void {
	const quadInfos = main.models.Model.loadRawModelDataFromObj(main.stackAllocator, data);
	defer main.stackAllocator.free(quadInfos);

	const start: usize = entityModels.len;
	const size: c_int = @intCast(quadInfos.len);

	entityModelQuads.appendSlice(quadInfos);

	entityModels.append(.{
		.start = start,
		.size = size,
	});

	entityModelNameToIndex.put(id, @intCast(entityModels.len - 1)) catch unreachable;
}

var _id: [maxEntityCount][]u8 = undefined;

var num: u16 = 0;
var reverseIndices: std.StringHashMap(u16) = .init(arenaAllocator.allocator);

pub fn init() void {
	entityModels = .init();
}

pub fn deinit() void {
	arena.deinit();
	entityModels.deinit();
}

pub fn getTypeById(id: []const u8) u16 {
	if(reverseIndices.get(id)) |result| {
		return result;
	} else {
		std.log.err("Couldn't find entity {s}. Replacing it with default...", .{id});
		return 0;
	}
}

pub fn register(_: []const u8, id: []const u8, _: ZonElement) u16 {
	if(reverseIndices.contains(id)) {
		std.log.err("Registered entity with id {s} twice!", .{id});
	}

	_id[num] = arenaAllocator.dupe(u8, id);
	reverseIndices.put(_id[num], @intCast(num)) catch unreachable;

	defer num += 1;
	std.log.debug("Registered entity: {d: >5} '{s}'", .{num, id});
	return @intCast(num);
}

pub const meshes = struct { // MARK: meshes
	var size: u32 = 0;
	var _modelIndex: [maxEntityCount]u16 = undefined;
	var textureIndices: [maxEntityCount]u16 = undefined;
	/// Stores the number of textures after each block was added. Used to clean additional textures when the world is switched.
	var maxTextureCount: [maxEntityCount]u32 = undefined;
	/// Number of loaded meshes. Used to determine if an update is needed.
	var loadedMeshes: u32 = 0;

	var textureIDs: main.List([]const u8) = undefined;
	var entityTextures: main.List(Image) = undefined;

	var arenaForWorld: main.heap.NeverFailingArenaAllocator = undefined;

	pub var entityTextureArray: main.List(Texture) = undefined;

	const black: Color = Color{.r = 0, .g = 0, .b = 0, .a = 255};
	const magenta: Color = Color{.r = 255, .g = 0, .b = 255, .a = 255};
	var undefinedTexture = [_]Color{magenta, black, black, magenta};
	const undefinedImage = Image{.width = 2, .height = 2, .imageData = undefinedTexture[0..]};
	var emptyTexture = [_]Color{black};
	const emptyImage = Image{.width = 1, .height = 1, .imageData = emptyTexture[0..]};

	pub fn init() void {
		entityTextureArray = .init(main.globalAllocator);
		textureIDs = .init(main.globalAllocator);
		entityTextures = .init(main.globalAllocator);
		arenaForWorld = .init(main.globalAllocator);
	}

	pub fn deinit() void {
		for (entityTextureArray.items) |tex| {
			tex.deinit();
		}
		entityTextureArray.deinit();
		textureIDs.deinit();
		entityTextures.deinit();
		arenaForWorld.deinit();
	}

	pub fn reset() void {
		meshes.size = 0;
		loadedMeshes = 0;
		textureIDs.clearRetainingCapacity();
		entityTextures.clearRetainingCapacity();
		_ = arenaForWorld.reset(.free_all);
	}

	pub inline fn model(entity: ClientEntity) ModelIndex {
		return _modelIndex[entity.entityType];
	}

	pub inline fn textureIndex(entity: ClientEntity) u16 {
		return textureIndices[entity.entityType];
	}

	fn extendedPath(_allocator: main.heap.NeverFailingAllocator, path: []const u8, ending: []const u8) []const u8 {
		return std.fmt.allocPrint(_allocator.allocator, "{s}{s}", .{path, ending}) catch unreachable;
	}

	fn readTextureFile(_path: []const u8, ending: []const u8, default: Image) Image {
		const path = extendedPath(main.stackAllocator, _path, ending);
		defer main.stackAllocator.free(path);
		return Image.readFromFile(arenaForWorld.allocator(), path) catch default;
	}

	fn readTextureData(_path: []const u8) void {
		const path = _path[0 .. _path.len - ".png".len];
		const textureInfoPath = extendedPath(main.stackAllocator, path, ".zig.zon");
		defer main.stackAllocator.free(textureInfoPath);
		const textureInfoZon = main.files.readToZon(main.stackAllocator, textureInfoPath) catch .null;
		defer textureInfoZon.deinit(main.stackAllocator);
		const base = readTextureFile(path, ".png", Image.defaultImage);
		entityTextures.append(base);
		entityTextureArray.append(.init());
	}

	pub fn readTexture(_textureId: ?[]const u8, assetFolder: []const u8) !u16 {
		const textureId = _textureId orelse return error.NotFound;
		var result: u16 = undefined;
		var splitter = std.mem.splitScalar(u8, textureId, ':');
		const mod = splitter.first();
		const id = splitter.rest();
		var path = try std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/{s}/entity/textures/{s}.png", .{assetFolder, mod, id});
		defer main.stackAllocator.free(path);
		// Test if it's already in the list:
		for(textureIDs.items, 0..) |other, j| {
			if(std.mem.eql(u8, other, path)) {
				result = @intCast(j);
				return result;
			}
		}
		const file = std.fs.cwd().openFile(path, .{}) catch |err| blk: {
			if(err != error.FileNotFound) {
				std.log.err("Could not open file {s}: {s}", .{path, @errorName(err)});
			}
			main.stackAllocator.free(path);
			path = try std.fmt.allocPrint(main.stackAllocator.allocator, "assets/{s}/entity/textures/{s}.png", .{mod, id}); // Default to global assets.
			break :blk std.fs.cwd().openFile(path, .{}) catch |err2| {
				std.log.err("File not found. Searched in \"{s}\" and also in the assetFolder \"{s}\"", .{path, assetFolder});
				return err2;
			};
		};
		file.close(); // It was only openend to check if it exists.
		// Otherwise read it into the list:
		result = @intCast(textureIDs.items.len);

		textureIDs.append(arenaForWorld.allocator().dupe(u8, path));
		readTextureData(path);
		return result;
	}

	pub fn register(assetFolder: []const u8, _: []const u8, zon: ZonElement) void {
		const modelName = zon.get([]const u8, "model", "none");
		_modelIndex[meshes.size] = entityModelNameToIndex.get(modelName) orelse blk: {
			std.log.err("Couldn't find voxelModel with name: {s}.", .{modelName});
			break :blk 0;
		};

		// The actual model is loaded later, in the rendering thread.
		// But textures can be loaded here:

		textureIndices[meshes.size] = readTexture(zon.get(?[]const u8, "texture", null), assetFolder) catch 0;

		maxTextureCount[meshes.size] = @intCast(textureIDs.items.len);

		meshes.size += 1;
	}

	pub fn reloadTextures(_: usize) void {
		entityTextures.clearRetainingCapacity();
		for(textureIDs.items) |path| {
			readTextureData(path);
		}
		generateTextureArray();
	}

	pub fn generateTextureArray() void {
		for (entityTextures.items, 0..) |image, i| {
			entityTextureArray.items[i].deinit();
			entityTextureArray.items[i] = .init();
			entityTextureArray.items[i].generate(image);
		}
	}
};
