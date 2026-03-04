const std = @import("std");

const main = @import("main");
const chunk = main.chunk;
const game = main.game;
const graphics = main.graphics;
const c = graphics.c;
const ZonElement = main.ZonElement;
const renderer = main.renderer;
const settings = main.settings;
const utils = main.utils;
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const BinaryReader = main.utils.BinaryReader;
const BinaryWriter = main.utils.BinaryWriter;

const blocks = main.blocks;
const chunk_zig = main.chunk;
const ServerChunk = chunk_zig.ServerChunk;
const World = game.World;
const ServerWorld = main.server.ServerWorld;
const items = main.items;
const ItemStack = items.ItemStack;
const random = main.random;

// ############################# Client only stuff ################################
pub const Client = struct {
	pub fn register(id: u32, comp: ZonElement) void {
		_ = id;
		_ = comp;
	}
	pub fn unregister(id: u32) void {
		_ = id;
	}
	pub fn init() void {}
	pub fn deinit() void {}
	pub fn clear() void {}
};
// ############################# Server only stuff ################################
pub const Server = struct {
	pub const ItemComponent = struct {
		pub fn save(self: ItemComponent, allocator: NeverFailingAllocator) ZonElement {
			_ = self;
			_ = allocator;
			return .null;
		}
	};
	pub fn init() void {}
	pub fn deinit() void {}
	pub fn get(id: u32) ?ItemComponent {
		_ = id;
		return null;
	}
	pub fn unregister(id: u32) void {
		_ = id;
	}
};
