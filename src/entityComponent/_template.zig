const std = @import("std");

const main = @import("main");
const chunk = main.chunk;
const Entity = main.entity.Entity;
const ServerChunk = chunk.ServerChunk;
const game = main.game;
const graphics = main.graphics;
const ZonElement = main.ZonElement;
const renderer = main.renderer;
const settings = main.settings;
const utils = main.utils;
const BinaryReader = utils.BinaryReader;
const BinaryWriter = utils.BinaryWriter;
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const blocks = main.blocks;
const World = game.World;
const ServerWorld = main.server.ServerWorld;
const items = main.items;
const ItemStack = items.ItemStack;
const random = main.random;

const c = @import("c");

pub var entityComponentID: main.entity.EntityComponentId = undefined;
pub const entityComponentVersion = 0;

// ############################# Client only stuff ################################
pub const client = struct {
	pub fn load(entity: Entity, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		_ = entity;
		_ = reader;
		_ = version;
	}
	pub fn unload(entity: Entity) void {
		_ = entity;
	}
	pub fn init() void {}
	pub fn deinit() void {}
	pub fn clear() void {}
};
// ############################# Server only stuff ################################
pub const server = struct {
	pub const ExampleComponent = struct {
		pub fn save(self: ExampleComponent, writer: *utils.BinaryWriter, audience: main.entity.AudienceInfo) main.entity.ComponentSaveBehaviour {
			_ = self;
			_ = writer;
			_ = audience;
			// do i want to be saved?
			return .save;
		}
	};
	pub fn init() void {}
	pub fn deinit() void {}
	pub fn get(entity: Entity) ?ExampleComponent {
		_ = entity;
		return null;
	}
	pub fn loadFromData(entity: Entity, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		_ = entity;
		_ = reader;
		_ = version;
	}
	pub fn unload(entity: Entity) void {
		_ = entity;
	}
};
