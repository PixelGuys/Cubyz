const std = @import("std");

const main = @import("main");
const NeverFailingArenaAllocator = main.heap.NeverFailingArenaAllocator;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const DenseId = main.utils.DenseId;

pub const EntityTypeId = DenseId(u16);
pub const EntityId = DenseId(u16);

var arenaAllocator: NeverFailingArenaAllocator = undefined;
var allocator: NeverFailingAllocator = undefined;

const freeList: main.ListUnmanaged(EntityId) = undefined;

pub fn init() void {
	arenaAllocator = .init(main.globalAllocator);
	allocator = arenaAllocator.allocator();

	freeList = .initCapacity(allocator, @intFromEnum(EntityId.noValue));

	for (0..@intFromEnum(EntityId.noValue)) |i| {
		freeList.append(allocator, @enumFromInt(i));
	}
}

pub fn deinit() void {
	arenaAllocator.deinit();
}

pub fn reset() void {
	_ = arenaAllocator.reset(.free_all);
}