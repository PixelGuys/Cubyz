const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const command = main.server.command;
const User = main.server.User;
const Vec3i = main.vec.Vec3i;

pub const description = "Operate on selection";
pub const usage =
	\\/selection normalize
	\\  Ensure pos1 is set to minimal coordinates and pos2 is set to maximal coordinates from selection.
	\\/selection cube <radius=5>
	\\  Create a cube selection with center at current player position.
	\\/selection shrink <limit=32>
	\\  Automatically shrink the selection to fit a structure, non-air blocks stop shrinking process.
	\\/selection grow <limit=32>
	\\  Automatically grow the selection to fit a structure.
	\\  Non-air blocks stop growing process.
	\\/selection adjust <limit=32>
	\\  Same as grow followed by shrink.
;

const Args = union(enum) {
	@"/selection normalize": struct { subcommand: enum { normalize } },
	@"/selection cube <radius>": struct { subcommand: enum { cube }, radius: ?u32 },
	@"/selection shrink <limit>": struct { subcommand: enum { shrink }, limit: ?u32 },
	@"/selection grow <limit>": struct { subcommand: enum { grow }, limit: ?u32 },
	@"/selection adjust <limit>": struct { subcommand: enum { adjust }, limit: ?u32 },
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
		.@"/selection normalize" => normalize(source),
		.@"/selection cube <radius>" => |cmd| cube(source, @intCast(@as(u31, @truncate(cmd.radius orelse 5)))),
		.@"/selection shrink <limit>" => |cmd| adjust(.shrink, source, @intCast(@as(u31, @truncate(cmd.limit orelse 32)))),
		.@"/selection grow <limit>" => |cmd| adjust(.grow, source, @intCast(@as(u31, @truncate(cmd.limit orelse 32)))),
		.@"/selection adjust <limit>" => |cmd| {
			adjust(.shrink, source, @intCast(@as(u31, @truncate(cmd.limit orelse 32))));
			adjust(.grow, source, @intCast(@as(u31, @truncate(cmd.limit orelse 32))));
		},
	}
}

fn normalize(source: *User) void {
	const current = command.getCurrentSelection(source) catch return;
	const minPos = current.minPos;
	const maxPos = current.maxPos - Vec3i{1, 1, 1};

	updateWorldEditPos(source, minPos, maxPos);
}

fn cube(source: *User, radius: i32) void {
	const pos: Vec3i = @floor(source.player().pos);
	updateWorldEditPos(source, pos - @as(Vec3i, @splat(radius)), pos + @as(Vec3i, @splat(radius)));
}

fn adjust(comptime mode: ScannerMode, source: *User, limit: i32) void {
	if (limit <= 1) return;

	const current = command.getCurrentSelection(source) catch return;
	const minPos = current.minPos;
	const maxPos = current.maxPos - Vec3i{1, 1, 1};

	var scanner: Scanner3D(mode) = .init(minPos, maxPos, limit);
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

const ScannerMode = enum { shrink, grow };

fn Scanner3D(comptime mode: ScannerMode) type {
	return struct {
		const Self = @This();

		min: [3]i32,
		max: [3]i32,

		limit: i32,

		originalMin: [3]i32 = @splat(0),
		originalMax: [3]i32 = @splat(0),

		const Axis = enum(u2) {
			x = 0,
			y = 1,
			z = 2,
			const iterator: [3]Axis = .{.x, .y, .z};
		};
		const Candidate = enum(u1) {
			min = 0,
			max = 1,
			const iterator: [2]Candidate = .{.min, .max};
		};
		const Stage = struct {
			axis: Axis,
			candidate: Candidate,
			isComplete: bool,
		};

		fn init(min: Vec3i, max: Vec3i, limit: i32) Self {
			return .{.min = min, .max = max, .limit = limit};
		}

		fn getRange(self: Self, axis: Axis) Range {
			const i: usize = @intFromEnum(axis);
			return .init(self.min[i], self.max[i] + 1, 1);
		}

		pub fn scan3D(self: *Self) struct { Vec3i, Vec3i } {
			self.originalMin = self.min;
			self.originalMax = self.max;

			var scanningSequence: [6]Stage = .{
				.{.axis = .x, .candidate = .min, .isComplete = false},
				.{.axis = .x, .candidate = .max, .isComplete = false},
				.{.axis = .y, .candidate = .min, .isComplete = false},
				.{.axis = .y, .candidate = .max, .isComplete = false},
				.{.axis = .z, .candidate = .min, .isComplete = false},
				.{.axis = .z, .candidate = .max, .isComplete = false},
			};

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

			while (true) doScan: {
				for (&scanningSequence) |*stage| {
					if (stage.isComplete) continue;

					switch (mode) {
						.shrink => self.shrink(stage),
						.grow => self.grow(stage),
					}
				}
				for (scanningSequence) |stage| if (!stage.isComplete) break :doScan;
				break;
			}

			return .{self.min, self.max};
		}

		fn getCurrentValue(self: Self, axis: Axis, candidate: Candidate) i32 {
			const i: usize = @intFromEnum(axis);
			return switch (candidate) {
				.min => self.min[i],
				.max => self.max[i],
			};
		}

		fn shrink(self: *Self, stage: *Stage) void {
			const currentValue = self.getCurrentValue(stage.axis, stage.candidate);

			switch (self.scanPerpendicularPlane(stage.axis, currentValue)) {
				.failure, .limitExceeded => {
					stage.isComplete = true;
					return;
				},
				.success => {},
			}

			const newValue = self.getCandidate(stage.axis, stage.candidate);

			if (!self.isValidCandidate(stage.axis, stage.candidate, newValue)) {
				stage.isComplete = true;
				return;
			}

			switch (stage.candidate) {
				.min => self.min[@intFromEnum(stage.axis)] = newValue,
				.max => self.max[@intFromEnum(stage.axis)] = newValue,
			}
		}

		fn grow(self: *Self, stage: *Stage) void {
			const newValue = self.getCandidate(stage.axis, stage.candidate);

			if (!self.isValidCandidate(stage.axis, stage.candidate, newValue)) {
				stage.isComplete = true;
				return;
			}

			switch (self.scanPerpendicularPlane(stage.axis, newValue)) {
				.failure, .limitExceeded => {
					stage.isComplete = true;
					return;
				},
				.success => {},
			}

			switch (stage.candidate) {
				.min => self.min[@intFromEnum(stage.axis)] = newValue,
				.max => self.max[@intFromEnum(stage.axis)] = newValue,
			}
		}

		fn getCandidate(self: Self, axis: Axis, candidate: Candidate) i32 {
			const i: usize = @intFromEnum(axis);
			return switch (mode) {
				.shrink => switch (candidate) {
					.min => self.min[i] + 1,
					.max => self.max[i] - 1,
				},
				.grow => switch (candidate) {
					.min => self.min[i] - 1,
					.max => self.max[i] + 1,
				},
			};
		}

		/// Check external limits to the iteration - fully collapsing the selection or exceeding the limit of iterations.
		fn isValidCandidate(self: Self, axis: Axis, candidate: Candidate, newValue: i32) bool {
			const i: usize = @intFromEnum(axis);
			return switch (mode) {
				.shrink => switch (candidate) {
					.min => newValue < self.originalMax[i] and newValue < self.originalMin[i] + self.limit,
					.max => newValue > self.originalMin[i] and newValue > self.originalMax[i] - self.limit,
				},
				.grow => switch (candidate) {
					.min => newValue > self.originalMin[i] - self.limit,
					.max => newValue < self.originalMax[i] + self.limit,
				},
			};
		}

		/// Scan a 2D plane of blocks perpendicular to the given axis.
		/// `currentValue` determines which of infinitely many planes to choose using a coordinate on `axis`.
		fn scanPerpendicularPlane(self: Self, axis: Axis, currentValue: i32) ScanStatus {
			return switch (axis) {
				.x => Scanner2D(.yz, mode).scanPlane(currentValue, self.getRange(.y), self.getRange(.z), self.limit),
				.y => Scanner2D(.xz, mode).scanPlane(currentValue, self.getRange(.x), self.getRange(.z), self.limit),
				.z => Scanner2D(.yx, mode).scanPlane(currentValue, self.getRange(.y), self.getRange(.x), self.limit),
			};
		}
	};
}

const ScanStatus = enum { success, failure, limitExceeded };

fn Scanner2D(comptime plane: enum { yz, xz, yx }, comptime mode: ScannerMode) type {
	return struct {
		const Self = @This();

		fn scanPlane(i: i32, jRange: Range, kRange: Range, limit: i32) ScanStatus {
			var jLimit: i32 = 0;

			var jIterator = jRange.iter();
			while (jIterator.next()) |j| {
				var kLimit: i32 = 0;

				var kIterator = kRange.iter();
				while (kIterator.next()) |k| {
					const x, const y, const z = Self.mapCoordinates(i, j, k);

					if (main.server.world.?.getBlock(x, y, z)) |block| {
						// Finding a non-air block in shrink mode means we have to stop contracting,
						// but in growing mode it means we can continue expading to possibly find more.
						if (block.typ != 0) return if (mode == .shrink) .failure else .success;
					}

					kLimit += 1;
					// We didn't even finish scanning one JK plane, so we can't return updated I
					if (kLimit > limit) return .limitExceeded;
				}

				jLimit += 1;
				// We didn't even finish scanning one JK plane, so we can't return updated I
				if (jLimit > limit) return .limitExceeded;
			}
			return if (mode == .shrink) .success else .failure;
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
