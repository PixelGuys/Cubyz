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
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const BinaryReader = main.utils.BinaryReader;

pub var entityComponentID: main.entity.EntityComponentId = undefined;
pub const entityComponentVersion = 0;

// ############################# Client only stuff ################################
pub const client = struct {
	const Component = struct {
		playerIndex: u32,
	};
	pub var components: main.utils.SparseSet(Component, main.entity.Entity) = .{};

	pub fn init() void {}
	pub fn deinit() void {
		components.deinit(main.globalAllocator);
	}
	pub fn clear() void {
		components.clear();
	}
	pub fn load(entity: u32, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		if (version != 0)
			return main.entity.EntityComponentLoadError.InvalidComponentVersion;
		const playerIndex = reader.readVarInt(u32) catch return main.entity.EntityComponentLoadError.UnreadableComponentData;

		const ptr = components.get(@enumFromInt(entity)) orelse components.add(main.globalAllocator, @enumFromInt(entity));
		ptr.* = Component{
			.playerIndex = playerIndex,
		};
	}
	pub fn unload(entity: u32) void {
		components.remove(@enumFromInt(entity)) catch {};
	}
	pub fn get(entity: u32) ?*Component {
		return components.get(@enumFromInt(entity));
	}
};

// ############################# Server only stuff ################################

pub const server = struct {
	pub const component = struct {
		playerIndex: u32, // model
		pub fn save(self: component, writer: *utils.BinaryWriter, audience: main.entity.AudienceInfo) main.entity.ComponentSaveBehaviour {
			writer.writeVarInt(u32, self.playerIndex);
			if (audience == .disk)
				return .discard;
			return .save;
		}
	};
	var components: main.utils.SparseSet(component, main.entity.Entity) = undefined;
	pub fn init() void {
		components = .{};
	}
	pub fn deinit() void {
		components.deinit(main.globalAllocator);
	}
	pub fn loadFromData(entity: u32, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		if (version != 0)
			return main.entity.EntityComponentLoadError.InvalidComponentVersion;
		const playerIndex = reader.readVarInt(u32) catch return main.entity.EntityComponentLoadError.UnreadableComponentData;

		try load(entity, playerIndex);
	}
	pub fn load(entity: u32, playerIndex: u32) main.entity.EntityComponentLoadError!void {
		const ptr = components.get(@enumFromInt(entity)) orelse components.add(main.globalAllocator, @enumFromInt(entity));
		ptr.* = component{
			.playerIndex = playerIndex,
		};
	}
	pub fn unload(entity: u32) void {
		components.remove(@enumFromInt(entity)) catch {};
	}
	pub fn put(entity: u32, renderComponent: component) void {
		const ptr = components.get(@enumFromInt(entity)) orelse components.add(main.globalAllocator, @enumFromInt(entity));
		ptr.* = renderComponent;
	}
	pub fn get(entity: u32) ?*component {
		return components.get(@enumFromInt(entity));
	}
};
