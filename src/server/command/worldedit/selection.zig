const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const command = main.server.command;
const User = main.server.User;
const Vec3i = main.vec.Vec3i;

pub const description = "Operate on selection";
pub const usage =
	\\/selection norm
	\\/selection normalize
	\\  Ensure pos1 is set to minimal coordinates and pos2 is set to maximal coordinates from selection.
	\\/selection query <info/blocks>
	\\  info - log general information about selection (pos1, pos2, size, number blocks and entities inside)
	\\  blocks - log list of unique blocks in selection and count them.
	\\/selection edit <direction> <amount>
	\\/selection shrink <limit=32>
	\\  Automatically shrink the selection to fit a structure, non-air blocks stop shrinking process.
	\\/selection grow <limit=32>
	\\  Automatically grow the selection to fit a structure.
;

const Mode = enum {info, blocks};
const Direction = enum {@"+x", @"-x", @"+y", @"-y", @"+z", @"-z", @"front", @"back", @"left", @"rigth", @"up", @"down"};

const Args = union(enum) {
	@"/selection query <info/blocks>": struct {_: enum{query}, mode: Mode},
	@"/selection edit <direction> <amount>": struct {_: enum{edit}, direction: Direction, amount: i32},
	@"/selection shrink <limit>": struct {_: enum{@"shrink"}, limit: ?u32},
	@"/selection grow <limit>": struct {_: enum{@"grow"}, limit: ?u32},
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/selection"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};

	switch (result) {
		.@"/selection query <info/blocks>" => |cmd| query(source, cmd.mode),
		.@"/selection edit <direction> <amount>" => |cmd| edit(source, cmd.direction, cmd.amount),
		.@"/selection shrink <limit>" => |cmd| shrink(source, @intCast(@as(u31, @truncate(cmd.limit orelse 32)))),
		.@"/selection grow <limit>" => |cmd| autoGrow(source, @intCast(@as(u31, @truncate(cmd.limit orelse 32)))),
	}
}

fn query(source: *User, mode: Mode) void {
	_ = source;
	_ = mode;
}

fn edit(source: *User, direction: Direction, amount: i32) void {
	_ = source;
	_ = direction;
	_ = amount;
}

fn shrink(source: *User, limit: i32) void {
	if (limit <= 1) return; // This is a noop.

	const current = command.getCurrentSelection(source) catch return;

	updateWorldEditPos(source, current.minPos, current.maxPos);

	const minX, const minY, const minZ = current.minPos;
	const maxX, const maxY, const maxZ = current.maxPos;

	const xRange: Range = .init(minX, maxX, 1);
	const yRange: Range = .init(minY, maxY, 1);
	const zRange: Range = .init(minZ, maxZ, 1);

	const newMinX = Search(.xyz).search3D(.init(minX, @min(minX + limit, maxX), 1), yRange, zRange, limit) orelse minX;
	const newMinY = Search(.yxz).search3D(.init(minY, @min(minY + limit, maxY), 1), xRange, zRange, limit) orelse minY;
	const newMinZ = Search(.zyx).search3D(.init(minZ, @min(minZ + limit, maxZ), 1), yRange, xRange, limit) orelse minZ;

	const newMaxX = Search(.xyz).search3D(.init(maxX, @max(minX, maxX - limit), -1), yRange, zRange, limit) orelse maxX;
	const newMaxY = Search(.yxz).search3D(.init(maxY, @max(minY, maxY - limit), -1), xRange, zRange, limit) orelse maxY;
	const newMaxZ = Search(.zyx).search3D(.init(maxZ, @max(minZ, maxZ - limit), -1), yRange, xRange, limit) orelse maxZ;

	updateWorldEditPos(source, .{newMinX, newMinY, newMinZ}, .{newMaxX, newMaxY, newMaxZ});
}

fn updateWorldEditPos(source: *User, pos1: Vec3i, pos2: Vec3i) void {
	source.worldEditData.selectionPosition1 = pos1;
	main.network.protocols.genericUpdate.sendWorldEditPos(source.conn, .selectedPos1, pos1);

	source.worldEditData.selectionPosition2 = pos2;
	main.network.protocols.genericUpdate.sendWorldEditPos(source.conn, .selectedPos2, pos2);
}


fn Search(comptime orientation: enum{xyz, yxz, zyx}) type {
	return struct {
		const Self = @This();

		fn search3D(iRange: Range, jRange: Range, kRange: Range, limit: i32) ?i32 {
			std.log.debug("{s} {} {} {}", .{@tagName(orientation), iRange, jRange, kRange});
			var iLimit: i32 = 0;
			var iIterator = iRange.iter();
			while (iIterator.next()) |i| {
				var jLimit: i32 = 0;

				var jIterator = jRange.iter();
				while (jIterator.next()) |j| {
					var kLimit: i32 = 0;

					var kIterator = kRange.iter();
					while (kIterator.next()) |k| {
						if (Self.getBlock(i, j, k)) |block| {
							if (block.typ != 0) {
								return i;
							}
						}

						kLimit += 1;
						// We didn't even finish scanning one JK plane, so we can't return updated I
						if (kLimit > limit) return null;
					}

					jLimit += 1;
					// We didn't even finish scanning one JK plane, so we can't return updated I
					if (jLimit > limit) return null;
				}

				iLimit += 1;
				// We scanned one JK plane and it was empty (we didn't return) so we can update I
				if (iLimit > limit) return i;
			}
			return null;
		}

		fn getBlock(i: i32, j: i32, k: i32) ?Block {
			return switch (orientation) {
				.xyz => main.server.world.?.getBlock(i, j, k),
				.yxz => main.server.world.?.getBlock(j, i, k),
				.zyx => main.server.world.?.getBlock(k, j, i),
			};
		}
	};
}

const Range = struct {
	start: i32,
	stop: i32,
	step: i32,

	/// Initialize a range.
	/// Start and stop are not allowed to be equal.
	/// When start is smaller than stop, step has to be positive, negative otherwise.
	/// Step is not allowed to be equal to 0.
	pub fn init(start: i32, stop: i32, step: i32) Range {
		std.debug.assert(start != stop);
		std.debug.assert(step != 0);
		std.debug.assert(if (start < stop) step > 0 else step < 0);

		return .{.start = start, .stop = stop, .step = step};
	}

	const Iterator = struct {
		current: i32,
		range: Range,

		fn next(self: *Iterator) ?i32 {
			if (self.current != self.range.stop) {
				defer self.current += self.range.step;
				return self.current;
			} else {
				return null;
			}
		}
	};

	pub fn iter(self: Range) Iterator {
		return .{.current = self.start, .range = self};
	}
};


fn autoGrow(source: *User, limit: ?i32) void {
	_ = source;
	_ = limit;
}