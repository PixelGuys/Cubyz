const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Source = command.Source;

pub const description = "Teleport to location.";
pub const usage =
	\\/tp <biome>
	\\/tp @<sourcePlayerIndex> <biome>
	\\/tp <x> <y> <z>
	\\/tp @<sourcePlayerIndex> <x> <y> <z>
	\\/tp @<destinationPlayerIndex>
	\\/tp @<sourcePlayerIndex> @<destinationPlayerIndex>
;

pub const Args = union(enum) {
	@"/tp <sourcePlayerIndex> <biome>": struct {
		sourcePlayerIndex: ?command.PlayerIndex,
		biome: command.BiomeId,
	},
	@"/tp <sourcePlayerIndex> <x> <y> <z>": struct {
		sourcePlayerIndex: ?command.PlayerIndex,
		x: command.Coordinate,
		y: command.Coordinate,
		z: command.Coordinate,
	},
	@"/tp <destinationPlayerIndex>": struct {
		destinationPlayerIndex: command.PlayerIndex,
	},
	@"/tp <sourcePlayerIndex> <destinationPlayerIndex>": struct {
		sourcePlayerIndex: command.PlayerIndex,
		destinationPlayerIndex: command.PlayerIndex,
	},
};

pub fn execute(args: Args, source: Source) void {
	const target = switch (args) {
		inline .@"/tp <sourcePlayerIndex> <biome>",
		.@"/tp <sourcePlayerIndex> <x> <y> <z>",
		.@"/tp <sourcePlayerIndex> <destinationPlayerIndex>",
		=> |params| command.Target.fromPlayerIndex(params.sourcePlayerIndex, source) catch return,
		else => command.Target.fromPlayerIndex(null, source) catch return,
	};
	const pos: main.vec.Vec3d = blk: switch (args) {
		.@"/tp <sourcePlayerIndex> <biome>" => |b| {
			const user = target.user;
			const biome = b.biome.biome;
			if (biome.isCave) {
				source.sendMessage("#ff0000Teleport to biome is only available for surface biomes.", .{});
				return;
			}
			const radius = 16384;
			const mapSize: i32 = main.server.terrain.ClimateMap.ClimateMapFragment.mapSize;
			// Explore chunks in a spiral from the center:
			const spiralLen = 2*radius/mapSize*2*radius/mapSize;
			var wx = user.lastPos[0] & ~(mapSize - 1);
			var wy = user.lastPos[1] & ~(mapSize - 1);
			var dirChanges: usize = 1;
			var dir: main.chunk.Neighbor = .dirNegX;
			var stepsRemaining: usize = 1;
			for (0..spiralLen) |_| {
				const map = main.server.terrain.ClimateMap.getOrGenerateFragment(wx, wy);
				for (0..map.map.len) |_| {
					const x = main.random.nextIntBounded(u31, &main.seed, map.map.len);
					const y = main.random.nextIntBounded(u31, &main.seed, map.map.len);
					const sample = map.map[x][y];
					if (sample.biome == biome) {
						const z = sample.height + sample.hills + sample.mountains + sample.roughness;
						const biomeSize = main.server.terrain.SurfaceMap.MapFragment.biomeSize;
						main.network.protocols.genericUpdate.sendTPCoordinates(user.conn, .{@floatFromInt(wx + x*biomeSize + biomeSize/2), @floatFromInt(wy + y*biomeSize + biomeSize/2), @floatCast(z + biomeSize/2)});
						return;
					}
				}
				switch (dir) {
					.dirNegX => wx -%= mapSize,
					.dirPosX => wx +%= mapSize,
					.dirNegY => wy -%= mapSize,
					.dirPosY => wy +%= mapSize,
					else => unreachable,
				}
				stepsRemaining -= 1;
				if (stepsRemaining == 0) {
					switch (dir) {
						.dirNegX => dir = .dirNegY,
						.dirPosX => dir = .dirPosY,
						.dirNegY => dir = .dirPosX,
						.dirPosY => dir = .dirNegX,
						else => unreachable,
					}
					dirChanges += 1;
					// Every second turn the number of steps needed doubles.
					stepsRemaining = dirChanges/2;
				}
			}
			source.sendMessage("#ff0000Couldn't find biome. Searched in a radius of 16384 blocks.", .{});
			return;
		},
		.@"/tp <sourcePlayerIndex> <x> <y> <z>" => |pos| {
			break :blk command.resolveCoordinates(pos.x, pos.y, pos.z, source) catch return;
		},
		inline .@"/tp <destinationPlayerIndex>", .@"/tp <sourcePlayerIndex> <destinationPlayerIndex>" => |index| {
			const dest = command.Target.fromPlayerIndex(index.destinationPlayerIndex, source) catch return;
			break :blk dest.user.player().pos;
		},
	};
	main.network.protocols.genericUpdate.sendTPCoordinates(target.user.conn, pos);
}
