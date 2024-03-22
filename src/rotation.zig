const std = @import("std");

const blocks = @import("blocks.zig");
const Block = blocks.Block;
const chunk = @import("chunk.zig");
const Neighbors = chunk.Neighbors;
const main = @import("main.zig");
const vec = main.vec;
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const Mat4f = vec.Mat4f;


// TODO: Why not just use a tagged union?
/// Each block gets 16 bit of additional storage(apart from the reference to the block type).
/// These 16 bits are accessed and interpreted by the `RotationMode`.
/// With the `RotationMode` interface there is almost no limit to what can be done with those 16 bit.
pub const RotationMode = struct {
	const DefaultFunctions = struct {
		fn model(block: Block) u16 {
			return blocks.meshes.modelIndexStart(block);
		}
		fn generateData(_: *main.game.World, _: Vec3i, _: Vec3d, _: Vec3f, _: Vec3i, _: *Block, blockPlacing: bool) bool {
			return blockPlacing;
		}
		fn createBlockModel(modelId: []const u8) u16 {
			return main.models.getModelIndex(modelId);
		}
		fn updateData(_: *Block, _: u3, _: Block) bool {
			return false;
		}
	};

	/// if the block should be destroyed or changed when a certain neighbor is removed.
	dependsOnNeighbors: bool = false,

	model: *const fn(block: Block) u16 = &DefaultFunctions.model,

	createBlockModel: *const fn(modelId: []const u8) u16 = &DefaultFunctions.createBlockModel,

	/// Updates the block data of a block in the world or places a block in the world.
	/// return true if the placing was successful, false otherwise.
	generateData: *const fn(world: *main.game.World, pos: Vec3i, relativePlayerPos: Vec3d, playerDir: Vec3f, relativeDir: Vec3i, currentData: *Block, blockPlacing: bool) bool = DefaultFunctions.generateData,

	/// Updates data of a placed block if the RotationMode dependsOnNeighbors.
	updateData: *const fn(block: *Block, neighborIndex: u3, neighbor: Block) bool = &DefaultFunctions.updateData,
};

var rotationModes: std.StringHashMap(RotationMode) = undefined;

fn rotationMatrixTransform(quad: *main.models.QuadInfo, transformMatrix: Mat4f) void {
	quad.normal = vec.xyz(Mat4f.mulVec(transformMatrix, vec.combine(quad.normal, 0)));
	for(&quad.corners) |*corner| {
		corner.* = vec.xyz(Mat4f.mulVec(transformMatrix, vec.combine(corner.* - Vec3f{0.5, 0.5, 0.5}, 1))) + Vec3f{0.5, 0.5, 0.5};
	}
}

const RotationModes = struct {
	pub const NoRotation = struct {
		pub const id: []const u8 = "no_rotation";
		fn init() void {}
		fn deinit() void {}
	};
	pub const Log = struct {
		pub const id: []const u8 = "log";
		var rotatedModels: std.StringHashMap(u16) = undefined;

		fn init() void {
			rotatedModels = std.StringHashMap(u16).init(main.globalAllocator.allocator);
		}

		fn deinit() void {
			rotatedModels.deinit();
		}

		pub fn createBlockModel(modelId: []const u8) u16 {
			if(rotatedModels.get(modelId)) |modelIndex| return modelIndex;

			const baseModelIndex = main.models.getModelIndex(modelId);
			const baseModel = main.models.models.items[baseModelIndex];
			// Rotate the model:
			const modelIndex: u16 = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.identity()});
			_ = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.rotationY(std.math.pi)});
			_ = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.rotationY(std.math.pi/2.0)});
			_ = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.rotationY(-std.math.pi/2.0)});
			_ = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.rotationX(-std.math.pi/2.0)});
			_ = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.rotationX(std.math.pi/2.0)});
			rotatedModels.put(modelId, modelIndex) catch unreachable;
			return modelIndex;
		}

		pub fn model(block: Block) u16 {
			return blocks.meshes.modelIndexStart(block) + @min(block.data, 5);
		}

		pub fn generateData(_: *main.game.World, _: Vec3i, _: Vec3d, _: Vec3f, relativeDir: Vec3i, currentData: *Block, blockPlacing: bool) bool {
			if(blockPlacing) {
				if(relativeDir[0] == 1) currentData.data = chunk.Neighbors.dirNegX;
				if(relativeDir[0] == -1) currentData.data = chunk.Neighbors.dirPosX;
				if(relativeDir[1] == 1) currentData.data = chunk.Neighbors.dirNegY;
				if(relativeDir[1] == -1) currentData.data = chunk.Neighbors.dirPosY;
				if(relativeDir[2] == 1) currentData.data = chunk.Neighbors.dirDown;
				if(relativeDir[2] == -1) currentData.data = chunk.Neighbors.dirUp;
				return true;
			}
			return false;
		}
	};
	pub const Fence = struct {
		pub const id: []const u8 = "fence";
		pub const dependsOnNeighbors = true;
		var fenceModels: std.StringHashMap(u16) = undefined;
		const FenceData = packed struct(u4) {
			isConnectedNegX: bool,
			isConnectedPosX: bool,
			isConnectedNegY: bool,
			isConnectedPosY: bool,
		};

		fn init() void {
			fenceModels = std.StringHashMap(u16).init(main.globalAllocator.allocator);
		}

		fn deinit() void {
			fenceModels.deinit();
		}

		fn fenceTransform(quad: *main.models.QuadInfo, data: FenceData) void {
			for(&quad.corners, &quad.cornerUV) |*corner, *cornerUV| {
				if(!data.isConnectedNegX and corner[0] == 0) {
					corner[0] = 0.5;
					cornerUV[0] = 0.5;
				}
				if(!data.isConnectedPosX and corner[0] == 1) {
					corner[0] = 0.5;
					cornerUV[0] = 0.5;
				}
				if(!data.isConnectedNegY and corner[1] == 0) {
					corner[1] = 0.5;
					cornerUV[0] = 0.5;
				}
				if(!data.isConnectedPosY and corner[1] == 1) {
					corner[1] = 0.5;
					cornerUV[0] = 0.5;
				}
			}
		}

		pub fn createBlockModel(modelId: []const u8) u16 {
			if(fenceModels.get(modelId)) |modelIndex| return modelIndex;

			const baseModelIndex = main.models.getModelIndex(modelId);
			const baseModel = main.models.models.items[baseModelIndex];
			// Rotate the model:
			const modelIndex: u16 = baseModel.transformModel(fenceTransform, .{@as(FenceData, @bitCast(@as(u4, 0)))});
			for(1..16) |fenceData| {
				_ = baseModel.transformModel(fenceTransform, .{@as(FenceData, @bitCast(@as(u4, @intCast(fenceData))))});
			}
			fenceModels.put(modelId, modelIndex) catch unreachable;
			return modelIndex;
		}

		pub fn model(block: Block) u16 {
			return blocks.meshes.modelIndexStart(block) + (block.data & 15);
		}

		pub fn updateData(block: *Block, neighborIndex: u3, neighbor: Block) bool {
			const blockModel = blocks.meshes.modelIndexStart(block.*);
			const neighborModel = blocks.meshes.modelIndexStart(neighbor);
			const targetVal = neighbor.solid() and (blockModel == neighborModel or main.models.models.items[neighborModel].neighborFacingQuads[neighborIndex ^ 1].len != 0);
			var currentData: FenceData = @bitCast(@as(u4, @truncate(block.data)));
			switch(neighborIndex) {
				Neighbors.dirNegX => {
					currentData.isConnectedNegX = targetVal;
				},
				Neighbors.dirPosX => {
					currentData.isConnectedPosX = targetVal;
				},
				Neighbors.dirNegY => {
					currentData.isConnectedNegY = targetVal;
				},
				Neighbors.dirPosY => {
					currentData.isConnectedPosY = targetVal;
				},
				else => {},
			}
			const result: u16 = @as(u4, @bitCast(currentData));
			if(result == block.data) return false;
			block.data = result;
			return true;
		}
	};
};

pub fn init() void {
	rotationModes = std.StringHashMap(RotationMode).init(main.globalAllocator.allocator);
	inline for(@typeInfo(RotationModes).Struct.decls) |declaration| {
		register(@field(RotationModes, declaration.name));
	}
}

pub fn deinit() void {
	rotationModes.deinit();
	inline for(@typeInfo(RotationModes).Struct.decls) |declaration| {
		@field(RotationModes, declaration.name).deinit();
	}
}

pub fn getByID(id: []const u8) *RotationMode {
	if(rotationModes.getPtr(id)) |mode| return mode;
	std.log.warn("Could not find rotation mode {s}. Using no_rotation instead.", .{id});
	return rotationModes.getPtr("no_rotation").?;
}

pub fn register(comptime Mode: type) void {
	Mode.init();
	var result: RotationMode = RotationMode{};
	inline for(@typeInfo(RotationMode).Struct.fields) |field| {
		if(@hasDecl(Mode, field.name)) {
			if(field.type == @TypeOf(@field(Mode, field.name))) {
				@field(result, field.name) = @field(Mode, field.name);
			} else {
				@field(result, field.name) = &@field(Mode, field.name);
			}
		}
	}
	rotationModes.putNoClobber(Mode.id, result) catch unreachable;
}