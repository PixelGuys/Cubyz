const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ListUnmanaged = main.ListUnmanaged;
const command = main.server.command;
const User = main.server.User;

pub const description = "Teleport to location.";
pub const usage =
	\\/tp <biome>
	\\/tp <x> <y> <z>
	\\/tp @<playerIndex>
;

const Args = union(enum) {
	@"/tp <biome>": struct { biome: struct {
		biome: *const main.server.terrain.biomes.Biome,
		pub fn parse(allocator: NeverFailingAllocator, _: []const u8, args: []const u8, errorMessage: *ListUnmanaged(u8)) error{ParseError}!@This() {
			return .{.biome = main.server.terrain.biomes.getByIdOptional(args) orelse {
				errorMessage.print(allocator, "#ff0000Couldn't find biome with id \"{s}\"", .{args});
				return error.ParseError;
			}};
		}
	} },
	@"/tp <x> <y> <z>": struct {
		x: command.Axis,
		y: command.Axis,
		z: ?command.Axis,
	},
	@"/tp <playerIndex>": struct { playerIndex: command.PlayerIndex },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/tp"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.ListUnmanaged(u8) = .{};
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};

	const pos: main.vec.Vec3d = blk: switch (result) {
		.@"/tp <biome>" => |b| {
			const biome = b.biome.biome;
			if (biome.isCave) {
				source.sendMessage("#ff0000Teleport to biome is only available for surface biomes.", .{});
				return;
			}
			const radius = 16384;
			const mapSize: i32 = main.server.terrain.ClimateMap.ClimateMapFragment.mapSize;
			// Explore chunks in a spiral from the center:
			const spiralLen = 2*radius/mapSize*2*radius/mapSize;
			var wx = source.lastPos[0] & ~(mapSize - 1);
			var wy = source.lastPos[1] & ~(mapSize - 1);
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
						main.network.protocols.genericUpdate.sendTPCoordinates(source.conn, .{@floatFromInt(wx + x*biomeSize + biomeSize/2), @floatFromInt(wy + y*biomeSize + biomeSize/2), @floatCast(z + biomeSize/2)});
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
		.@"/tp <x> <y> <z>" => |pos| {
			break :blk .{
				pos.x.toValue(source.player().pos[0]),
				pos.y.toValue(source.player().pos[1]),
				if (pos.z) |z| z.toValue(source.player().pos[2]) else source.player().pos[2],
			};
		},
		.@"/tp <playerIndex>" => |index| {
			const target = command.Target.fromPlayerIndex(index.playerIndex, source) catch return;
			defer target.deinit();
			break :blk target.user.player().pos;
		},
	};
	main.network.protocols.genericUpdate.sendTPCoordinates(source.conn, pos);
}
