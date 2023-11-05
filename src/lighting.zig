const std = @import("std");

const main = @import("root");
const blocks = main.blocks;
const chunk = main.chunk;

const Channel = enum {
	red,
	green,
	blue,

	pub fn shift(self: Channel) u5 {
		switch(self) {
			.red => return 16,
			.green => return 8,
			.blue => return 0,
		}
	}
};

pub const ChannelChunk = struct {
	data: [chunk.chunkVolume]u8,
	mutex: std.Thread.Mutex,

	pub fn init(self: *ChannelChunk, ch: *chunk.Chunk) !void {
		self.mutex = .{};
		for(&self.data, 0..) |*val, i| {
			val.* = if(ch.blocks[i].transparent()) 255 else 0; // TODO: Proper light propagation. This is just ambient occlusion at the moment.
		}
	}

	pub fn getValue(self: *ChannelChunk, voxelSizeShift: u5, wx: i32, wy: i32, wz: i32) u8 {
		const x = (wx >> voxelSizeShift) & chunk.chunkMask;
		const y = (wy >> voxelSizeShift) & chunk.chunkMask;
		const z = (wz >> voxelSizeShift) & chunk.chunkMask;
		const index = chunk.getIndex(x, y, z);
		return self.data[index];
	}
};