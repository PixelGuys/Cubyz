const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

pub fn init(_: ZonElement) ?*anyopaque {
	return @as(*anyopaque, undefined);
}

pub fn run(_: *anyopaque, params: main.callbacks.ClientBlockCallback.Params) main.callbacks.Result {
	if (params.block.blockEntity() == null or !std.mem.eql(u8, params.block.blockEntity().?.id, "sign")) {
		std.log.err("Can only edit sign if block entity of the block is a sign.", .{});
		return .ignored;
	}
	main.block_entity.BlockEntityTypes.Sign.StorageClient.mutex.lock();
	defer main.block_entity.BlockEntityTypes.Sign.StorageClient.mutex.unlock();
	const data = main.block_entity.BlockEntityTypes.Sign.StorageClient.get(params.blockPos, params.chunk);
	main.gui.windowlist.sign_editor.openFromSignData(params.blockPos, if (data) |_data| _data.text else "");

	return .handled;
}
