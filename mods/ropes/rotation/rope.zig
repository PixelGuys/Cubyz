const std = @import("std");

const main     = @import("main");
const blocks   = main.blocks;
const rotation = main.rotation;

const Neighbor   = main.chunk.Neighbor;
const ModelIndex = main.models.ModelIndex;
const ZonElement = main.ZonElement;
const Block      = blocks.Block;
const Degrees    = rotation.Degrees;

const Inventory = main.items.Inventory;
const Item      = main.items.Item;

const Mat4f = main.vec.Mat4f;
const Vec3f = main.vec.Vec3f;
const Vec3i = main.vec.Vec3i;

const mesh_storage  = main.renderer.mesh_storage;
const MeshSelection = main.renderer.MeshSelection;

const max_rope_length: usize = 256;

var rotatedModels: std.StringHashMap(ModelIndex) = undefined;

pub const RopeOrientation = enum(u2) {
	x,
	y,
	z, // up/down

	fn fromData(data: u16) RopeOrientation {
		return @enumFromInt(@min(data, 2));
	}

	fn toData(orient: RopeOrientation) u16 {
		return @intFromEnum(orient);
	}
};

pub fn init() void {
	rotatedModels = .init(main.globalAllocator.allocator);
}

pub fn deinit() void {
	rotatedModels.deinit();
}

pub fn reset() void {
	rotatedModels.clearRetainingCapacity();
}

pub fn createBlockModel(_: Block, _: *u16, zon: ZonElement) ModelIndex {
	const modelId = zon.as([]const u8, "cubyz:cube");
	if(rotatedModels.get(modelId)) |modelIndex| return modelIndex;

	// Get the base model that's created from the `.obj` file.
	const baseModel = main.models.getModelIndex(modelId).model();

	// Rotate the model to point along horizontal axes, plus unchanged.
	const x_orient = Mat4f.rotationY(std.math.tau / 4.0);
	const y_orient = Mat4f.rotationX(std.math.tau / 4.0);
	const z_orient = Mat4f.identity();

	// From my understanding, calling this function registers additional model
	// meshes into the model index. Because we want all related models to be
	// accessible in sequence, we re-add a copy of the base model as well.
	const modelIndex = baseModel.transformModel(rotation.rotationMatrixTransform, .{ x_orient });
	_                = baseModel.transformModel(rotation.rotationMatrixTransform, .{ y_orient });
	_                = baseModel.transformModel(rotation.rotationMatrixTransform, .{ z_orient });

	rotatedModels.put(modelId, modelIndex) catch unreachable;
	return modelIndex;
}

pub fn model(block: Block) ModelIndex {
	const modelOffset = @min(block.data, 2);
	return blocks.meshes.modelIndexStart(block).add(modelOffset);
}

pub fn rotateZ(data: u16, angle: Degrees) u16 {
	const orient = RopeOrientation.fromData(data);
	// Rotating up/down rope around Z axis leaves it unchanged.
	if(orient == .z) return data;
	// Rotating rope 0° or 180° leaves it unchanged.
	if(angle == .@"0" or angle == .@"180") return data;
	// Otherwise, X axis orientation becomes Y axis orientation and the other way around.
	const rotated: RopeOrientation = if(orient == .x) .y else .x;
	return rotated.toData();
}

pub fn generateData(_: *main.game.World, _: Vec3i, _: Vec3f, _: Vec3f, _: Vec3i, neighbor: ?Neighbor, block: *Block, _: Block, blockPlacing: bool) bool {
	if(blockPlacing) {
		var orient: RopeOrientation = .z;
		// Only place sideways ropes if `shift` is held.
		// (This is the same check `game.player.placeBlock` uses.)
		if(main.KeyBoard.key("shift").pressed) {
			if(neighbor) |n| {
				orient = switch(n) {
					.dirPosX, .dirNegX => .x,
					.dirPosY, .dirNegY => .y,
					.dirUp  , .dirDown => .z,
				};
			}
		}
		block.data = orient.toData();
		return true;
	}
	return false;
}

pub fn onBlockInteract(
	/// The block being interacted with.
	block: Block,
	/// The position of the interacted block.
	pos: Vec3i,
	/// The face, or normal, pointing away from the block.
	face: Vec3i,
	/// The relative position within the block being clicked, between {0,0,0} and {1,1,1}.
	rel: Vec3f,
	/// The player's inventory.
	inv: Inventory,
	/// The currently selected slot in the player's inventory.
	slot: u32,
	/// The item that's currently being held, if any.
	item: ?Item,
) bool {
	_ = .{ face, rel, item }; // unused

	// Check to see if the rope orientation is up/down.
	if(block.data != RopeOrientation.z.toData()) return false;

	// Try to extend the rope downwards.
	var currentPos = pos;
	for(1..max_rope_length) |_| {
		currentPos[2] -= 1;
		const below = getBlock(currentPos) orelse return false;
		if(std.meta.eql(below, block)) continue; // found more rope, continue

		// Try to place a rope block here.
		if(below.replacable() and MeshSelection.canPlaceBlock(currentPos, block))
			updateBlockAndSendUpdate(inv, slot, currentPos, .{0, 0, 0}, below, block);
		break;
	}
	return true;
}

pub fn onBlockBreaking(_: ?main.items.Item, _: Vec3f, _: Vec3f, block: *Block) void {
	// Check to see if the rope orientation is up/down.
	if(block.data == RopeOrientation.z.toData()) {
		// TODO: This assumes this is the selected block is being broken.
		//       Should probably be part of the function parameters instead.
		var currentPos = MeshSelection.selectedBlockPos orelse return;
		for(1..max_rope_length) |length| {
			const below = getBlock(currentPos - Vec3i{0, 0, 1}) orelse return;
			if(!std.meta.eql(below, block.*)) {
				// `below` is not an up/down rope, so break the block at `currentPos`.
				if(length==1) {
					// Special case: Break the initial block.
					block.* = .{.typ = 0, .data = 0};
				} else {
					// FIXME: This is VERY NAUGHTY but currently the only way to avoid a deadlock.
					Inventory.Sync.ClientSide.mutex.unlock();
					const inv  = main.game.Player.inventory;
					const slot = main.game.Player.selectedSlot;
					const dropOffset = Vec3f{0, 0, @floatFromInt(length)}; // drop block further up
					updateBlockAndSendUpdate(inv, slot, currentPos, dropOffset, block.*, .{.typ = 0, .data = 0});
					Inventory.Sync.ClientSide.mutex.lock();
				}
				return;
			}
			currentPos[2] -= 1;
		}
		// Reached the maximum rope length, so give up and break nothing.
	} else {
		// Just break the current block itself.
		block.* = .{.typ = 0, .data = 0};
	}
}


fn getBlock(pos: Vec3i) ?Block {
	return mesh_storage.getBlockFromRenderThread(pos[0], pos[1], pos[2]);
}

fn updateBlockAndSendUpdate(inv: Inventory, slot: u32, pos: Vec3i, dropOffset: Vec3f, oldBlock: Block, newBlock: Block) void {
	main.items.Inventory.Sync.ClientSide.executeCommand(.{
		.updateBlock = .{
			.source = .{.inv = inv, .slot = slot},
			.pos = pos,
			.dropLocation = .{
				.dir = MeshSelection.selectionFace,
				.min = MeshSelection.selectionMin,
				.max = MeshSelection.selectionMax,
				.offset = dropOffset,
			},
			.oldBlock = oldBlock,
			.newBlock = newBlock,
		},
	});
	mesh_storage.updateBlock(.{.x = pos[0], .y = pos[1], .z = pos[2], .newBlock = newBlock, .blockEntityData = &.{}});
}

