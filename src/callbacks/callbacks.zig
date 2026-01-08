const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const vec = main.vec;
const Vec3i = vec.Vec3i;

pub const ClientBlockCallback = Callback(struct {block: Block, blockPos: Vec3i}, @import("block/client/_list.zig"));
pub const ServerBlockCallback = Callback(struct {block: Block, chunk: *main.chunk.ServerChunk, blockPos: main.chunk.BlockPos}, @import("block/server/_list.zig"));

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
					.init = main.meta.castFunctionReturnToOptionalAnyopaque(CallbackStruct.init),
					.run = main.meta.castFunctionSelfToAnyopaque(CallbackStruct.run),
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

pub const SimpleCallback = struct {
	data: *anyopaque = undefined,
	inner: ?*const fn(*anyopaque) void = null,

	fn genericWrapper(callbackFunction: fn() void) *const fn(*anyopaque) void {
		return &struct {
			fn wrapper(_: *anyopaque) void {
				callbackFunction();
			}
		}.wrapper;
	}

	pub fn init(comptime callbackFunction: fn() void) SimpleCallback {
		return .{
			.inner = genericWrapper(callbackFunction),
		};
	}

	pub fn initWithPtr(callbackFunction: anytype, data: *anyopaque) SimpleCallback {
		return .{
			.inner = main.meta.castFunctionSelfToAnyopaque(callbackFunction),
			.data = data,
		};
	}

	pub fn initWithInt(callbackFunction: fn(usize) void, data: usize) SimpleCallback {
		@setRuntimeSafety(false);
		return .{
			.inner = @ptrCast(&callbackFunction),
			.data = @ptrFromInt(data),
		};
	}

	pub fn run(self: SimpleCallback) void {
		if(self.inner) |callback| {
			callback(self.data);
		}
	}
};
