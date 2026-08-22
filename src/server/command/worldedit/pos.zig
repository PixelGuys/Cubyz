const std = @import("std");

const main = @import("main");
const command = main.server.command;
const WorldEditData = main.server.WorldEditData;
const Source = command.Source;
const Vec3i = main.vec.Vec3i;
const Vec3d = main.vec.Vec3d;

pub const description = "Set a world edit selection position 1 or 2.";
pub const usage =
	\\/pos <1/2>
	\\/pos <1/2> <x> <y> <z>
	\\/pos <1/2> @<playerIndex>
;

pub const Args = union(enum) {
	@"/pos <1/2>": struct {
		pos: WorldEditData.Pos,
	},
	@"/pos <1/2> <x> <y> <z>": struct {
		pos: WorldEditData.Pos,
		x: command.Coordinate,
		y: command.Coordinate,
		z: command.Coordinate,
	},
	@"/pos <1/2> @<playerIndex>": struct {
		pos: WorldEditData.Pos,
		x: command.Coordinate,
		y: command.Coordinate,
		z: command.Coordinate,
		playerIndex: command.PlayerIndex,
	},
};

pub fn execute(args: Args, source: Source) void {
	switch (source) {
		.user => |user| {
			const whichPos, const coordinates: Vec3i = blk: switch (args) {
				.@"/pos <1/2>" => |params| {
					const pos: Vec3d = user.player().pos;
					break :blk .{params.pos, @floor(pos)};
				},
				.@"/pos <1/2> <x> <y> <z>" => |params| {
					const posDouble: Vec3d = command.resolveCoordinates(params.x, params.y, params.z, source) catch |err| {
						std.log.err("Failed to resolve coordinates for /pos command: {s}", .{err});
						return;
					};
					break :blk .{params.pos, @floor(posDouble)};
				},
				.@"/pos <1/2> @<playerIndex>" => |params| {
					const target = command.Target.fromPlayerIndex(params.playerIndex, source) catch return;
					const pos: Vec3d = target.user.player().pos;
					break :blk .{params.pos, @floor(pos)};
				},
			};

			user.worldEditData.selectionPosition[@intFromEnum(whichPos)] = coordinates;
			main.network.protocols.genericUpdate.sendWorldEditPos(user.conn, @enumFromInt(@intFromEnum(whichPos)), coordinates);

			user.sendMessage("Position {s}: {}", .{@tagName(whichPos), coordinates});
			if (user.worldEditData.selectionPosition[0]) |pos1| {
				if (user.worldEditData.selectionPosition[1]) |pos2| {
					user.sendMessage("Selection size: {}", .{@max(pos1, pos2) - @min(pos1, pos2) + Vec3i{1, 1, 1}});
				}
			}
		},
		.server => {
			const whichPos, const coordinates: Vec3i = blk: switch (args) {
				.@"/pos <1/2>" => |params| {
					break :blk .{params.pos, .{0, 0, 0}};
				},
				.@"/pos <1/2> <x> <y> <z>" => |params| {
					const posDouble: Vec3d = command.resolveCoordinates(params.x, params.y, params.z, source) catch |err| {
						std.log.err("Failed to resolve coordinates for /pos command: {s}", .{err});
						return;
					};
					break :blk .{params.pos, @floor(posDouble)};
				},
				.@"/pos <1/2> @<playerIndex>" => |params| {
					const target = command.Target.fromPlayerIndex(params.playerIndex, source) catch return;
					const pos: Vec3d = target.user.player().pos;
					break :blk .{params.pos, @floor(pos)};
				},
			};
			main.server.worldEditData.selectionPosition[@intFromEnum(whichPos)] = coordinates;
			std.log.info("Position {s}: {}", .{@tagName(whichPos), coordinates});
		},
	}
}
