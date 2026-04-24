const std = @import("std");

const main = @import("main");
const MeshSelection = main.renderer.MeshSelection;
const mesh_storage = main.renderer.mesh_storage;
const Block = main.blocks.Block;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const ZonElement = main.ZonElement;

var currentBlockProgress: f32 = 0;
var currentSwingProgress: f32 = 0;
var currentSwingTime: f32 = 0;

pub fn init(_: ZonElement) ?*@This() {
	const result = main.worldArena.create(@This());
	return result;
}

pub fn run(_: *@This(), params: main.callbacks.ItemUsedCallback.Params) main.callbacks.Result {
	const selectedPos = params.selectedBlockPos orelse return .ignored;
	if (params.deltaTime == 0) {
		currentBlockProgress = 0;
		currentSwingProgress = 0;
		currentSwingTime = 0;
	}
	const block = mesh_storage.getBlockFromRenderThread(selectedPos[0], selectedPos[1], selectedPos[2]) orelse return .ignored;

	const holdingTargetedBlock = params.item == .baseItem and params.item.baseItem.block() == block.typ;
	if ((block.hasTag(.fluid) or block.hasTag(.air)) and !holdingTargetedBlock) return .ignored;

	const relPos: Vec3f = @floatCast(main.game.Player.super.pos - @as(Vec3d, @floatFromInt(selectedPos)));

	main.sync.ClientSide.mutex.lock();
	if (!main.game.Player.isCreative()) {
		var damage: f32 = main.game.Player.defaultBlockDamage;
		const isProceduralItem = params.item == .proceduralItem;
		if (isProceduralItem) {
			damage = params.item.proceduralItem.getBlockDamage(block);
		}
		damage -= block.blockResistance();
		if (damage > 0) {
			const swingTime = if (isProceduralItem and params.item.proceduralItem.isEffectiveOn(block)) 1.0/params.item.proceduralItem.getProperty(.swingSpeed) else 0.5;
			if (currentSwingTime > swingTime) {
				currentSwingProgress = 0;
				currentSwingTime = 0;
			}
			if (currentSwingTime == 0) {
				const swings = @ceil(block.blockHealth()/damage);
				const damagePerSwing = block.blockHealth()/swings;
				currentSwingTime = damagePerSwing/damage*swingTime;
			}
			currentSwingProgress += @floatCast(params.deltaTime);
			while (currentSwingProgress > currentSwingTime) {
				currentSwingProgress -= currentSwingTime;
				currentBlockProgress += damage*currentSwingTime/swingTime/block.blockHealth();
				if (currentBlockProgress > 0.9999) break;
				const swings = @ceil(block.blockHealth()/damage);
				const damagePerSwing = block.blockHealth()/swings;
				currentSwingTime = damagePerSwing/damage*swingTime;
			}
			if (currentBlockProgress < 0.9999) {
				mesh_storage.removeBreakingAnimation(MeshSelection.lastSelectedBlockPos);
				if (currentBlockProgress != 0) {
					mesh_storage.addBreakingAnimation(MeshSelection.lastSelectedBlockPos, currentBlockProgress);
				}
				main.sync.ClientSide.mutex.unlock();

				return .handled;
			} else {
				currentSwingProgress = 0;
				mesh_storage.removeBreakingAnimation(MeshSelection.lastSelectedBlockPos);
				currentBlockProgress = 0;
				currentSwingTime = 0;
			}
		} else {
			main.sync.ClientSide.mutex.unlock();
			return .handled;
		}
	} else {
		mesh_storage.removeBreakingAnimation(MeshSelection.lastSelectedBlockPos);
	}

	var newBlock = block;
	block.mode().onBlockBreaking(params.item, relPos, params.lastDir, &newBlock);
	main.sync.ClientSide.mutex.unlock();

	if (newBlock != block) {
		MeshSelection.updateBlockAndSendUpdate(main.game.Player.inventory, main.game.Player.selectedSlot, selectedPos, block, newBlock);
	}
	return .handled;
}
