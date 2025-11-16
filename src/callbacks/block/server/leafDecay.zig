const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const blocks = main.blocks;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;
const Server = main.server;

pub fn init(_: ZonElement) ?*@This() {
	const result = main.worldArena.create(@This());
	return result;
}
fn foundWayToLog(world: *Server.ServerWorld, leave: Block, wx: i32, wy: i32, wz: i32) bool {

	// init array to mark already searched blocks.
	const checkRange = 5;
	const checkLength = checkRange*2 + 1;
	var checked: [checkLength*checkLength*checkLength]bool = undefined;
	for(0..checkLength*checkLength*checkLength) |i| {
		checked[i] = false;
	}

	// queue for breath-first search
	var queue = main.utils.CircularBufferQueue(Vec3i).init(main.globalAllocator, 32);
	defer queue.deinit();
	queue.pushBack(Vec3i{wx - 1, wy, wz});
	queue.pushBack(Vec3i{wx + 1, wy, wz});
	queue.pushBack(Vec3i{wx, wy - 1, wz});
	queue.pushBack(Vec3i{wx, wy + 1, wz});
	queue.pushBack(Vec3i{wx, wy, wz - 1});
	queue.pushBack(Vec3i{wx, wy, wz + 1});

	while(queue.popFront()) |value| {
		// calc relative position
		const x = @as(i32, @intCast(value[0])) - wx;
		const y = @as(i32, @intCast(value[1])) - wy;
		const z = @as(i32, @intCast(value[2])) - wz;

		// out of range
		if(x*x + y*y + z*z > checkRange*checkRange)
			continue;

		// mark as checked
		const arrayIndexX = x + checkRange;
		const arrayIndexY = y + checkRange;
		const arrayIndexZ = z + checkRange;
		const index = (arrayIndexX*checkLength + arrayIndexY)*checkLength + arrayIndexZ;
		if(checked[@as(usize, @intCast(index))])
			continue;
		checked[@as(usize, @intCast(index))] = true;

		// get the (potential) log
		const chunkPosition = main.chunk.ChunkPosition.initFromWorldPos(value, 1);
		var chunk = world.getOrGenerateChunkAndIncreaseRefCount(chunkPosition);
		chunk.mutex.lock();
		const log = chunk.getBlock(value[0] & main.chunk.chunkMask, value[1] & main.chunk.chunkMask, value[2] & main.chunk.chunkMask);
		chunk.mutex.unlock();
		chunk.decreaseRefCount();

		// it is a log
		// end search.
		if(log.decayProhibitor()) {
			return true;
		}
		// it is the same type of leave
		// continue search!
		else if(log.typ == leave.typ) {
			const neighbourRange = 1; // 1 = leaves need path to log without air gab
			for(0..neighbourRange*2 + 1) |offsetX| {
				for(0..neighbourRange*2 + 1) |offsetY| {
					for(0..neighbourRange*2 + 1) |offsetZ| {
						const totalX = value[0] + @as(i32, @intCast(offsetX)) - neighbourRange;
						const totalY = value[1] + @as(i32, @intCast(offsetY)) - neighbourRange;
						const totalZ = value[2] + @as(i32, @intCast(offsetZ)) - neighbourRange;
						queue.pushBack(Vec3i{
							totalX,
							totalY,
							totalZ,
						});
					}
				}
			}
		}
	}
	return false;
}
pub fn run(_: *@This(), params: main.callbacks.ServerBlockCallback.Params) main.callbacks.Result {
	const wx = params.chunk.super.pos.wx + params.x;
	const wy = params.chunk.super.pos.wy + params.y;
	const wz = params.chunk.super.pos.wz + params.z;

	main.items.Inventory.Sync.ServerSide.mutex.lock();
	defer main.items.Inventory.Sync.ServerSide.mutex.unlock();

	if(Server.world) |world| {
		params.chunk.mutex.lock();
		const leave = params.chunk.getBlock(wx & main.chunk.chunkMask, wy & main.chunk.chunkMask, wz & main.chunk.chunkMask);
		params.chunk.mutex.unlock();

		// check if there is any log in the proximity?^
		if(foundWayToLog(world, leave, wx, wy, wz))
			return .ignored;
		// no, there is no log in proximity
		world.updateBlock(wx, wy, wz, main.blocks.Block.air);

		// trigger others leaves:
		world.updateSurrounding(wx, wy, wz);
		return .handled;
	}
	return .ignored;
}
