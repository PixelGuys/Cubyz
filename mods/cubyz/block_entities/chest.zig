const main = @import("main");
const utils = main.utils;
const BinaryReader = utils.BinaryReader;
const BinaryWriter = utils.BinaryWriter;
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const Chunk = main.chunk.Chunk;
const block_entity = main.block_entity;
const UpdateEvent = block_entity.UpdateEvent;
const EventStatus = block_entity.EventStatus;
const BlockEntityIndex = block_entity.BlockEntityIndex;
const BlockEntityDataStorage = block_entity.BlockEntityDataStorage;

const StorageServer = BlockEntityDataStorage(
	struct {
		id: ?u32,
	},
);

pub fn init() void {
	StorageServer.init();
}
pub fn deinit() void {
	StorageServer.deinit();
}
pub fn reset() void {
	StorageServer.reset();
}

pub fn onLoadClient(_: Vec3i, _: *Chunk, _: *BinaryReader) BinaryReader.AllErrors!void {}
pub fn onUnloadClient(_: BlockEntityIndex) void {}
pub fn onLoadServer(_: Vec3i, _: *Chunk, _: *BinaryReader) BinaryReader.AllErrors!void {}
pub fn onUnloadServer(dataIndex: BlockEntityIndex) void {
	StorageServer.mutex.lock();
	defer StorageServer.mutex.unlock();
	_ = StorageServer.removeAtIndex(dataIndex) orelse unreachable;
}
pub fn onStoreServerToDisk(_: BlockEntityIndex, _: *BinaryWriter) void {}
pub fn onStoreServerToClient(_: BlockEntityIndex, _: *BinaryWriter) void {}
pub fn onInteract(pos: Vec3i, _: *Chunk) EventStatus {
	if(main.KeyBoard.key("shift").pressed) return .ignored;

	const inventory = main.items.Inventory.init(main.globalAllocator, 20, .normal, .{.blockInventory = pos});

	main.gui.windowlist.chest.setInventory(inventory);
	main.gui.openWindow("chest");
	main.Window.setMouseGrabbed(false);

	return .handled;
}

pub fn updateClientData(_: Vec3i, _: *Chunk, _: UpdateEvent) BinaryReader.AllErrors!void {}
pub fn updateServerData(_: Vec3i, _: *Chunk, _: UpdateEvent) BinaryReader.AllErrors!void {}
pub fn getServerToClientData(_: Vec3i, _: *Chunk, _: *BinaryWriter) void {}
pub fn getClientToServerData(_: Vec3i, _: *Chunk, _: *BinaryWriter) void {}

pub fn renderAll(_: Mat4f, _: Vec3f, _: Vec3d) void {}