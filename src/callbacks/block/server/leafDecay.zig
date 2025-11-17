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
fn getIndexInCheckArray(relative_x: i32, relative_y: i32, relative_z: i32, checkRange: comptime_int) usize {
	const checkLength = checkRange*2 + 1;

	const arrayIndexX = relative_x + checkRange;
	const arrayIndexY = relative_y + checkRange;
	const arrayIndexZ = relative_z + checkRange;
	return @as(usize, @intCast((arrayIndexX*checkLength + arrayIndexY)*checkLength + arrayIndexZ));
}
fn foundWayToLog(world: *Server.ServerWorld, leaf: Block, wx: i32, wy: i32, wz: i32) bool {

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

	queue.pushBack(Vec3i{0, 0, 0});
	checked[getIndexInCheckArray(0, 0, 0, checkRange)] = true;

	while(queue.popFront()) |value| {
		// get the (potential) log
		if(world.getBlock(value[0] + wx, value[1] + wy, value[2] + wz)) |log| {
			// it is a log
			// end search.
			if(log.decayProhibitor()) {
				return true;
			}
			// it is the same type of leaf
			// continue search!
			else if(log.typ == leaf.typ) {
				const neighbourRange = 1; // 1 = leaves need path to log without air gab
				for(0..neighbourRange*2 + 1) |offsetX| {
					for(0..neighbourRange*2 + 1) |offsetY| {
						for(0..neighbourRange*2 + 1) |offsetZ| {
							// relative position
							const X = value[0] + @as(i32, @intCast(offsetX)) - neighbourRange;
							const Y = value[1] + @as(i32, @intCast(offsetY)) - neighbourRange;
							const Z = value[2] + @as(i32, @intCast(offsetZ)) - neighbourRange;

							// out of range
							if(X*X + Y*Y + Z*Z > checkRange*checkRange)
								continue;

							// mark as checked
							if(checked[getIndexInCheckArray(X, Y, Z, checkRange)])
								continue;
							checked[getIndexInCheckArray(X, Y, Z, checkRange)] = true;
							queue.pushBack(Vec3i{X, Y, Z});
						}
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
		if(world.getBlock(wx, wy, wz)) |leaf| {

			// check if there is any log in the proximity?^
			if(foundWayToLog(world, leaf, wx, wy, wz))
				return .ignored;

			// no, there is no log in proximity
			_ = world.cmpxchgBlock(wx, wy, wz, leaf, Block{.typ = leaf.decayReplacement(), .data = 0});

			return .handled;
		}
	}
	return .ignored;
}
