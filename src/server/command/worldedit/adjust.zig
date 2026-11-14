const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const command = main.server.command;
const Source = command.Source;
const Neighbor = main.chunk.Neighbor;
const User = main.server.User;
const Vec3i = main.vec.Vec3i;
const Mask = main.blueprint.Mask;

pub const description = "Adjust current selection to fit blocks insite.";
pub const usage =
	\\/adjust <limit=32>
	\\  Adjust current selection to fit non air blocks inside.
	\\/adjust <mask> <limit=32>
	\\  Adjust current selection to fit blocks that match the provided mask.
;

pub const Args = union(enum) {
	@"/adjust <mask> <limit>": struct { mask: command.MaskExpression, limit: ?u32 },
	@"/adjust <limit>": struct { limit: ?u32 },
};

pub fn execute(args: Args, source: Source) void {
	if (source != .user) {
		source.sendMessage("Command cannot be run without a user", .{});
		return;
	}
	switch (args) {
		.@"/adjust <mask> <limit>" => |cmd| {
			adjust(.shrink, source.user, cmd.mask.mask, @intCast(@as(u31, @truncate(cmd.limit orelse 32))));
			adjust(.grow, source.user, cmd.mask.mask, @intCast(@as(u31, @truncate(cmd.limit orelse 32))));
		},
		.@"/adjust <limit>" => |cmd| {
			const mask = Mask.initFromString(main.stackAllocator, "!cubyz:air") catch unreachable;
			defer mask.deinit(main.stackAllocator);

			adjust(.shrink, source.user, mask, @intCast(@as(u31, @truncate(cmd.limit orelse 32))));
			adjust(.grow, source.user, mask, @intCast(@as(u31, @truncate(cmd.limit orelse 32))));
		},
	}
}

fn adjust(comptime mode: ScannerMode, source: *User, mask: Mask, limit: i32) void {
	if (limit <= 1) return;

	const current = command.getCurrentSelection(source) catch return;
	const minPos = current.minPos;
	const maxPos = current.maxPos - Vec3i{1, 1, 1};

	if (@reduce(.Or, maxPos - minPos > @as(Vec3i, @splat(limit)))) {
		source.sendMessage("#ff0000Selection is too large to adjust with the current limit ({}) , increase limit or change selection.", .{limit});
		return;
	}

	var scanner: Scanner3D(mode) = .init(minPos, maxPos, mask, limit);
	const newMin, const newMax = scanner.scan3D();

	updateWorldEditPos(source, newMin, newMax);
}

fn updateWorldEditPos(source: *User, pos1: Vec3i, pos2: Vec3i) void {
	source.worldEditData.selectionPosition1 = pos1;
	main.network.protocols.genericUpdate.sendWorldEditPos(source.conn, .selectedPos1, pos1);

	source.worldEditData.selectionPosition2 = pos2;
	main.network.protocols.genericUpdate.sendWorldEditPos(source.conn, .selectedPos2, pos2);
}

const Range = struct {
	start: i32,
	stop: i32,

	/// Initialize a range.
	/// Start and stop are not allowed to be equal.
	pub fn init(start: i32, stop: i32) Range {
		std.debug.assert(start != stop);

		return .{.start = start, .stop = stop};
	}

	const Iterator = struct {
		current: i32,
		range: Range,

		fn next(self: *Iterator) ?i32 {
			if (self.current != self.range.stop) {
				defer self.current +%= 1;
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

const ScannerMode = enum { shrink, grow };

fn Scanner3D(comptime mode: ScannerMode) type {
	return struct {
		const Self = @This();

		min: [3]i32,
		max: [3]i32,

		limit: i32,
		mask: Mask,

		originalMin: [3]i32 = @splat(0),
		originalMax: [3]i32 = @splat(0),

		const Box = struct {
			min: [3]i32,
			max: [3]i32,

			fn eql(self: Box, other: Box) bool {
				return self.min[0] == other.min[0] and self.min[1] == other.min[1] and self.min[2] == other.min[2] and self.max[0] == other.max[0] and self.max[1] == other.max[1] and self.max[2] == other.max[2];
			}
		};

		fn init(min: Vec3i, max: Vec3i, mask: Mask, limit: i32) Self {
			return .{.min = min, .max = max, .mask = mask, .limit = limit};
		}

		fn getRange(self: Self, axis: Neighbor.VectorComponentEnum) Range {
			const i: usize = @intFromEnum(axis);
			return .init(self.min[i], self.max[i] + 1);
		}

		pub fn scan3D(self: *Self) struct { Vec3i, Vec3i } {
			self.originalMin = self.min;
			self.originalMax = self.max;

			// For a simple shrinking process, this could have been much simpler: Just three nested loops in
			// each out of 6 directions would be enough. However, if we want to properly implmenet growing,
			// every consecutive direction of scanning needs to account for the previous iteration results.
			// This is especially important when working with clusters of small objects, which could potentially
			// be cut off if we just kept the original size of the selection and only scanned in a star shape.
			//
			//  Example:
			//   Structure consisting of two L like parts, overalpping but not touching:
			//
			//         **
			//     *    *
			//     **
			//               ┃   ┃
			//               ┃   ┃ * this space is never checked if we don't account for previous iterations
			//      ┏━━━┓    ╋━━━╋━━━
			//      ┃   ┃    ┃ * ┃
			//      ┗━━━┛    ┗━━━┻━━━
			//
			//                           ┃      ┃
			//                     *     ┃    * ┃ if we account for previous iterations we capture clustered objects
			//      ┏━━━┓    ╋━━━╋━━━    ╋━━━━━━╋
			//      ┃   ┃    ┃ * ┃       ┃ *    ┃
			//      ┗━━━┛    ┗━━━┻━━━    ┗━━━━━━┻
			//
			// Now, this code does an extra effort of altering between directions until all are saturated.
			// This part might not be necessary, but I don't think it changes much in the design, so I did it this way.

			while (true) {
				const selectionBefore: Box = .{.min = self.min, .max = self.max};
				for (Neighbor.iterable) |neighbor| {
					switch (mode) {
						.shrink => self.shrink(neighbor),
						.grow => self.grow(neighbor),
					}
				}
				const selectionAfter: Box = .{.min = self.min, .max = self.max};
				if (selectionBefore.eql(selectionAfter)) break;
			}

			return .{self.min, self.max};
		}

		fn getCurrentValue(self: Self, neighbor: Neighbor) i32 {
			const i: usize = @intFromEnum(neighbor.vectorComponent());
			return if (neighbor.isPositive()) self.max[i] else self.min[i];
		}

		fn shrink(self: *Self, neighbor: Neighbor) void {
			const currentValue = self.getCurrentValue(neighbor);

			switch (self.scanPerpendicularPlane(neighbor.vectorComponent(), currentValue)) {
				.stopScan => return,
				.continueScan => {},
			}

			const newValue = self.getCandidate(neighbor);

			if (!self.isValidCandidate(neighbor, newValue)) return;

			if (neighbor.isPositive()) {
				self.max[@intFromEnum(neighbor.vectorComponent())] = newValue;
			} else {
				self.min[@intFromEnum(neighbor.vectorComponent())] = newValue;
			}
		}

		fn grow(self: *Self, neighbor: Neighbor) void {
			const newValue = self.getCandidate(neighbor);

			if (!self.isValidCandidate(neighbor, newValue)) return;

			switch (self.scanPerpendicularPlane(neighbor.vectorComponent(), newValue)) {
				.stopScan => return,
				.continueScan => {},
			}

			if (neighbor.isPositive()) {
				self.max[@intFromEnum(neighbor.vectorComponent())] = newValue;
			} else {
				self.min[@intFromEnum(neighbor.vectorComponent())] = newValue;
			}
		}

		fn getCandidate(self: Self, neighbor: Neighbor) i32 {
			const i: usize = @intFromEnum(neighbor.vectorComponent());
			return switch (mode) {
				.shrink => if (neighbor.isPositive()) self.max[i] - 1 else self.min[i] + 1,
				.grow => if (neighbor.isPositive()) self.max[i] + 1 else self.min[i] - 1,
			};
		}

		/// Check external limits to the iteration - fully collapsing the selection or exceeding the limit of iterations.
		fn isValidCandidate(self: Self, neighbor: Neighbor, newValue: i32) bool {
			const i: usize = @intFromEnum(neighbor.vectorComponent());
			switch (mode) {
				.shrink => if (neighbor.isPositive()) {
					return newValue < self.originalMax[i] and newValue < self.originalMin[i] + self.limit;
				} else {
					return newValue > self.originalMin[i] and newValue > self.originalMax[i] - self.limit;
				},
				.grow => if (neighbor.isPositive()) {
					return newValue < self.originalMax[i] + self.limit;
				} else {
					return newValue > self.originalMin[i] - self.limit;
				},
			}
		}

		/// Scan a 2D plane of blocks perpendicular to the given axis.
		/// `currentValue` determines which of infinitely many planes to choose using a coordinate on `axis`.
		fn scanPerpendicularPlane(self: Self, axis: Neighbor.VectorComponentEnum, currentValue: i32) ScanStatus {
			return switch (axis) {
				.x => Scanner2D(.yz, mode).scanPlane(currentValue, self.getRange(.y), self.getRange(.z), self.mask),
				.y => Scanner2D(.xz, mode).scanPlane(currentValue, self.getRange(.x), self.getRange(.z), self.mask),
				.z => Scanner2D(.yx, mode).scanPlane(currentValue, self.getRange(.y), self.getRange(.x), self.mask),
			};
		}
	};
}

const ScanStatus = enum { continueScan, stopScan };

fn Scanner2D(comptime plane: enum { yz, xz, yx }, comptime mode: ScannerMode) type {
	return struct {
		const Self = @This();

		fn scanPlane(i: i32, jRange: Range, kRange: Range, mask: Mask) ScanStatus {
			var jIterator = jRange.iter();
			while (jIterator.next()) |j| {
				var kIterator = kRange.iter();
				while (kIterator.next()) |k| {
					const x, const y, const z = Self.mapCoordinates(i, j, k);

					if (main.server.world.?.getBlock(x, y, z)) |block| {
						// Finding a non-air block in shrink mode means we have to stop contracting,
						// but in growing mode it means we can continue expading to possibly find more.
						if (mask.match(block)) return if (mode == .shrink) .stopScan else .continueScan;
					}
				}
			}
			return if (mode == .shrink) .continueScan else .stopScan;
		}

		fn mapCoordinates(i: i32, j: i32, k: i32) struct { i32, i32, i32 } {
			return switch (plane) {
				.yz => .{i, j, k},
				.xz => .{j, i, k},
				.yx => .{k, j, i},
			};
		}
	};
}
