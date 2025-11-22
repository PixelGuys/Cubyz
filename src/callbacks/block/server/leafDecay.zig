const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const blocks = main.blocks;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;
const Server = main.server;

decayReplacement: blocks.Block,

pub fn init(zon: ZonElement) ?*@This() {
	const result = main.worldArena.create(@This());
	if(zon.get(?[]const u8, "replacement", null)) |blockname| {
		result.decayReplacement = main.blocks.parseBlock(blockname);
	} else result.decayReplacement = main.blocks.Block.air;

	return result;
}
fn getIndexInCheckArray(relativePosition: Vec3i, checkRange: comptime_int) usize {
	const checkLength = checkRange*2 + 1;

	const arrayIndexX = relativePosition[0] + checkRange;
	const arrayIndexY = relativePosition[1] + checkRange;
	const arrayIndexZ = relativePosition[2] + checkRange;
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

	// queue for breadth-first search
	var queue = main.utils.CircularBufferQueue(Vec3i).init(main.stackAllocator, 32);
	defer queue.deinit();

	queue.pushBack(Vec3i{0, 0, 0});
	checked[getIndexInCheckArray(Vec3i{0, 0, 0}, checkRange)] = true;

	while(queue.popFront()) |value| {
		// get the (potential) log
		if(world.getBlock(value[0] +% wx, value[1] +% wy, value[2] +% wz)) |log| {
			// it is a log ? end search.
			if(log.decayProhibitor()) {
				return true;
			}
			// it is the same type of leaf? continue search!
			if(log.typ != leaf.typ) continue;
			for(main.chunk.Neighbor.iterable) |offset| {
				const relativePosition = value + offset.relPos();

				// out of range
				if(vec.lengthSquare(relativePosition) > checkRange*checkRange)
					continue;

				// mark as checked
				if(checked[getIndexInCheckArray(relativePosition, checkRange)])
					continue;
				checked[getIndexInCheckArray(relativePosition, checkRange)] = true;
				queue.pushBack(relativePosition);
			}
		}
	}
	return false;
}
pub fn run(self: *@This(), params: main.callbacks.ServerBlockCallback.Params) main.callbacks.Result {
	const wx = params.chunk.super.pos.wx + params.x;
	const wy = params.chunk.super.pos.wy + params.y;
	const wz = params.chunk.super.pos.wz + params.z;

	if(params.block.mode() == main.rotation.getByID("cubyz:decayable")) {
		if(params.block.data != 0)
			return .ignored;
	} else {
		std.log.err("Expected {s} to have cubyz:decayable rotation", .{params.block.id()});
	}

	if(Server.world) |world| {
		if(world.getBlock(wx, wy, wz)) |leaf| {
			// check if there is any log in the proximity?^
			if(foundWayToLog(world, leaf, wx, wy, wz))
				return .ignored;

			// no, there is no log in proximity
			main.items.Inventory.Sync.ServerSide.mutex.lock();
			defer main.items.Inventory.Sync.ServerSide.mutex.unlock();
			if(world.cmpxchgBlock(wx, wy, wz, leaf, self.decayReplacement) == null) {
				return .handled;
			}
		}
	}
	return .ignored;
}
