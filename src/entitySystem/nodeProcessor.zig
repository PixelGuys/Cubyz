const std = @import("std");

const main = @import("main");
const chunk = main.chunk;
const ServerChunk = chunk.ServerChunk;
const game = main.game;
const graphics = main.graphics;
const ZonElement = main.ZonElement;
const renderer = main.renderer;
const settings = main.settings;
const utils = main.utils;
const BinaryReader = utils.BinaryReader;
const BinaryWriter = utils.BinaryWriter;
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const blocks = main.blocks;
const World = game.World;
const ServerWorld = main.server.ServerWorld;
const items = main.items;
const ItemStack = items.ItemStack;
const random = main.random;
const entity = main.entity;
const EntityModel = main.entityModel.EntityModel;

const c = @import("c");

// ############################# Client only stuff ################################
pub const client = struct {
	pub var nodeBuffer: graphics.LargeBuffer(Mat4f) = undefined;

	pub fn init() void {
		nodeBuffer.init(main.globalAllocator, 1 << 20, 15);
	}

	pub fn deinit() void {
		nodeBuffer.deinit();
	}
	pub fn clear() void {}

	pub fn renderHud(_: Mat4f, _: Vec3f, _: Vec3d) void {}
	pub fn render(_: Mat4f, _: Vec3f, _: Vec3d, _: f64) void {
		main.client.entity_manager.mutex.lock();
		defer main.client.entity_manager.mutex.unlock();
		
		for (entity.components.@"cubyz:model".client.components.dense.items, entity.components.@"cubyz:model".client.components.denseToSparseIndex.items) |*component, id| {
			if (@intFromEnum(id) == game.Player.id) // don't process local player
				continue;

			const entModel = component.entityModel.get();
			const ent = main.client.entity_manager.getEntity(@intFromEnum(id)) orelse continue;

			const head = entModel.nodeIndexMap.get("Head");
			if (entModel.nodeIndexMap.get("Eyestalks")) |eyestalksId| {
				const stalkRot = ent.rot[0]*0.25;
				const headRot = ent.rot[0]*0.75;
				component.nodes[eyestalksId].setRot(vec.quatFromAxisAngle(Vec3f{1, 0, 0}, stalkRot));

				const headId = head.?;
				component.nodes[headId].setRot(vec.quatFromAxisAngle(Vec3f{1, 0, 0}, headRot));
			} else if (head) |headId| {
				component.nodes[headId].setRot(vec.quatFromAxisAngle(Vec3f{1, 0, 0}, ent.rot[0]));
			}

			for (component.nodes, 0..) |*node, i| {
				if ((node.parent != null and component.nodes[node.parent.?].version > node.parentVersion)) {
					const parentMat = component.matrices[node.parent.?];

					var newMat = Mat4f.identity();

					if (node.isDirty) {
						newMat = node.recalc(entModel.nodePivots[i]);
					}
					
					component.matrices[i] = newMat.mul(parentMat).transpose();
					node.parentVersion = component.nodes[node.parent.?].version;
				} else if (node.isDirty) {
					component.matrices[i] = node.recalc(entModel.nodePivots[i]).transpose();
				}

				node.isDirty = false;
			}

			main.entity.systems.nodeProcessor.client.nodeBuffer.uploadData(component.matrices, &component.bufferAllocation);
		}
	}
};
// ############################# Server only stuff ################################
pub const server = struct {
	pub fn init() void {}
	pub fn deinit() void {}

	pub fn update() void {}
};
