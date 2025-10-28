const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const vec = main.vec;
const Vec3i = vec.Vec3i;

pub const ClientBlockEvent = Event(struct {block: Block, blockPos: Vec3i}, @import("block/client/_list.zig"));
pub const ServerBlockEvent = Event(struct {block: Block, chunk: *main.chunk.ServerChunk, x: i32, y: i32, z: i32}, @import("block/server/_list.zig"));

pub const BlockTouchEvent = Event(struct {entity: *main.server.Entity, source: Block, blockPos: Vec3i, deltaTime: f64}, @import("block/touch/_list.zig"));

pub const EventResult = enum {handled, ignored};

pub fn init() void {
	ClientBlockEvent.globalInit();
	ServerBlockEvent.globalInit();
	BlockTouchEvent.globalInit();
}

fn Event(_Params: type, list: type) type {
	return struct {
		data: *anyopaque,
		runFunction: *const fn(self: *anyopaque, params: Params) main.events.EventResult,

		pub const Params = _Params;

		const VTable = struct {
			init: *const fn(zon: main.ZonElement) ?*anyopaque,
			run: *const fn(self: *anyopaque, params: Params) main.events.EventResult,
		};

		var eventCreationMap: std.StringHashMapUnmanaged(VTable) = .{};

		fn globalInit() void {
			inline for(@typeInfo(list).@"struct".decls) |decl| {
				const EventStruct = @field(list, decl.name);
				eventCreationMap.put(main.globalArena.allocator, decl.name, .{
					.init = main.utils.castFunctionReturnToAnyopaque(EventStruct.init),
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
				.data = vtable.init(zon) orelse return null,
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
