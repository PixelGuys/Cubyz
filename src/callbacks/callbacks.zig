const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const vec = main.vec;
const Vec3i = vec.Vec3i;

pub const ClientBlockCallback = Callback(struct {block: Block, blockPos: Vec3i}, @import("block/client/_list.zig"));
pub const ServerBlockCallback = Callback(struct {block: Block, chunk: *main.chunk.ServerChunk, x: i32, y: i32, z: i32}, @import("block/server/_list.zig"));

pub const BlockTouchCallback = Callback(struct {entity: *main.server.Entity, source: Block, blockPos: Vec3i, deltaTime: f64}, @import("block/touch/_list.zig"));

pub const Result = enum {handled, ignored};

pub fn init() void {
	ClientBlockCallback.globalInit();
	ServerBlockCallback.globalInit();
	BlockTouchCallback.globalInit();
}

fn Callback(_Params: type, list: type) type {
	return struct {
		data: *anyopaque,
		inner: *const fn(self: *anyopaque, params: Params) Result,

		pub const Params = _Params;

		const VTable = struct {
			init: *const fn(zon: main.ZonElement) ?*anyopaque,
			run: *const fn(self: *anyopaque, params: Params) Result,
		};

		var eventCreationMap: std.StringHashMapUnmanaged(VTable) = .{};

		fn globalInit() void {
			inline for(@typeInfo(list).@"struct".decls) |decl| {
				const CallbackStruct = @field(list, decl.name);
				eventCreationMap.put(main.globalArena.allocator, decl.name, .{
					.init = main.utils.castFunctionReturnToAnyopaque(CallbackStruct.init),
					.run = main.utils.castFunctionSelfToAnyopaque(CallbackStruct.run),
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
				.inner = vtable.run,
			};
		}

		pub const noop: @This() = .{
			.data = undefined,
			.inner = &noopCallback,
		};

		fn noopCallback(_: *anyopaque, _: Params) Result {
			return .ignored;
		}

		pub fn run(self: @This(), params: Params) Result {
			return self.inner(self.data, params);
		}

		pub fn isNoop(self: @This()) bool {
			return self.inner == &noopCallback;
		}
	};
}
