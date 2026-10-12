const std = @import("std");

const main = @import("main");
const blocks = main.blocks;
const Block = blocks.Block;
const Neighbor = main.chunk.Neighbor;
const ModelIndex = main.models.ModelIndex;
const rotation = main.rotation;
const RotationMode = rotation.RotationMode;
const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

const minStateCount: u8 = 2;
const maxStateCount: u8 = 16;

var textureOnlyCache: std.StringHashMapUnmanaged(ModelIndex) = .{};
var modelRepositionCache: std.StringHashMapUnmanaged(ModelIndex) = .{};

const MultiModelKey = struct {
	modelId: [maxStateCount][]const u8,

	fn initFromZon(zon: ZonElement) MultiModelKey {
		var self: MultiModelKey = .{ .modelId = undefined };
		for (0..maxStateCount) |index| {
			self.modelId[index] = zon.getAtIndex([]const u8, index) orelse "cubyz:cube";
		}
		return self;
	}

	const Context = struct {
		pub fn hash(_: Context, val: MultiModelKey) u64 {
			var hasher = std.hash.Wyhash.init(0);
			for (val.modelId) |modelId| {
				hasher.update(modelId);
			}
			return hasher.final();
		}
		pub fn eql(_: Context, val1: MultiModelKey, val2: MultiModelKey) bool {
			for (0..maxStateCount) |index| {
				if (!std.mem.eql(u8, val1.modelId[index], val2.modelId[index])) return false;
			}
			return true;
		}
	};
};
const MultiModelHashMap = std.HashMapUnmanaged(MultiModelKey, ModelIndex, MultiModelKey.Context, std.hash_map.default_max_load_percentage);

var modelOnlyCache: MultiModelHashMap = .{};
var textureAndModelCache: MultiModelHashMap = .{};

pub fn init() void {
	textureOnlyCache = .empty;
	modelOnlyCache = .empty;
	modelRepositionCache = .empty;
	textureAndModelCache = .empty;
}

pub fn deinit() void {
	textureOnlyCache.deinit(main.globalAllocator.allocator);
	modelOnlyCache.deinit(main.globalAllocator.allocator);
	modelRepositionCache.deinit(main.globalAllocator.allocator);
	textureAndModelCache.deinit(main.globalAllocator.allocator);
}

pub fn reset() void {
	textureOnlyCache.clearRetainingCapacity();
	modelOnlyCache.clearRetainingCapacity();
	modelRepositionCache.clearRetainingCapacity();
	textureAndModelCache.clearRetainingCapacity();
}

const PileMode = enum(u8) {
	/// Use single model, change texture with every state.
	textureOnly = 0,
	/// Use one texture, change model with every state.
	modelOnly = 1,
	/// Use one texture and one model, but translate copies of the model. Copies use same texture.
	modelReposition = 2,
	/// Use different texture and model pair for every state.
	textureAndModel = 3,
};

pub fn createBlockModel(block: Block, modeData: *u16, zon: ZonElement) ModelIndex {
	const stateCount = zon.get(u8, "states") orelse 2;
	if (stateCount < minStateCount) {
		std.log.err("Block '{s}' uses texture pile with {} states. 'cubyz:texture_pile' should have at least {} states, use 'no_rotation' instead", .{block.id(), stateCount, minStateCount});
	} else if (stateCount > maxStateCount) {
		std.log.err("Block '{s}' uses texture pile with {} states. 'cubyz:texture_pile' can have at most {} states.", .{block.id(), stateCount, maxStateCount});
	}
	modeData.* = @min(stateCount, maxStateCount);

	const mode = zon.get(PileMode, "mode") orelse .textureOnly;
	const modelIndex = switch (mode) {
		.textureOnly => return createModelModeTextureOnly(block, zon),
		.modelOnly => return createModelModeOnly(block, zon),
		.modelReposition => return createModelModeModelReposition(block, zon),
		.textureAndModel => return createModelModeTextureAndModel(block, zon),
	};
	return modelIndex;
}

fn createModelModeTextureOnly(_: Block, zon: ZonElement) ModelIndex {
	const modelId = zon.get([]const u8, "model") orelse "cubyz:cube";

	if (textureOnlyCache.get(modelId)) |modelIndex| return modelIndex;

	const baseModel = main.models.getModelIndex(modelId).model();

	const transform = struct {
		fn transform(quad: *main.models.QuadInfo, data: u16) void {
			quad.textureSlot = data%maxStateCount;
		}
	};

	const modelIndex = baseModel.transformModel(transform.transform, .{@as(u16, @intCast(0))});
	for (1..maxStateCount) |data| {
		_ = baseModel.transformModel(transform.transform, .{@as(u16, @intCast(data))});
	}
	textureOnlyCache.put(main.globalAllocator.allocator, modelId, modelIndex) catch unreachable;
	return modelIndex;
}


fn getRequiredModelsField(mode: PileMode, block: Block, zon: ZonElement) ZonElement {
	const modelIdField = zon.getChild("models");
	if (modelIdField == .null) {
		std.log.err("Block {s} uses 'cubyz:texture_pile' with mode '{s}' but has no 'models' field.", .{block.id(), @tagName(mode)});
		return .null;
	}
	if (modelIdField != .array) {
		std.log.err("Block {s} uses 'cubyz:texture_pile' with mode '{s}' but 'models' field is not an array.", .{block.id(), @tagName(mode)});
		return .null;
	}
	return modelIdField;
}

fn createModelModeOnly(block: Block, zon: ZonElement) ModelIndex {
	const modelIdsArray = getRequiredModelsField(.modelOnly, block, zon);

	const cacheKey: MultiModelKey = .initFromZon(modelIdsArray);
	if (modelOnlyCache.get(cacheKey)) |modelIndex| return modelIndex;

	var firstModelIndex: ?ModelIndex = null;
	for (0..maxStateCount) |index| {
		const modelId = cacheKey.modelId[index] ;

		const baseModel = main.models.getModelIndex(modelId).model();
		const modelIndex = baseModel.dupeModel();
		if (firstModelIndex == null) firstModelIndex = modelIndex;
	}
	modelOnlyCache.put(main.globalAllocator.allocator, cacheKey, firstModelIndex.?) catch unreachable;
	return firstModelIndex.?;
}

fn createModelModeModelReposition(block: Block, zon: ZonElement) ModelIndex {
	const stateCount = zon.get(u8, "states") orelse 2;
	const modelId = zon.get([]const u8, "model") orelse "cubyz:cube";
	const offsets = zon.getChild("offsets");
	if (offsets == .null) {
		std.log.err("Block {s} uses 'cubyz:texture_pile' with mode 'modelReposition' but has no 'offsets' field.", .{block.id()});
	}
	if (offsets != .array) {
		std.log.err("Block {s} uses 'cubyz:texture_pile' with mode 'modelReposition' but 'offsets' field is not an array.", .{block.id()});
	}

	// if (modelRepositionCache.get(modelId)) |modelIndex| return modelIndex;

	const baseModel = main.models.getModelIndex(modelId).model();

	var firstModelIndex: ?ModelIndex = null;
	for (0..maxStateCount) |data| {
		var modelIndex: ModelIndex = undefined;

		if (data >= stateCount) {
			modelIndex = main.models.getModelIndex("cubyz:cube").model().dupeModel();
		} else {
			const stateOffsets = offsets.getAtIndex(ZonElement, data) orelse .null;
			if (stateOffsets != .array) {
				std.log.err("Block {s} invalid offset at index {} expected array got {s}.", .{block.id(), data, @tagName(stateOffsets)});
			}

			var transformedModels: main.List(ModelIndex) = .initCapacity(main.stackAllocator, @as(usize, data + 1));
			defer transformedModels.deinit(main.stackAllocator);

			const transform = struct {
				fn transform(quad: *main.models.QuadInfo, transformMatrix: vec.Mat4f) void {
					for (&quad.corners) |*corner| {
						corner.* = vec.xyz(vec.Mat4f.mulVec(transformMatrix, vec.combine(corner.*, 1)));
					}
				}
			};

			for (0..data + 1) |i| {
				std.log.debug("Block {s} modelReposition state {} i {}", .{block.id(), data, i});
				const offset = stateOffsets.getAtIndex(ZonElement, i) orelse .null;
				if (offset != .array) {
					std.log.err("Block {s} invalid offset at index {} for state {}.", .{block.id(), i, data});
				}
				const x = offset.getAtIndex(f32, 0) orelse 0.0;
				const y = offset.getAtIndex(f32, 1) orelse 0.0;
				const z = offset.getAtIndex(f32, 2) orelse 0.0;

				const transformedModel = baseModel.transformModel(transform.transform, .{vec.Mat4f.translation(.{x, y, z})});
				transformedModels.append(main.stackAllocator, transformedModel);
			}
			modelIndex = main.models.Model.mergeModels(transformedModels.items);
		}

		if (firstModelIndex == null) firstModelIndex = modelIndex;
	}
	// modelRepositionCache.put(main.globalAllocator.allocator, modelId, firstModelIndex.?) catch unreachable;
	return firstModelIndex.?;
}

fn createModelModeTextureAndModel(block: Block, zon: ZonElement) ModelIndex {
	const modelIdsField = getRequiredModelsField(.textureAndModel, block, zon);

	var cacheKey: MultiModelKey = .{ .modelId = undefined };
	for (0..maxStateCount) |index| {
		cacheKey.modelId[index] = modelIdsField.getAtIndex([]const u8, index) orelse "cubyz:cube";
	}
	if (textureAndModelCache.get(cacheKey)) |modelIndex| return modelIndex;

	var firstModelIndex: ?ModelIndex = null;
	for (0..maxStateCount) |index| {
		const modelId = cacheKey.modelId[index];

		const baseModel = main.models.getModelIndex(modelId).model();

		const transform = struct {
			fn transform(quad: *main.models.QuadInfo, data: u16) void {
				quad.textureSlot = data%maxStateCount;
			}
		};

		const modelIndex = baseModel.transformModel(transform.transform, .{@as(u16, @intCast(index))});
		if (firstModelIndex == null) firstModelIndex = modelIndex;
	}
	textureAndModelCache.put(main.globalAllocator.allocator, cacheKey, firstModelIndex.?) catch unreachable;
	return firstModelIndex.?;
}

pub fn model(block: Block) ModelIndex {
	return blocks.meshes.modelIndexStart(block).add(@min(block.data, block.modeData() - 1));
}

pub fn generateData(_: *main.game.World, _: Vec3i, _: Vec3f, _: Vec3f, _: Vec3i, _: ?Neighbor, currentData: *Block, _: Block, blockPlacing: bool) bool {
	if (blockPlacing) {
		currentData.data = 0;
		return true;
	}
	if (currentData.data >= currentData.modeData() - 1) {
		return false;
	}
	currentData.data = currentData.data + 1;
	return true;
}

pub fn onBlockBreaking(_: main.items.Item, _: Vec3f, _: Vec3f, currentData: *Block) void {
	if (currentData.data == 0) {
		currentData.* = .{.typ = 0, .data = 0};
	} else {
		currentData.data = @min(currentData.data, currentData.modeData() - 1) - 1;
	}
}

fn isItemBlock(block: Block, item: main.items.ItemStack) bool {
	return item.item == .baseItem and item.item.baseItem.block() == block.typ;
}

pub fn canBeChangedInto(oldBlock: Block, newBlock: Block, item: main.items.ItemStack, shouldDropSourceBlockOnSuccess: *bool) RotationMode.CanBeChangedInto {
	switch (RotationMode.DefaultFunctions.canBeChangedInto(oldBlock, newBlock, item, shouldDropSourceBlockOnSuccess)) {
		.no, .yes_costsDurability => return .no,
		.yes_costsItems => |r| return .{.yes_costsItems = r},
		.yes => {
			const oldAmount = if (oldBlock.typ == newBlock.typ) @min(oldBlock.data, oldBlock.modeData() - 1) else 0;
			if (oldAmount == newBlock.data) return .no;
			if (oldAmount > newBlock.data) return .yes;
			if (!isItemBlock(newBlock, item)) return .no;
			return .{.yes_costsItems = newBlock.data - oldAmount};
		},
	}
}

pub fn itemDropsOnChange(oldBlock: Block, newBlock: Block) u16 {
	if (newBlock.typ != oldBlock.typ) return oldBlock.data + 1;
	return oldBlock.data -| newBlock.data;
}

// MARK: non-interface fns

pub fn updateBlockFromNeighborConnectivity(block: *Block, neighborSupportive: [6]bool) void {
	if (!neighborSupportive[Neighbor.dirDown.toInt()]) block.* = .air;
}
