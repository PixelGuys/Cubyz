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

pub var entityComponentID: u32 = undefined;
pub const entityComponentVersion = 0;

// ############################# Client only stuff ################################
pub const client = struct {
	const PlayerComponent = struct {
		playerIndex: u32, // model
	};
	pub var playerComponents: main.utils.SparseSet(PlayerComponent, main.entity.Entity) = undefined;

	pub fn init() void {
		playerComponents = .{};
	}
	pub fn deinit() void {
		playerComponents.deinit(main.globalAllocator);
	}
	pub fn clear() void {
		playerComponents.deinit(main.globalAllocator);
		playerComponents = .{};
	}
	pub fn load(entity: u32, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		_ = version;
		const playerIndex = reader.readVarInt(u32) catch return main.entity.EntityComponentLoadError.UnreadableComponentData;

		const ptr = playerComponents.get(@enumFromInt(entity)) orelse playerComponents.add(main.globalAllocator, @enumFromInt(entity));
		ptr.* = PlayerComponent{
			.playerIndex = playerIndex,
		};
	}
	pub fn unload(entity: u32) void {
		playerComponents.remove(@enumFromInt(entity)) catch {};
	}
	pub fn get(entity: u32) ?*PlayerComponent {
		return playerComponents.get(@enumFromInt(entity));
	}
};

// ############################# Server only stuff ################################

pub const server = struct {
	pub const PlayerComponent = struct {
		playerIndex: u32, // model
		pub fn save(self: PlayerComponent, writer: *utils.BinaryWriter, audience: main.entity.AudienceInfo) main.entity.ComponentSaveBehaviour {
			_ = audience;
			writer.writeVarInt(u32, self.playerIndex);
			return .save;
		}
	};
	var playerComponents: main.utils.SparseSet(PlayerComponent, main.entity.Entity) = undefined;
	pub fn init() void {
		playerComponents = .{};
	}
	pub fn deinit() void {
		playerComponents.deinit(main.globalAllocator);
	}
	pub fn loadFromData(entity: u32, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		_ = version;
		const playerIndex = reader.readVarInt(u32) catch return main.entity.EntityComponentLoadError.UnreadableComponentData;

		try load(entity, playerIndex);
	}
	pub fn load(entity: u32, playerIndex: u32) main.entity.EntityComponentLoadError!void {
		const ptr = playerComponents.get(@enumFromInt(entity)) orelse playerComponents.add(main.globalAllocator, @enumFromInt(entity));
		ptr.* = PlayerComponent{
			.playerIndex = playerIndex,
		};
	}
	pub fn unload(entity: u32) void {
		playerComponents.remove(@enumFromInt(entity)) catch {};
	}
	pub fn put(entity: u32, renderComponent: PlayerComponent) void {
		const ptr = playerComponents.get(@enumFromInt(entity)) orelse playerComponents.add(main.globalAllocator, @enumFromInt(entity));
		ptr.* = renderComponent;
	}
	pub fn get(entity: u32) ?*PlayerComponent {
		return playerComponents.get(@enumFromInt(entity));
	}
};
