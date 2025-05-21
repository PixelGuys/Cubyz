const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const Neighbor = main.chunk.Neighbor;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;

pub fn init() void {}
pub fn deinit() void {}
pub fn reset() void {}

const PackedType = u1;

pub const PersistentData = packed struct(PackedType) {
	playerPlaced: bool,

	pub inline fn castData(data: u16) PersistentData {
		return @bitCast(@as(PackedType, @intCast(data)));
	}
};

pub fn generateData(_: *main.game.World, _: Vec3i, _: Vec3f, _: Vec3f, _: Vec3i, _: ?Neighbor, currentData: *Block, _: Block, blockPlacing: bool) bool {
	if(blockPlacing) {
		var data: PersistentData = PersistentData.castData(currentData.data);
		data.playerPlaced = true;
		currentData.data = @as(PackedType, @bitCast(data));
	}
	return blockPlacing;
}
