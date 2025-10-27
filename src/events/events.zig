const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const vec = main.vec;
const Vec3i = vec.Vec3i;

pub const BlockInteract = GenericEvent(struct {block: Block, pos: Vec3i}, @import("block_interact/_list.zig"));

pub const EventResult = enum {handled, ignored};

pub fn init() void {
	BlockInteract.globalInit();
}

fn GenericEvent(_Params: type, list: type) type {
	return struct {
		data: *anyopaque,
		runFunction: *const fn(self: *anyopaque, params: Params) main.events.EventResult,

		pub const Params = _Params;

		const VTable = struct {
			load: *const fn(zon: main.ZonElement) ?*anyopaque,
			run: *const fn(self: *anyopaque, params: Params) main.events.EventResult,
		};

		var eventCreationMap: std.StringHashMapUnmanaged(VTable) = .{};

		fn globalInit() void {
			inline for(@typeInfo(list).@"struct".decls) |decl| {
				const EventStruct = @field(list, decl.name);
				eventCreationMap.put(main.globalArena.allocator, decl.name, .{
					.load = main.utils.castFunctionReturnToAnyopaque(EventStruct.load),
					.run = main.utils.castFunctionSelfToAnyopaque(EventStruct.run),
				}) catch unreachable;
			}
		}

		pub fn init(zon: main.ZonElement) ?@This() {
			const typ = zon.get(?[]const u8, "type", null) orelse {
				std.log.err("Missing field \"type\"", .{});
				return null;
			};
			const vtable = eventCreationMap.get(typ) orelse {
				std.log.err("Couldn't find block interact event {s}", .{typ});
				return null;
			};
			return .{
				.data = vtable.load(zon) orelse return null,
				.runFunction = vtable.run,
			};
		}

		pub const ignored: @This() = .{
			.data = undefined,
			.runFunction = &ignoredRun,
		};

		fn ignoredRun(_: *anyopaque, _: Params) EventResult {
			return .ignored;
		}

		pub fn run(self: @This(), params: Params) main.events.EventResult {
			return self.runFunction(self.data, params);
		}
	};
}
