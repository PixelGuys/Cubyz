const std = @import("std");

const blocks = @import("blocks.zig");
const Block = blocks.Block;
const chunk = @import("chunk.zig");
const Neighbor = chunk.Neighbor;
const main = @import("main.zig");
const vec = main.vec;
const Vec2f = vec.Vec2f;
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;
const Mat4f = vec.Mat4f;
const ZonElement = main.ZonElement;

const RayIntersectionResult = struct {
	distance: f64,
	min: Vec3f,
	max: Vec3f,
};

// TODO: Why not just use a tagged union?
/// Each block gets 16 bit of additional storage(apart from the reference to the block type).
/// These 16 bits are accessed and interpreted by the `RotationMode`.
/// With the `RotationMode` interface there is almost no limit to what can be done with those 16 bit.
pub const RotationMode = struct { // MARK: RotationMode
	const DefaultFunctions = struct {
		fn model(block: Block) u16 {
			return blocks.meshes.modelIndexStart(block);
		}
		fn generateData(_: *main.game.World, _: Vec3i, _: Vec3f, _: Vec3f, _: Vec3i, _: ?Neighbor, _: *Block, _: Block, blockPlacing: bool) bool {
			return blockPlacing;
		}
		fn createBlockModel(zon: ZonElement) u16 {
			return main.models.getModelIndex(zon.as([]const u8, "cubyz:cube"));
		}
		fn updateData(_: *Block, _: Neighbor, _: Block) bool {
			return false;
		}
		fn modifyBlock(_: *Block, _: u16) bool {
			return false;
		}
		fn rayIntersection(block: Block, _: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f) ?RayIntersectionResult {
			return rayModelIntersection(blocks.meshes.model(block), relativePlayerPos, playerDir);
		}
		fn rayModelIntersection(modelIndex: u32, relativePlayerPos: Vec3f, playerDir: Vec3f) ?RayIntersectionResult {
			// Check the true bounding box (using this algorithm here: https://tavianator.com/2011/ray_box.html):
			const invDir = @as(Vec3f, @splat(1))/playerDir;
			const modelData = &main.models.models.items[modelIndex];
			const min: Vec3f = modelData.min;
			const max: Vec3f = modelData.max;
			const t1 = (min - relativePlayerPos)*invDir;
			const t2 = (max - relativePlayerPos)*invDir;
			const boxTMin = @reduce(.Max, @min(t1, t2));
			const boxTMax = @reduce(.Min, @max(t1, t2));
			if(boxTMin <= boxTMax and boxTMax > 0) {
				return .{
					.distance = boxTMin,
					.min = min,
					.max = max,
				};
			}
			return null;
		}
		fn onBlockBreaking(_: ?main.items.Item, _: Vec3f, _: Vec3f, currentData: *Block) void {
			currentData.* = .{.typ = 0, .data = 0};
		}
		fn canBeChangedInto(oldBlock: Block, newBlock: Block, item: main.items.ItemStack, shouldDropSourceBlockOnSuccess: *bool) CanBeChangedInto {
			shouldDropSourceBlockOnSuccess.* = true;
			if(oldBlock == newBlock) return .no;
			if(oldBlock.typ == newBlock.typ) return .yes;
			if(oldBlock.solid()) {
				var damage: f32 = 1;
				const isTool = item.item != null and item.item.? == .tool;
				if(isTool) {
					damage = item.item.?.tool.getBlockDamage(oldBlock);
				}
				damage -= oldBlock.blockResistance();
				if(damage > 0) {
					if(isTool) {
						return .{.yes_costsDurability = @intFromFloat(@ceil(oldBlock.blockHealth()/damage))};
					} else return .yes;
				}
			} else {
				if(item.item) |_item| {
					if(_item == .baseItem) {
						if(_item.baseItem.block != null and _item.baseItem.block.? == newBlock.typ) {
							return .{.yes_costsItems = 1};
						}
					}
				}
				if(newBlock.typ == 0) {
					return .yes;
				}
			}
			return .no;
		}
	};

	pub const CanBeChangedInto = union(enum) {
		no: void,
		yes: void,
		yes_costsDurability: u16,
		yes_costsItems: u16,
		yes_dropsItems: u16,
	};

	/// if the block should be destroyed or changed when a certain neighbor is removed.
	dependsOnNeighbors: bool = false,

	/// The default rotation data intended for generation algorithms
	naturalStandard: u16 = 0,

	model: *const fn(block: Block) u16 = &DefaultFunctions.model,

	createBlockModel: *const fn(zon: ZonElement) u16 = &DefaultFunctions.createBlockModel,

	/// Updates the block data of a block in the world or places a block in the world.
	/// return true if the placing was successful, false otherwise.
	generateData: *const fn(world: *main.game.World, pos: Vec3i, relativePlayerPos: Vec3f, playerDir: Vec3f, relativeDir: Vec3i, neighbor: ?Neighbor, currentData: *Block, neighborBlock: Block, blockPlacing: bool) bool = DefaultFunctions.generateData,

	/// Updates data of a placed block if the RotationMode dependsOnNeighbors.
	updateData: *const fn(block: *Block, neighbor: Neighbor, neighborBlock: Block) bool = &DefaultFunctions.updateData,

	modifyBlock: *const fn(block: *Block, newType: u16) bool = DefaultFunctions.modifyBlock,

	rayIntersection: *const fn(block: Block, item: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f) ?RayIntersectionResult = &DefaultFunctions.rayIntersection,

	onBlockBreaking: *const fn(item: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f, currentData: *Block) void = &DefaultFunctions.onBlockBreaking,

	canBeChangedInto: *const fn(oldBlock: Block, newBlock: Block, item: main.items.ItemStack, shouldDropSourceBlockOnSuccess: *bool) CanBeChangedInto = DefaultFunctions.canBeChangedInto,
};

var rotationModes: std.StringHashMap(RotationMode) = undefined;

fn rotationMatrixTransform(quad: *main.models.QuadInfo, transformMatrix: Mat4f) void {
	quad.normal = vec.xyz(Mat4f.mulVec(transformMatrix, vec.combine(quad.normal, 0)));
	for(&quad.corners) |*corner| {
		corner.* = vec.xyz(Mat4f.mulVec(transformMatrix, vec.combine(corner.* - Vec3f{0.5, 0.5, 0.5}, 1))) + Vec3f{0.5, 0.5, 0.5};
	}
}

pub const RotationModes = struct {
	pub const NoRotation = struct { // MARK: NoRotation
		pub const id: []const u8 = "no_rotation";
		fn init() void {}
		fn deinit() void {}
		fn reset() void {}
	};
	pub const Log = struct { // MARK: Log
		pub const id: []const u8 = "log";
		var rotatedModels: std.StringHashMap(u16) = undefined;

		fn init() void {
			rotatedModels = .init(main.globalAllocator.allocator);
		}

		fn deinit() void {
			rotatedModels.deinit();
		}

		fn reset() void {
			rotatedModels.clearRetainingCapacity();
		}

		pub fn createBlockModel(zon: ZonElement) u16 {
			const modelId = zon.as([]const u8, "cubyz:cube");
			if(rotatedModels.get(modelId)) |modelIndex| return modelIndex;

			const baseModelIndex = main.models.getModelIndex(modelId);
			const baseModel = main.models.models.items[baseModelIndex];
			// Rotate the model:
			const modelIndex: u16 = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.identity()});
			_ = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.rotationY(std.math.pi)});
			_ = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.rotationZ(-std.math.pi/2.0).mul(Mat4f.rotationX(-std.math.pi/2.0))});
			_ = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.rotationZ(std.math.pi/2.0).mul(Mat4f.rotationX(-std.math.pi/2.0))});
			_ = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.rotationX(-std.math.pi/2.0)});
			_ = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.rotationZ(std.math.pi).mul(Mat4f.rotationX(-std.math.pi/2.0))});
			rotatedModels.put(modelId, modelIndex) catch unreachable;
			return modelIndex;
		}

		pub fn model(block: Block) u16 {
			return blocks.meshes.modelIndexStart(block) + @min(block.data, 5);
		}

		pub fn generateData(_: *main.game.World, _: Vec3i, _: Vec3f, _: Vec3f, _: Vec3i, neighbor: ?Neighbor, currentData: *Block, _: Block, blockPlacing: bool) bool {
			if(blockPlacing) {
				currentData.data = neighbor.?.reverse().toInt();
				return true;
			}
			return false;
		}
	};
	pub const Planar = struct { // MARK: Planar
		pub const id: []const u8 = "planar";
		var rotatedModels: std.StringHashMap(u16) = undefined;

		fn init() void {
			rotatedModels = .init(main.globalAllocator.allocator);
		}

		fn deinit() void {
			rotatedModels.deinit();
		}

		fn reset() void {
			rotatedModels.clearRetainingCapacity();
		}

		pub fn createBlockModel(zon: ZonElement) u16 {
			const modelId = zon.as([]const u8, "cubyz:cube");
			if(rotatedModels.get(modelId)) |modelIndex| return modelIndex;

			const baseModelIndex = main.models.getModelIndex(modelId);
			const baseModel = main.models.models.items[baseModelIndex];
			// Rotate the model:
			const modelIndex: u16 = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.rotationZ(std.math.pi/2.0)});
			_ = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.rotationZ(-std.math.pi/2.0)});
			_ = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.rotationZ(std.math.pi)});
			_ = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.identity()});
			rotatedModels.put(modelId, modelIndex) catch unreachable;
			return modelIndex;
		}

		pub fn model(block: Block) u16 {
			return blocks.meshes.modelIndexStart(block) + @min(block.data, 3);
		}

		pub fn generateData(_: *main.game.World, _: Vec3i, _: Vec3f, playerDir: Vec3f, _: Vec3i, _: ?Neighbor, currentData: *Block, _: Block, blockPlacing: bool) bool {
			if(blockPlacing) {
				if(@abs(playerDir[0]) > @abs(playerDir[1])) {
					const dir: Neighbor = if(playerDir[0] < 0) .dirNegX else .dirPosX;
					currentData.data = dir.toInt() - 2;
				} else {
					const dir: Neighbor = if(playerDir[1] < 0) .dirNegY else .dirPosY;
					currentData.data = dir.toInt() - 2;
				}
				return true;
			}
			return false;
		}
	};
	pub const Fence = struct { // MARK: Fence
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
			fenceModels = .init(main.globalAllocator.allocator);
		}

		fn deinit() void {
			fenceModels.deinit();
		}

		fn reset() void {
			fenceModels.clearRetainingCapacity();
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
					if(@abs(quad.normal[2]) > 0.7) {
						cornerUV[1] = 0.5;
					} else {
						cornerUV[0] = 0.5;
					}
				}
				if(!data.isConnectedPosY and corner[1] == 1) {
					corner[1] = 0.5;
					if(@abs(quad.normal[2]) > 0.7) {
						cornerUV[1] = 0.5;
					} else {
						cornerUV[0] = 0.5;
					}
				}
			}
		}

		pub fn createBlockModel(zon: ZonElement) u16 {
			const modelId = zon.as([]const u8, "cubyz:cube");
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

		pub fn updateData(block: *Block, neighbor: Neighbor, neighborBlock: Block) bool {
			const blockBaseModel = blocks.meshes.modelIndexStart(block.*);
			const neighborBaseModel = blocks.meshes.modelIndexStart(neighborBlock);
			const neighborModel = blocks.meshes.model(neighborBlock);
			const targetVal = neighborBlock.solid() and (blockBaseModel == neighborBaseModel or main.models.models.items[neighborModel].isNeighborOccluded[neighbor.reverse().toInt()]);
			var currentData: FenceData = @bitCast(@as(u4, @truncate(block.data)));
			switch(neighbor) {
				.dirNegX => {
					currentData.isConnectedNegX = targetVal;
				},
				.dirPosX => {
					currentData.isConnectedPosX = targetVal;
				},
				.dirNegY => {
					currentData.isConnectedNegY = targetVal;
				},
				.dirPosY => {
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
	pub const Branch = struct { // MARK: Branch
		pub const id: []const u8 = "branch";
		pub const dependsOnNeighbors = true;
		var branchModels: std.StringHashMap(u16) = undefined;
		const BranchData = packed struct(u6) {
			enabledConnections: u6,

			pub fn init(blockData: u16) BranchData {
				return .{.enabledConnections = @truncate(blockData)};
			}

			pub fn isConnected(self: @This(), neighbor: Neighbor) bool {
				return (self.enabledConnections & Neighbor.bitMask(neighbor)) != 0;
			}

			pub fn setConnection(self: *@This(), neighbor: Neighbor, value: bool) void {
				if(value) {
					self.enabledConnections |= Neighbor.bitMask(neighbor);
				} else {
					self.enabledConnections &= ~Neighbor.bitMask(neighbor);
				}
			}
		};

		fn init() void {
			branchModels = .init(main.globalAllocator.allocator);
		}

		fn deinit() void {
			branchModels.deinit();
		}

		fn reset() void {
			branchModels.clearRetainingCapacity();
		}

		fn branchTransform(quad: *main.models.QuadInfo, data: BranchData) void {
			for(&quad.corners) |*corner| {
				if((!data.isConnected(Neighbor.dirNegX) and corner[0] == 0) or
					(!data.isConnected(Neighbor.dirPosX) and corner[0] == 1) or
					(!data.isConnected(Neighbor.dirNegY) and corner[1] == 0) or
					(!data.isConnected(Neighbor.dirPosY) and corner[1] == 1) or
					(!data.isConnected(Neighbor.dirDown) and corner[2] == 0) or
					(!data.isConnected(Neighbor.dirUp) and corner[2] == 1)) return degenerateQuad(quad);
			}
		}

		fn degenerateQuad(quad: *main.models.QuadInfo) void {
			for(&quad.corners) |*corner| {
				corner.* = @splat(0.5);
			}
		}

		pub fn createBlockModel(zon: ZonElement) u16 {
			const modelId = zon.as([]const u8, "cubyz:cube");
			if(branchModels.get(modelId)) |modelIndex| return modelIndex;

			const baseModelIndex = main.models.getModelIndex(modelId);
			const baseModel = main.models.models.items[baseModelIndex];

			const modelIndex: u16 = baseModel.transformModel(branchTransform, .{BranchData.init(0)});
			for(1..64) |branchData| {
				_ = baseModel.transformModel(branchTransform, .{BranchData.init(@truncate(branchData))});
			}
			branchModels.put(modelId, modelIndex) catch unreachable;
			return modelIndex;
		}

		pub fn model(block: Block) u16 {
			return blocks.meshes.modelIndexStart(block) + (block.data & 63);
		}

		pub fn generateData(
			_: *main.game.World,
			_: Vec3i,
			_: Vec3f,
			_: Vec3f,
			_: Vec3i,
			neighbor: ?Neighbor,
			currentBlock: *Block,
			neighborBlock: Block,
			blockPlacing: bool,
		) bool {
			const blockBaseModel = blocks.meshes.modelIndexStart(currentBlock.*);
			const neighborBaseModel = blocks.meshes.modelIndexStart(neighborBlock);

			if(blockPlacing or blockBaseModel == neighborBaseModel or neighborBlock.solid()) {
				const neighborModel = blocks.meshes.model(neighborBlock);

				var currentData = BranchData.init(currentBlock.data);
				// Branch block upon placement should extend towards a block it was placed
				// on if the block is solid or also uses branch model.
				const targetVal = ((neighborBlock.solid() and !neighborBlock.viewThrough()) and (blockBaseModel == neighborBaseModel or main.models.models.items[neighborModel].isNeighborOccluded[neighbor.?.reverse().toInt()]));
				currentData.setConnection(neighbor.?, targetVal);

				const result: u16 = currentData.enabledConnections;
				if(result == currentBlock.data) return false;

				currentBlock.data = result;
				return true;
			}
			return false;
		}

		pub fn updateData(block: *Block, neighbor: Neighbor, neighborBlock: Block) bool {
			const blockBaseModel = blocks.meshes.modelIndexStart(block.*);
			const neighborBaseModel = blocks.meshes.modelIndexStart(neighborBlock);
			var currentData = BranchData.init(block.data);

			// Handle joining with other branches. While placed, branches extend in a
			// opposite direction than they were placed from, effectively connecting
			// to the block they were placed at.
			if(blockBaseModel == neighborBaseModel) {
				const neighborData = BranchData.init(neighborBlock.data);
				currentData.setConnection(neighbor, neighborData.isConnected(neighbor.reverse()));
			} else if(!neighborBlock.solid()) {
				currentData.setConnection(neighbor, false);
			}

			const result: u16 = currentData.enabledConnections;
			if(result == block.data) return false;

			block.data = result;
			return true;
		}

		fn closestRay(block: Block, relativePlayerPos: Vec3f, playerDir: Vec3f) ?u16 {
			var closestIntersectionDistance: f64 = std.math.inf(f64);
			var resultBitMask: ?u16 = null;
			{
				const modelIndex = blocks.meshes.modelIndexStart(block);
				if(RotationMode.DefaultFunctions.rayModelIntersection(modelIndex, relativePlayerPos, playerDir)) |intersection| {
					closestIntersectionDistance = intersection.distance;
					resultBitMask = 0;
				}
			}
			for(Neighbor.iterable) |direction| {
				const directionBitMask = Neighbor.bitMask(direction);

				if((block.data & directionBitMask) != 0) {
					const modelIndex = blocks.meshes.modelIndexStart(block) + directionBitMask;
					if(RotationMode.DefaultFunctions.rayModelIntersection(modelIndex, relativePlayerPos, playerDir)) |intersection| {
						if(@abs(closestIntersectionDistance) > @abs(intersection.distance)) {
							closestIntersectionDistance = intersection.distance;
							resultBitMask = direction.bitMask();
						}
					}
				}
			}
			return resultBitMask;
		}

		pub fn onBlockBreaking(_: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f, currentData: *Block) void {
			if(closestRay(currentData.*, relativePlayerPos, playerDir)) |directionBitMask| {
				// If player destroys a central part of branch block, branch block is completely destroyed.
				if(directionBitMask == 0) {
					currentData.typ = 0;
					currentData.data = 0;
					return;
				}
				// Otherwise only the connection player aimed at is destroyed.
				currentData.data &= ~directionBitMask;
			}
		}
	};
	pub const Pipe = struct { // MARK: Pipe
		pub const id: []const u8 = "pipe";
		pub const dependsOnNeighbors = true;
		var modelIndex: u16 = undefined;
		const BranchData = packed struct(u6) {
			enabledConnections: u6,

			pub fn init(blockData: u16) BranchData {
				return .{.enabledConnections = @truncate(blockData)};
			}

			pub fn isConnected(self: @This(), neighbor: Neighbor) bool {
				return (self.enabledConnections & Neighbor.bitMask(neighbor)) != 0;
			}

			pub fn setConnection(self: *@This(), neighbor: Neighbor, value: bool) void {
				if(value) {
					self.enabledConnections |= Neighbor.bitMask(neighbor);
				} else {
					self.enabledConnections &= ~Neighbor.bitMask(neighbor);
				}
			}
		};

		fn init() void {
			modelIndex = 0;
		}

		fn deinit() void {}

		const PatternType = enum(u3) {
			dot = 0,
			halfLine = 1,
			line = 2,
			bend = 3,
			intersection = 4,
			cross = 5,
		};

		const Pattern = union(PatternType) {
			dot: void,
			halfLine: struct {
				dir: u2,
			},
			line: struct {
				dir: u2,
			},
			bend: struct {
				dir: u2,
			},
			intersection: struct {
				dir: u2,
			},
			cross: void,
		};

		fn rotateQuad(originalCorners: [4]Vec2f, pattern: Pattern, side: Neighbor) main.models.QuadInfo {
			var corners: [4]Vec2f = originalCorners;

			switch(pattern) {
				.dot, .cross => {},
				inline else => |typ| {
					const angle: f32 = @as(f32, @floatFromInt(typ.dir))*std.math.pi/2.0;
					corners = .{
						vec.rotate2d(originalCorners[0], angle, @splat(0.5)),
						vec.rotate2d(originalCorners[1], angle, @splat(0.5)),
						vec.rotate2d(originalCorners[2], angle, @splat(0.5)),
						vec.rotate2d(originalCorners[3], angle, @splat(0.5)),
					};
				}
			}

			const offX: f32 = if(side.textureX()[([6]usize{0, 0, 1, 1, 0, 0})[@intFromEnum(side)]] < 0) 1 else 0;
			const offY: f32 = if(side.textureY()[([6]usize{1, 1, 2, 2, 2, 2})[@intFromEnum(side)]] < 0) 1 else 0;

			const norm: Vec3f = switch(side) {
				Neighbor.dirUp => .{0.0, 0.0, 1.0},
				Neighbor.dirDown => .{0.0, 0.0, -1.0},
				Neighbor.dirPosX => .{1.0, 0.0, 0.0},
				Neighbor.dirNegX => .{-1.0, 0.0, 0.0},
				Neighbor.dirPosY => .{0.0, 1.0, 0.0},
				Neighbor.dirNegY => .{0.0, -1.0, 0.0},
			};

			const corns = .{
				@as(Vec3f, @floatFromInt(side.textureX()))*@as(Vec3f, @splat(corners[0][0] - offX)) + @as(Vec3f, @floatFromInt(side.textureY()))*@as(Vec3f, @splat(corners[0][1] - offY)),
				@as(Vec3f, @floatFromInt(side.textureX()))*@as(Vec3f, @splat(corners[1][0] - offX)) + @as(Vec3f, @floatFromInt(side.textureY()))*@as(Vec3f, @splat(corners[1][1] - offY)),
				@as(Vec3f, @floatFromInt(side.textureX()))*@as(Vec3f, @splat(corners[2][0] - offX)) + @as(Vec3f, @floatFromInt(side.textureY()))*@as(Vec3f, @splat(corners[2][1] - offY)),
				@as(Vec3f, @floatFromInt(side.textureX()))*@as(Vec3f, @splat(corners[3][0] - offX)) + @as(Vec3f, @floatFromInt(side.textureY()))*@as(Vec3f, @splat(corners[3][1] - offY)),
			};

			const tex: u32 = @intCast(@intFromEnum(pattern));

			var offset: Vec3f = .{0.0, 0.0, 0.0};
			offset[@intFromEnum(side.vectorComponent())] = if(side.isPositive()) 12.0/16.0 else 4.0/16.0;

			const res: main.models.QuadInfo = .{
				.corners = .{
					corns[0] + offset,
					corns[1] + offset,
					corns[2] + offset,
					corns[3] + offset,
				},
				.cornerUV = originalCorners,
				.normal = norm,
				.opaqueInLod = 1,
				.textureSlot = tex,
			};

			return res;
		}

		fn addQuads(pattern: Pattern, side: Neighbor, out: *main.List(main.models.QuadInfo)) void {
			switch(pattern) {
				.dot => {
					out.append(rotateQuad(.{
						.{0.25, 0.25},
						.{0.25, 0.75},
						.{0.75, 0.25},
						.{0.75, 0.75},
					}, pattern, side));
				},
				.halfLine => {
					out.append(rotateQuad(.{
						.{0.25, 0.0},
						.{0.25, 0.75},
						.{0.75, 0.0},
						.{0.75, 0.75},
					}, pattern, side));
				},
				.line => {
					out.append(rotateQuad(.{
						.{0.25, 0.0},
						.{0.25, 1.0},
						.{0.75, 0.0},
						.{0.75, 1.0},
					}, pattern, side));
				},
				.bend => {
					out.append(rotateQuad(.{
						.{0.0, 0.0},
						.{0.0, 0.75},
						.{0.75, 0.0},
						.{0.75, 0.75},
					}, pattern, side));
				},
				.intersection => {
					out.append(rotateQuad(.{
						.{0.0, 0.0},
						.{0.0, 0.75},
						.{1.0, 0.0},
						.{1.0, 0.75},
					}, pattern, side));
				},
				.cross => {
					out.append(rotateQuad(.{
						.{0.0, 0.0},
						.{0.0, 1.0},
						.{1.0, 0.0},
						.{1.0, 1.0},
					}, pattern, side));
				},
			}
		}

		fn getPattern(data: BranchData, side: Neighbor) ?Pattern {
			const a = Neighbor.fromRelPos(side.textureX()).?;
			const b = Neighbor.fromRelPos(side.textureX()).?.reverse();
			const c = Neighbor.fromRelPos(side.textureY()).?;
			const d = Neighbor.fromRelPos(side.textureY()).?.reverse();

			const aVal: u6 = if(data.isConnected(a)) 1 else 0;
			const bVal: u6 = if(data.isConnected(b)) 1 else 0;
			const cVal: u6 = if(data.isConnected(c)) 1 else 0;
			const dVal: u6 = if(data.isConnected(d)) 1 else 0;

			const res: u6 = dVal << 3 | cVal << 2 | bVal << 1 | aVal;

			const count: u6 = aVal + bVal + cVal + dVal;

			return switch(count) {
				0 => {
					if(data.isConnected(side)) {
						return null;
					}

					return .{.dot = {}};
				},
				1 => {
					var dir: u2 = 3;
					if(dVal == 1) {
						dir = 0;
					} else if(aVal == 1) {
						dir = 1;
					} else if(cVal == 1) {
						dir = 2;
					}
					return .{.halfLine = .{.dir = dir}};
				},
				2 => {
					if(res == 3 or res == 12) {
						var dir: u2 = 0;
						if(res == 3) {
							dir = 1;
						}

						return .{.line = .{.dir = dir}};
					}

					var dir: u2 = 3;

					if(dVal == 1) {
						dir = 0;
					}

					if(dVal == 1) {
						dir = 0;
						if(aVal == 1) {
							dir = 1;
						}
					} else if(aVal == 1) {
						dir = 1;
						if(cVal == 1) {
							dir = 2;
						}
					} else if(cVal == 1) {
						dir = 2;
						if(bVal == 1) {
							dir = 3;
						}
					}

					return .{.bend = .{.dir = dir}};
				},
				3 => {
					const dir: u2 = switch(res) {
						0b0111 => 2,
						0b1110 => 3,
						0b1101 => 1,
						0b1011 => 0,
						else => undefined,
					};

					return .{.intersection = .{.dir = dir}};
				},
				4 => {
					return .{.cross = {}};
				},
				else => undefined,
			};
		}

		pub fn createBlockModel(_: ZonElement) u16 {
			if(modelIndex != 0) {
				return modelIndex;
			}

			for(0..64) |i| {
				var quads = main.List(main.models.QuadInfo).init(main.stackAllocator);
				defer quads.deinit();

				for(Neighbor.iterable) |neighbor| {
					const pattern = getPattern(BranchData.init(@intCast(i)), neighbor);

					if(pattern) |pat| {
						addQuads(pat, neighbor, &quads);
					}
				}

				const index = main.models.Model.init(quads.items);
				if(i == 0) {
					modelIndex = index;
				}
			}

			return modelIndex;
		}

		pub fn model(block: Block) u16 {
			return blocks.meshes.modelIndexStart(block) + (block.data & 63);
		}

		pub fn generateData(
			_: *main.game.World,
			_: Vec3i,
			_: Vec3f,
			_: Vec3f,
			_: Vec3i,
			neighbor: ?Neighbor,
			currentBlock: *Block,
			neighborBlock: Block,
			blockPlacing: bool,
		) bool {
			const blockBaseModel = blocks.meshes.modelIndexStart(currentBlock.*);
			const neighborBaseModel = blocks.meshes.modelIndexStart(neighborBlock);

			if(blockPlacing or blockBaseModel == neighborBaseModel or neighborBlock.solid()) {
				const neighborModel = blocks.meshes.model(neighborBlock);

				var currentData = BranchData.init(currentBlock.data);
				// Branch block upon placement should extend towards a block it was placed
				// on if the block is solid or also uses branch model.
				const targetVal = ((neighborBlock.solid() and !neighborBlock.viewThrough()) and (blockBaseModel == neighborBaseModel or main.models.models.items[neighborModel].isNeighborOccluded[neighbor.?.reverse().toInt()]));
				currentData.setConnection(neighbor.?, targetVal);

				const result: u16 = currentData.enabledConnections;
				if(result == currentBlock.data) return false;

				currentBlock.data = result;
				return true;
			}
			return false;
		}

		pub fn updateData(block: *Block, neighbor: Neighbor, neighborBlock: Block) bool {
			const blockBaseModel = blocks.meshes.modelIndexStart(block.*);
			const neighborBaseModel = blocks.meshes.modelIndexStart(neighborBlock);
			var currentData = BranchData.init(block.data);

			// Handle joining with other branches. While placed, branches extend in a
			// opposite direction than they were placed from, effectively connecting
			// to the block they were placed at.
			if(blockBaseModel == neighborBaseModel) {
				const neighborData = BranchData.init(neighborBlock.data);
				currentData.setConnection(neighbor, neighborData.isConnected(neighbor.reverse()));
			} else if(!neighborBlock.solid()) {
				currentData.setConnection(neighbor, false);
			}

			const result: u16 = currentData.enabledConnections;
			if(result == block.data) return false;

			block.data = result;
			return true;
		}
	};
	pub const Stairs = struct { // MARK: Stairs
		pub const id: []const u8 = "stairs";
		var modelIndex: u16 = 0;

		fn subBlockMask(x: u1, y: u1, z: u1) u8 {
			return @as(u8, 1) << ((@as(u3, x)*2 + @as(u3, y))*2 + z);
		}
		fn hasSubBlock(stairData: u8, x: u1, y: u1, z: u1) bool {
			return stairData & subBlockMask(x, y, z) == 0;
		}

		fn init() void {}
		fn deinit() void {}
		fn reset() void {
			modelIndex = 0;
		}

		const GreedyFaceInfo = struct {min: Vec2f, max: Vec2f};
		fn mergeFaces(faceVisible: [2][2]bool, mem: []GreedyFaceInfo) []GreedyFaceInfo {
			var faces: usize = 0;
			if(faceVisible[0][0]) {
				if(faceVisible[0][1]) {
					if(faceVisible[1][0] and faceVisible[1][1]) {
						// One big face:
						mem[faces] = .{.min = .{0, 0}, .max = .{1, 1}};
						faces += 1;
					} else {
						mem[faces] = .{.min = .{0, 0}, .max = .{0.5, 1}};
						faces += 1;
						if(faceVisible[1][0]) {
							mem[faces] = .{.min = .{0.5, 0}, .max = .{1, 0.5}};
							faces += 1;
						}
						if(faceVisible[1][1]) {
							mem[faces] = .{.min = .{0.5, 0.5}, .max = .{1, 1}};
							faces += 1;
						}
					}
				} else {
					if(faceVisible[1][0]) {
						mem[faces] = .{.min = .{0, 0}, .max = .{1.0, 0.5}};
						faces += 1;
					} else {
						mem[faces] = .{.min = .{0, 0}, .max = .{0.5, 0.5}};
						faces += 1;
					}
					if(faceVisible[1][1]) {
						mem[faces] = .{.min = .{0.5, 0.5}, .max = .{1, 1}};
						faces += 1;
					}
				}
			} else {
				if(faceVisible[0][1]) {
					if(faceVisible[1][1]) {
						mem[faces] = .{.min = .{0, 0.5}, .max = .{1, 1}};
						faces += 1;
					} else {
						mem[faces] = .{.min = .{0, 0.5}, .max = .{0.5, 1}};
						faces += 1;
					}
					if(faceVisible[1][0]) {
						mem[faces] = .{.min = .{0.5, 0}, .max = .{1, 0.5}};
						faces += 1;
					}
				} else {
					if(faceVisible[1][0]) {
						if(faceVisible[1][1]) {
							mem[faces] = .{.min = .{0.5, 0}, .max = .{1, 1.0}};
							faces += 1;
						} else {
							mem[faces] = .{.min = .{0.5, 0}, .max = .{1, 0.5}};
							faces += 1;
						}
					} else if(faceVisible[1][1]) {
						mem[faces] = .{.min = .{0.5, 0.5}, .max = .{1, 1}};
						faces += 1;
					}
				}
			}
			return mem[0..faces];
		}

		pub fn createBlockModel(_: ZonElement) u16 {
			if(modelIndex != 0) {
				return modelIndex;
			}
			for(0..256) |i| {
				var quads = main.List(main.models.QuadInfo).init(main.stackAllocator);
				defer quads.deinit();
				for(Neighbor.iterable) |neighbor| {
					const xComponent = @abs(neighbor.textureX());
					const yComponent = @abs(neighbor.textureY());
					const normal = Vec3i{neighbor.relX(), neighbor.relY(), neighbor.relZ()};
					const zComponent = @abs(normal);
					const zMap: [2]@Vector(3, u32) = if(@reduce(.Add, normal) > 0) .{@splat(0), @splat(1)} else .{@splat(1), @splat(0)};
					var visibleFront: [2][2]bool = undefined;
					var visibleMiddle: [2][2]bool = undefined;
					for(0..2) |x| {
						for(0..2) |y| {
							const xSplat: @TypeOf(xComponent) = @splat(@intCast(x));
							const ySplat: @TypeOf(xComponent) = @splat(@intCast(y));
							const posFront = xComponent*xSplat + yComponent*ySplat + zComponent*zMap[1];
							const posBack = xComponent*xSplat + yComponent*ySplat + zComponent*zMap[0];
							visibleFront[x][y] = hasSubBlock(@intCast(i), @intCast(posFront[0]), @intCast(posFront[1]), @intCast(posFront[2]));
							visibleMiddle[x][y] = !visibleFront[x][y] and hasSubBlock(@intCast(i), @intCast(posBack[0]), @intCast(posBack[1]), @intCast(posBack[2]));
						}
					}
					const xAxis = @as(Vec3f, @floatFromInt(neighbor.textureX()));
					const yAxis = @as(Vec3f, @floatFromInt(neighbor.textureY()));
					const zAxis = @as(Vec3f, @floatFromInt(normal));
					// Greedy mesh it:
					var faces: [2]GreedyFaceInfo = undefined;
					const frontFaces = mergeFaces(visibleFront, &faces);
					for(frontFaces) |*face| {
						var xLower = @abs(xAxis)*@as(Vec3f, @splat(face.min[0]));
						var xUpper = @abs(xAxis)*@as(Vec3f, @splat(face.max[0]));
						if(@reduce(.Add, xAxis) < 0) std.mem.swap(Vec3f, &xLower, &xUpper);
						var yLower = @abs(yAxis)*@as(Vec3f, @splat(face.min[1]));
						var yUpper = @abs(yAxis)*@as(Vec3f, @splat(face.max[1]));
						if(@reduce(.Add, yAxis) < 0) std.mem.swap(Vec3f, &yLower, &yUpper);
						const zValue: Vec3f = @floatFromInt(zComponent*zMap[1]);
						if(neighbor == .dirNegX or neighbor == .dirPosY) {
							face.min[0] = 1 - face.min[0];
							face.max[0] = 1 - face.max[0];
							const swap = face.min[0];
							face.min[0] = face.max[0];
							face.max[0] = swap;
						}
						if(neighbor == .dirUp) {
							face.min = Vec2f{1, 1} - face.min;
							face.max = Vec2f{1, 1} - face.max;
							std.mem.swap(Vec2f, &face.min, &face.max);
						}
						if(neighbor == .dirDown) {
							face.min[1] = 1 - face.min[1];
							face.max[1] = 1 - face.max[1];
							const swap = face.min[1];
							face.min[1] = face.max[1];
							face.max[1] = swap;
						}
						quads.append(.{
							.normal = zAxis,
							.corners = .{
								xLower + yLower + zValue,
								xLower + yUpper + zValue,
								xUpper + yLower + zValue,
								xUpper + yUpper + zValue,
							},
							.cornerUV = .{.{face.min[0], face.min[1]}, .{face.min[0], face.max[1]}, .{face.max[0], face.min[1]}, .{face.max[0], face.max[1]}},
							.textureSlot = neighbor.toInt(),
						});
					}
					const middleFaces = mergeFaces(visibleMiddle, &faces);
					for(middleFaces) |*face| {
						var xLower = @abs(xAxis)*@as(Vec3f, @splat(face.min[0]));
						var xUpper = @abs(xAxis)*@as(Vec3f, @splat(face.max[0]));
						if(@reduce(.Add, xAxis) < 0) std.mem.swap(Vec3f, &xLower, &xUpper);
						var yLower = @abs(yAxis)*@as(Vec3f, @splat(face.min[1]));
						var yUpper = @abs(yAxis)*@as(Vec3f, @splat(face.max[1]));
						if(@reduce(.Add, yAxis) < 0) std.mem.swap(Vec3f, &yLower, &yUpper);
						const zValue = @as(Vec3f, @floatFromInt(zComponent))*@as(Vec3f, @splat(0.5));
						if(neighbor == .dirNegX or neighbor == .dirPosY) {
							face.min[0] = 1 - face.min[0];
							face.max[0] = 1 - face.max[0];
							const swap = face.min[0];
							face.min[0] = face.max[0];
							face.max[0] = swap;
						}
						if(neighbor == .dirUp) {
							face.min = Vec2f{1, 1} - face.min;
							face.max = Vec2f{1, 1} - face.max;
							std.mem.swap(Vec2f, &face.min, &face.max);
						}
						if(neighbor == .dirDown) {
							face.min[1] = 1 - face.min[1];
							face.max[1] = 1 - face.max[1];
							const swap = face.min[1];
							face.min[1] = face.max[1];
							face.max[1] = swap;
						}
						quads.append(.{
							.normal = zAxis,
							.corners = .{
								xLower + yLower + zValue,
								xLower + yUpper + zValue,
								xUpper + yLower + zValue,
								xUpper + yUpper + zValue,
							},
							.cornerUV = .{.{face.min[0], face.min[1]}, .{face.min[0], face.max[1]}, .{face.max[0], face.min[1]}, .{face.max[0], face.max[1]}},
							.textureSlot = neighbor.toInt(),
						});
					}
				}
				const index = main.models.Model.init(quads.items);
				if(i == 0) {
					modelIndex = index;
				}
			}
			return modelIndex;
		}

		pub fn model(block: Block) u16 {
			return blocks.meshes.modelIndexStart(block) + (block.data & 255);
		}

		pub fn generateData(_: *main.game.World, _: Vec3i, _: Vec3f, _: Vec3f, _: Vec3i, _: ?Neighbor, currentData: *Block, _: Block, blockPlacing: bool) bool {
			if(blockPlacing) {
				currentData.data = 0;
				return true;
			}
			return false;
		}

		fn intersectHalfUnitBox(start: Vec3f, invDir: Vec3f) ?f32 {
			const t0 = start*invDir;
			const t1 = (start + Vec3f{0.5, 0.5, 0.5})*invDir;
			const entry = @reduce(.Max, @min(t0, t1));
			const exit = @reduce(.Min, @max(t0, t1));
			if(entry > exit or exit < 0) {
				return null;
			} else return entry;
		}

		fn intersectionPos(block: Block, relativePlayerPos: Vec3f, playerDir: Vec3f) ?struct {minT: f32, minPos: @Vector(3, u1)} {
			const invDir = @as(Vec3f, @splat(1))/playerDir;
			const relPos: Vec3f = @floatCast(-relativePlayerPos);
			const data: u8 = @truncate(block.data);
			var minT: f32 = std.math.floatMax(f32);
			var minPos: @Vector(3, u1) = undefined;
			for(0..8) |i| {
				const subPos: @Vector(3, u1) = .{
					@truncate(i >> 2),
					@truncate(i >> 1),
					@truncate(i),
				};
				if(hasSubBlock(data, subPos[0], subPos[1], subPos[2])) {
					const relSubPos = relPos + @as(Vec3f, @floatFromInt(subPos))*@as(Vec3f, @splat(0.5));
					if(intersectHalfUnitBox(relSubPos, invDir)) |t| {
						if(t < minT) {
							minT = t;
							minPos = subPos;
						}
					}
				}
			}
			if(minT != std.math.floatMax(f32)) {
				return .{.minT = minT, .minPos = minPos};
			}
			return null;
		}

		pub fn rayIntersection(block: Block, item: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f) ?RayIntersectionResult {
			if(item) |_item| {
				switch(_item) {
					.baseItem => |baseItem| {
						if(std.mem.eql(u8, baseItem.id, "cubyz:chisel")) { // Select only one eigth of a block
							if(intersectionPos(block, relativePlayerPos, playerDir)) |intersection| {
								const offset: Vec3f = @floatFromInt(intersection.minPos);
								const half: Vec3f = @splat(0.5);
								return .{
									.distance = intersection.minT,
									.min = half*offset,
									.max = half + half*offset,
								};
							}
							return null;
						}
					},
					else => {},
				}
			}
			return RotationMode.DefaultFunctions.rayIntersection(block, item, relativePlayerPos, playerDir);
		}

		pub fn onBlockBreaking(item: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f, currentData: *Block) void {
			if(item) |_item| {
				switch(_item) {
					.baseItem => |baseItem| {
						if(std.mem.eql(u8, baseItem.id, "cubyz:chisel")) { // Break only one eigth of a block
							if(intersectionPos(currentData.*, relativePlayerPos, playerDir)) |intersection| {
								currentData.data = currentData.data | subBlockMask(intersection.minPos[0], intersection.minPos[1], intersection.minPos[2]);
								if(currentData.data == 255) currentData.* = .{.typ = 0, .data = 0};
								return;
							}
						}
					},
					else => {},
				}
			}
			return RotationMode.DefaultFunctions.onBlockBreaking(item, relativePlayerPos, playerDir, currentData);
		}

		pub fn canBeChangedInto(oldBlock: Block, newBlock: Block, item: main.items.ItemStack, shouldDropSourceBlockOnSuccess: *bool) RotationMode.CanBeChangedInto {
			if(oldBlock.typ != newBlock.typ) return RotationMode.DefaultFunctions.canBeChangedInto(oldBlock, newBlock, item, shouldDropSourceBlockOnSuccess);
			if(oldBlock.data == newBlock.data) return .no;
			if(item.item != null and item.item.? == .baseItem and std.mem.eql(u8, item.item.?.baseItem.id, "cubyz:chisel")) {
				return .yes; // TODO: Durability change, after making the chisel a proper tool.
			}
			return .no;
		}
	};
	pub const Torch = struct { // MARK: Torch
		pub const id: []const u8 = "torch";
		pub const naturalStandard: u16 = 1;
		pub const dependsOnNeighbors = true;
		var rotatedModels: std.StringHashMap(u16) = undefined;
		const TorchData = packed struct(u5) {
			center: bool,
			negX: bool,
			posX: bool,
			negY: bool,
			posY: bool,
		};

		fn init() void {
			rotatedModels = .init(main.globalAllocator.allocator);
		}

		fn deinit() void {
			rotatedModels.deinit();
		}

		fn reset() void {
			rotatedModels.clearRetainingCapacity();
		}

		pub fn createBlockModel(zon: ZonElement) u16 {
			const baseModelId: []const u8 = zon.get([]const u8, "base", "cubyz:cube");
			const sideModelId: []const u8 = zon.get([]const u8, "side", "cubyz:cube");
			const key: []const u8 = std.mem.concat(main.stackAllocator.allocator, u8, &.{baseModelId, sideModelId}) catch unreachable;
			defer main.stackAllocator.free(key);

			if(rotatedModels.get(key)) |modelIndex| return modelIndex;

			const baseModelIndex = main.models.getModelIndex(baseModelId);
			const baseModel = main.models.models.items[baseModelIndex];
			const sideModelIndex = main.models.getModelIndex(sideModelId);
			const sideModel = main.models.models.items[sideModelIndex];
			// Rotate the model:
			var centerModel: u16 = undefined;
			var negXModel: u16 = undefined;
			var posXModel: u16 = undefined;
			var negYModel: u16 = undefined;
			var posYModel: u16 = undefined;
			for(1..32) |i| {
				const torchData: TorchData = @bitCast(@as(u5, @intCast(i)));
				if(i & i - 1 == 0) {
					if(torchData.center) centerModel = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.identity()});
					if(torchData.negX) negXModel = sideModel.transformModel(rotationMatrixTransform, .{Mat4f.rotationZ(0)});
					if(torchData.posX) posXModel = sideModel.transformModel(rotationMatrixTransform, .{Mat4f.rotationZ(std.math.pi)});
					if(torchData.negY) negYModel = sideModel.transformModel(rotationMatrixTransform, .{Mat4f.rotationZ(std.math.pi/2.0)});
					if(torchData.posY) posYModel = sideModel.transformModel(rotationMatrixTransform, .{Mat4f.rotationZ(-std.math.pi/2.0)});
				} else {
					var models: [5]u16 = undefined;
					var amount: usize = 0;
					if(torchData.center) {
						models[amount] = centerModel;
						amount += 1;
					}
					if(torchData.negX) {
						models[amount] = negXModel;
						amount += 1;
					}
					if(torchData.posX) {
						models[amount] = posXModel;
						amount += 1;
					}
					if(torchData.negY) {
						models[amount] = negYModel;
						amount += 1;
					}
					if(torchData.posY) {
						models[amount] = posYModel;
						amount += 1;
					}
					_ = main.models.Model.mergeModels(models[0..amount]);
				}
			}
			const modelIndex = centerModel;
			rotatedModels.put(key, modelIndex) catch unreachable;
			return modelIndex;
		}

		pub fn model(block: Block) u16 {
			return blocks.meshes.modelIndexStart(block) + (@as(u5, @truncate(block.data)) -| 1);
		}

		pub fn generateData(_: *main.game.World, _: Vec3i, _: Vec3f, _: Vec3f, relativeDir: Vec3i, neighbor: ?Neighbor, currentData: *Block, neighborBlock: Block, _: bool) bool {
			if(neighbor == null) return false;
			const neighborModel = blocks.meshes.model(neighborBlock);
			const neighborSupport = neighborBlock.solid() and main.models.models.items[neighborModel].neighborFacingQuads[neighbor.?.reverse().toInt()].len != 0;
			if(!neighborSupport) return false;
			var data: TorchData = @bitCast(@as(u5, @truncate(currentData.data)));
			if(relativeDir[0] == 1) data.posX = true;
			if(relativeDir[0] == -1) data.negX = true;
			if(relativeDir[1] == 1) data.posY = true;
			if(relativeDir[1] == -1) data.negY = true;
			if(relativeDir[2] == -1) data.center = true;
			if(@as(u5, @bitCast(data)) != currentData.data) {
				currentData.data = @as(u5, @bitCast(data));
				return true;
			} else {
				return false;
			}
		}

		pub fn updateData(block: *Block, neighbor: Neighbor, neighborBlock: Block) bool {
			const neighborModel = blocks.meshes.model(neighborBlock);
			const neighborSupport = neighborBlock.solid() and main.models.models.items[neighborModel].neighborFacingQuads[neighbor.reverse().toInt()].len != 0;
			var currentData: TorchData = @bitCast(@as(u5, @truncate(block.data)));
			switch(neighbor) {
				.dirNegX => {
					currentData.negX = currentData.negX and neighborSupport;
				},
				.dirPosX => {
					currentData.posX = currentData.posX and neighborSupport;
				},
				.dirNegY => {
					currentData.negY = currentData.negY and neighborSupport;
				},
				.dirPosY => {
					currentData.posY = currentData.posY and neighborSupport;
				},
				.dirDown => {
					currentData.center = currentData.center and neighborSupport;
				},
				else => {},
			}
			const result: u16 = @as(u5, @bitCast(currentData));
			if(result == block.data) return false;
			block.data = result;
			if(result == 0) block.typ = 0;
			return true;
		}

		fn closestRay(comptime typ: enum {bit, intersection}, block: Block, _: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f) if(typ == .intersection) ?RayIntersectionResult else u16 {
			var result: ?RayIntersectionResult = null;
			var resultBit: u16 = 0;
			for([_]u16{1, 2, 4, 8, 16}) |bit| {
				if(block.data & bit != 0) {
					const modelIndex = blocks.meshes.modelIndexStart(block) + bit - 1;
					if(RotationMode.DefaultFunctions.rayModelIntersection(modelIndex, relativePlayerPos, playerDir)) |intersection| {
						if(result == null or result.?.distance > intersection.distance) {
							result = intersection;
							resultBit = bit;
						}
					}
				}
			}
			if(typ == .bit) return resultBit;
			return result;
		}

		pub fn rayIntersection(block: Block, item: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f) ?RayIntersectionResult {
			return closestRay(.intersection, block, item, relativePlayerPos, playerDir);
		}

		pub fn onBlockBreaking(item: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f, currentData: *Block) void {
			const bit = closestRay(.bit, currentData.*, item, relativePlayerPos, playerDir);
			currentData.data &= ~bit;
			if(currentData.data == 0) currentData.typ = 0;
		}

		pub fn canBeChangedInto(oldBlock: Block, newBlock: Block, item: main.items.ItemStack, shouldDropSourceBlockOnSuccess: *bool) RotationMode.CanBeChangedInto {
			switch(RotationMode.DefaultFunctions.canBeChangedInto(oldBlock, newBlock, item, shouldDropSourceBlockOnSuccess)) {
				.no, .yes_costsDurability, .yes_dropsItems => return .no,
				.yes, .yes_costsItems => {
					const torchAmountChange = @as(i32, @popCount(newBlock.data)) - if(oldBlock.typ == newBlock.typ) @as(i32, @popCount(oldBlock.data)) else 0;
					if(torchAmountChange <= 0) {
						return .{.yes_dropsItems = @intCast(-torchAmountChange)};
					} else {
						if(item.item == null or item.item.? != .baseItem or !std.meta.eql(item.item.?.baseItem.block, newBlock.typ)) return .no;
						return .{.yes_costsItems = @intCast(torchAmountChange)};
					}
				},
			}
		}
	};
	pub const Carpet = struct { // MARK: Carpet
		pub const id: []const u8 = "carpet";
		pub const naturalStandard: u16 = 0b10000;
		var rotatedModels: std.StringHashMap(u16) = undefined;
		const CarpetData = packed struct(u6) {
			negX: bool,
			posX: bool,
			negY: bool,
			posY: bool,
			negZ: bool,
			posZ: bool,
		};

		fn init() void {
			rotatedModels = .init(main.globalAllocator.allocator);
		}

		fn deinit() void {
			rotatedModels.deinit();
		}

		fn reset() void {
			rotatedModels.clearRetainingCapacity();
		}

		pub fn createBlockModel(zon: ZonElement) u16 {
			const modelId = zon.as([]const u8, "cubyz:cube");
			if(rotatedModels.get(modelId)) |modelIndex| return modelIndex;

			const baseModelIndex = main.models.getModelIndex(modelId);
			const baseModel = main.models.models.items[baseModelIndex];
			// Rotate the model:
			var negXModel: u16 = undefined;
			var posXModel: u16 = undefined;
			var negYModel: u16 = undefined;
			var posYModel: u16 = undefined;
			var negZModel: u16 = undefined;
			var posZModel: u16 = undefined;
			for(1..64) |i| {
				const carpetData: CarpetData = @bitCast(@as(u6, @intCast(i)));
				if(i & i - 1 == 0) {
					if(carpetData.negX) negXModel = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.rotationZ(-std.math.pi/2.0).mul(Mat4f.rotationX(-std.math.pi/2.0))});
					if(carpetData.posX) posXModel = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.rotationZ(std.math.pi/2.0).mul(Mat4f.rotationX(-std.math.pi/2.0))});
					if(carpetData.negY) negYModel = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.rotationX(-std.math.pi/2.0)});
					if(carpetData.posY) posYModel = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.rotationZ(std.math.pi).mul(Mat4f.rotationX(-std.math.pi/2.0))});
					if(carpetData.negZ) negZModel = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.identity()});
					if(carpetData.posZ) posZModel = baseModel.transformModel(rotationMatrixTransform, .{Mat4f.rotationY(std.math.pi)});
				} else {
					var models: [6]u16 = undefined;
					var amount: usize = 0;
					if(carpetData.negX) {
						models[amount] = negXModel;
						amount += 1;
					}
					if(carpetData.posX) {
						models[amount] = posXModel;
						amount += 1;
					}
					if(carpetData.negY) {
						models[amount] = negYModel;
						amount += 1;
					}
					if(carpetData.posY) {
						models[amount] = posYModel;
						amount += 1;
					}
					if(carpetData.negZ) {
						models[amount] = negZModel;
						amount += 1;
					}
					if(carpetData.posZ) {
						models[amount] = posZModel;
						amount += 1;
					}
					_ = main.models.Model.mergeModels(models[0..amount]);
				}
			}
			const modelIndex = negXModel;
			rotatedModels.put(modelId, modelIndex) catch unreachable;
			return modelIndex;
		}

		pub fn model(block: Block) u16 {
			return blocks.meshes.modelIndexStart(block) + (@as(u6, @truncate(block.data)) -| 1);
		}

		pub fn generateData(_: *main.game.World, _: Vec3i, relativePlayerPos: Vec3f, playerDir: Vec3f, relativeDir: Vec3i, _: ?Neighbor, currentData: *Block, neighbor: Block, _: bool) bool {
			if(neighbor.mode() == currentData.mode()) parallelPlacing: {
				const bit = closestRay(.bit, neighbor, null, relativePlayerPos - @as(Vec3f, @floatFromInt(relativeDir)), playerDir);
				const bitData: CarpetData = @bitCast(@as(u6, @truncate(bit)));
				if((bitData.negX or bitData.posX) and relativeDir[0] != 0) break :parallelPlacing;
				if((bitData.negY or bitData.posY) and relativeDir[1] != 0) break :parallelPlacing;
				if((bitData.negZ or bitData.posZ) and relativeDir[2] != 0) break :parallelPlacing;
				if(currentData.data & bit == bit) return false;
				currentData.data |= bit;
				return true;
			}
			var data: CarpetData = @bitCast(@as(u6, @truncate(currentData.data)));
			if(relativeDir[0] == 1) data.posX = true;
			if(relativeDir[0] == -1) data.negX = true;
			if(relativeDir[1] == 1) data.posY = true;
			if(relativeDir[1] == -1) data.negY = true;
			if(relativeDir[2] == 1) data.posZ = true;
			if(relativeDir[2] == -1) data.negZ = true;
			if(@as(u6, @bitCast(data)) != currentData.data) {
				currentData.data = @as(u6, @bitCast(data));
				return true;
			} else {
				return false;
			}
		}

		fn closestRay(comptime typ: enum {bit, intersection}, block: Block, _: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f) if(typ == .intersection) ?RayIntersectionResult else u16 {
			var result: ?RayIntersectionResult = null;
			var resultBit: u16 = 0;
			for([_]u16{1, 2, 4, 8, 16, 32}) |bit| {
				if(block.data & bit != 0) {
					const modelIndex = blocks.meshes.modelIndexStart(block) + bit - 1;
					if(RotationMode.DefaultFunctions.rayModelIntersection(modelIndex, relativePlayerPos, playerDir)) |intersection| {
						if(result == null or result.?.distance > intersection.distance) {
							result = intersection;
							resultBit = bit;
						}
					}
				}
			}
			if(typ == .bit) return resultBit;
			return result;
		}

		pub fn rayIntersection(block: Block, item: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f) ?RayIntersectionResult {
			return closestRay(.intersection, block, item, relativePlayerPos, playerDir);
		}

		pub fn onBlockBreaking(item: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f, currentData: *Block) void {
			const bit = closestRay(.bit, currentData.*, item, relativePlayerPos, playerDir);
			currentData.data &= ~bit;
			if(currentData.data == 0) currentData.typ = 0;
		}

		pub fn canBeChangedInto(oldBlock: Block, newBlock: Block, item: main.items.ItemStack, shouldDropSourceBlockOnSuccess: *bool) RotationMode.CanBeChangedInto {
			return Torch.canBeChangedInto(oldBlock, newBlock, item, shouldDropSourceBlockOnSuccess);
		}
	};
	pub const Ore = struct { // MARK: Ore
		pub const id: []const u8 = "ore";
		var modelCache: ?u16 = null;

		fn init() void {}
		fn deinit() void {}
		fn reset() void {
			modelCache = null;
		}

		pub fn createBlockModel(zon: ZonElement) u16 {
			const modelId = zon.as([]const u8, "cubyz:cube");
			if(!std.mem.eql(u8, modelId, "cubyz:cube")) {
				std.log.err("Ores can only be use on cube models.", .{modelId});
			}
			if(modelCache) |modelIndex| return modelIndex;

			const baseModelIndex = main.models.getModelIndex("cubyz:cube");
			const baseModel = main.models.models.items[baseModelIndex];
			var quadList = main.List(main.models.QuadInfo).init(main.stackAllocator);
			defer quadList.deinit();
			baseModel.getRawFaces(&quadList);
			const len = quadList.items.len;
			for(0..len) |i| {
				quadList.append(quadList.items[i]);
				quadList.items[i + len].textureSlot += 16;
				quadList.items[i].opaqueInLod = 2;
			}
			const modelIndex = main.models.Model.init(quadList.items);
			modelCache = modelIndex;
			return modelIndex;
		}

		pub fn generateData(_: *main.game.World, _: Vec3i, _: Vec3f, _: Vec3f, _: Vec3i, _: ?Neighbor, _: *Block, _: Block, _: bool) bool {
			return false;
		}

		pub fn modifyBlock(block: *Block, newBlockType: u16) bool {
			if(block.transparent() or block.viewThrough()) return false;
			if(!main.models.models.items[main.blocks.meshes.modelIndexStart(block.*)].allNeighborsOccluded) return false;
			if(block.data != 0) return false;
			block.data = block.typ;
			block.typ = newBlockType;
			return true;
		}

		pub fn canBeChangedInto(oldBlock: Block, newBlock: Block, _: main.items.ItemStack, shouldDropSourceBlockOnSuccess: *bool) RotationMode.CanBeChangedInto {
			if(oldBlock == newBlock) return .no;
			if(oldBlock.transparent() or oldBlock.viewThrough()) return .no;
			if(!main.models.models.items[main.blocks.meshes.modelIndexStart(oldBlock)].allNeighborsOccluded) return .no;
			if(oldBlock.data != 0) return .no;
			if(newBlock.data != oldBlock.typ) return .no;
			shouldDropSourceBlockOnSuccess.* = false;
			return .{.yes_costsItems = 1};
		}

		pub fn onBlockBreaking(_: ?main.items.Item, _: Vec3f, _: Vec3f, currentData: *Block) void {
			currentData.typ = currentData.data;
			currentData.data = 0;
		}
	};
};

// MARK: init/register

pub fn init() void {
	rotationModes = .init(main.globalAllocator.allocator);
	inline for(@typeInfo(RotationModes).@"struct".decls) |declaration| {
		register(@field(RotationModes, declaration.name));
	}
}

pub fn reset() void {
	inline for(@typeInfo(RotationModes).@"struct".decls) |declaration| {
		@field(RotationModes, declaration.name).reset();
	}
}

pub fn deinit() void {
	rotationModes.deinit();
	inline for(@typeInfo(RotationModes).@"struct".decls) |declaration| {
		@field(RotationModes, declaration.name).deinit();
	}
}

pub fn getByID(id: []const u8) *RotationMode {
	if(rotationModes.getPtr(id)) |mode| return mode;
	std.log.err("Could not find rotation mode {s}. Using no_rotation instead.", .{id});
	return rotationModes.getPtr("no_rotation").?;
}

pub fn register(comptime Mode: type) void {
	Mode.init();
	var result: RotationMode = RotationMode{};
	inline for(@typeInfo(RotationMode).@"struct".fields) |field| {
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
