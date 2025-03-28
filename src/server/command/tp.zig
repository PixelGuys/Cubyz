const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Teleport to location.";
pub const usage = "/tp <x> <y>\n/tp <x> <y> <z>\n/tp <biome>";

pub fn execute(args: []const u8, source: *User) void {
	if(std.mem.containsAtLeast(u8, args, 1, ":")) {
		const biome = main.server.terrain.biomes.getById(args);
		if(!std.mem.eql(u8, biome.id, args)) {
			source.sendMessage("#ff0000Couldn't find biome with id \"{s}\"", .{args});
			return;
		}
		if(biome.isCave) {
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
		for(0..spiralLen) |_| {
			const map = main.server.terrain.ClimateMap.getOrGenerateFragmentAndIncreaseRefCount(wx, wy);
			defer map.decreaseRefCount();
			for(0..map.map.len) |_| {
				const x = main.random.nextIntBounded(u31, &main.seed, map.map.len);
				const y = main.random.nextIntBounded(u31, &main.seed, map.map.len);
				const sample = map.map[x][y];
				if(sample.biome == biome) {
					const z = sample.height + sample.hills + sample.mountains + sample.roughness;
					const biomeSize = main.server.terrain.SurfaceMap.MapFragment.biomeSize;
					main.network.Protocols.genericUpdate.sendTPCoordinates(source.conn, .{@floatFromInt(wx + x*biomeSize + biomeSize/2), @floatFromInt(wy + y*biomeSize + biomeSize/2), @floatCast(z + biomeSize/2)});
					return;
				}
			}
			switch(dir) {
				.dirNegX => wx -%= mapSize,
				.dirPosX => wx +%= mapSize,
				.dirNegY => wy -%= mapSize,
				.dirPosY => wy +%= mapSize,
				else => unreachable,
			}
			stepsRemaining -= 1;
			if(stepsRemaining == 0) {
				switch(dir) {
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
	}
	var x: ?f64 = null;
	var y: ?f64 = null;
	var z: ?f64 = null;
	var split = std.mem.splitScalar(u8, args, ' ');
	while(split.next()) |arg| {
		const num: f64 = std.fmt.parseFloat(f64, arg) catch {
			source.sendMessage("#ff0000Expected number, found \"{s}\"", .{arg});
			return;
		};
		if(x == null) {
			x = num;
		} else if(y == null) {
			y = num;
		} else if(z == null) {
			z = num;
		} else {
			source.sendMessage("#ff0000Too many arguments for command /tp", .{});
			return;
		}
	}
	if(x == null or y == null) {
		source.sendMessage("#ff0000Too few arguments for command /tp", .{});
		return;
	}
	if(z == null) {
		z = source.player.pos[2];
	}
	x = std.math.clamp(x.?, -1e9, 1e9); // TODO: Remove after #310 is implemented
	y = std.math.clamp(y.?, -1e9, 1e9);
	z = std.math.clamp(z.?, -1e9, 1e9);
	main.network.Protocols.genericUpdate.sendTPCoordinates(source.conn, .{x.?, y.?, z.?});
}
