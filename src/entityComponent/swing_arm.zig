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
	const Component = struct {
		currentSwingProgress: f32,
	};
	pub var components: main.utils.SparseSet(Component, Entity) = .{};

	pub fn init() void {}
	pub fn deinit() void {
		components.deinit(main.globalAllocator);
	}
	pub fn clear() void {
		components.clear();
	}
	pub fn load(entity: Entity, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		if (version != 0) return error.InvalidComponentVersion;
		const currentSwingProgress = reader.readFloat(f32) catch return error.UnreadableComponentData;
		const ptr = components.get(entity) orelse components.add(main.globalAllocator, entity);
		ptr.* = Component{
			.currentSwingProgress = currentSwingProgress,
		};
	}
	pub fn unload(entity: Entity) void {
		components.remove(entity) catch {};
	}
	pub fn get(entity: Entity) ?*Component {
		return components.get(entity);
	}
};
// ############################# Server only stuff ################################
pub const server = struct {
	pub const Component = struct {
		currentSwingProgress: f32,
		pub fn save(self: Component, writer: *utils.BinaryWriter, audience: main.entity.AudienceInfo) main.entity.ComponentSaveBehaviour {
			writer.writeFloat(f32, self.currentSwingProgress);
			if (audience == .disk) return .discard;
			return .save;
		}
	};
	var components: main.utils.SparseSet(Component, Entity) = undefined;
	pub fn init() void {
		components = .{};
	}
	pub fn deinit() void {
		components.deinit(main.globalAllocator);
	}
	pub fn loadFromData(entity: Entity, _: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		if (version != 0) return error.InvalidComponentVersion;
		load(entity);
	}
	pub fn load(entity: Entity) void {
		put(entity, Component{
			.currentSwingProgress = 0,
		});
	}
	pub fn unload(entity: Entity) void {
		components.remove(entity) catch {};
	}
	pub fn put(entity: Entity, renderComponent: Component) void {
		const ptr = components.get(entity) orelse components.add(main.globalAllocator, entity);
		ptr.* = renderComponent;
	}
	pub fn get(entity: Entity) ?*Component {
		return components.get(entity);
	}
};
