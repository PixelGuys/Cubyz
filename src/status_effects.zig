const std = @import("std");
const main = @import("main.zig");
const Tag = main.Tag;
const utils = main.utils;
const BinaryReader = utils.BinaryReader;
const BinaryWriter = utils.BinaryWriter;
const ZonElement = main.ZonElement;
const StatusUpdateCallback = main.callbacks.StatusUpdateCallback;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub const maxStatusEffectCount: usize = 65536; // 16 bit limit

var _id: [maxStatusEffectCount][]u8 = undefined;
var _onUpdate: [maxStatusEffectCount]StatusUpdateCallback = undefined;

var size: u32 = 0;

var reverseIndices: std.StringHashMapUnmanaged(u16) = .{};
pub fn register(_: []const u8, id: []const u8, zon: ZonElement) u16 {
	_id[size] = main.worldArena.dupe(u8, id);
	reverseIndices.put(main.worldArena.allocator, _id[size], @intCast(size)) catch unreachable;

	_onUpdate[size] = blk: {
		break :blk StatusUpdateCallback.init(zon.getChildOrNull("onUpdate") orelse break :blk .noop, .{.statusEffect = .{.typ = size}}) orelse {
			std.log.err("Failed to load onUpdate event for status {s}", .{_id[size]});
			break :blk .noop;
		};
	};

	defer size += 1;
	std.log.debug("Registered status: {d: >5} '{s}'", .{size, id});
	return @intCast(size);
}

pub fn reset() void {
	size = 0;
	reverseIndices = .{};
}

pub const StatusEffect = packed struct(u32) { // MARK: StatusEffect
	typ: u32,

	pub fn toInt(self: StatusEffect) u32 {
		return @as(u32, self.typ) | @as(u32, self.data) << 16;
	}
	pub fn fromInt(self: u32) StatusEffect {
		return StatusEffect{.typ = @truncate(self)};
	}

	pub inline fn id(self: StatusEffect) []u8 {
		return _id[self.typ];
	}

	pub inline fn idAndData(self: StatusEffect, list: *main.ListManaged(u8)) void {
		list.appendSlice(self.id());
		if (self.data == 0) return;
		list.append(':');
		self.mode().formatBlockData(self, list);
	}

	pub inline fn onUpdate(self: StatusEffect) StatusUpdateCallback {
		return _onUpdate[self.typ];
	}
};

pub const StatusEffectTracker = struct {
	id: u32,
	stacks: u32,
	timeLeft: f32,

	pub fn fromBytes(self: *StatusEffectTracker, reader: *BinaryReader) !void {
		self.id = try reader.readVarInt(u32);
		self.stacks = try reader.readVarInt(u32);
		self.timeLeft = try reader.readFloat(f32);
	}

	pub fn toBytes(self: StatusEffectTracker, writer: *BinaryWriter) void {
		writer.writeVarInt(u32, self.id);
		writer.writeVarInt(u32, self.stacks);
		writer.writeFloat(f32, self.timeLeft);
	}
};

pub const AppliedStatusEffects = struct {
	statusEffects: main.ListManaged(StatusEffectTracker),

	pub fn init(_: AppliedStatusEffects, allocator: NeverFailingAllocator) AppliedStatusEffects {
		return .{.statusEffects = .init(allocator)};
	}

	pub fn deinit(self: AppliedStatusEffects) void {
		self.statusEffects.deinit();
	}

	pub fn fromBytes(self: *AppliedStatusEffects, reader: *BinaryReader) !void {
		const amount = try reader.readVarInt(u32);
		for (0..amount) |_| {
			var statusTracker: StatusEffectTracker = StatusEffectTracker{.id = 0, .stacks = 0, .timeLeft = 0};
			try statusTracker.fromBytes(reader);
			self.statusEffects.append(statusTracker);
		}
	}

	pub fn toBytes(self: AppliedStatusEffects, writer: *BinaryWriter) void {
		writer.writeVarInt(u32, @intCast(self.statusEffects.items.len));
		for (self.statusEffects.items) |item| {
			item.toBytes(writer);
		}
	}
};
