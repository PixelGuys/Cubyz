const std = @import("std");

const main = @import("main");
const Vec3i = main.vec.Vec3i;
const SbbGen = main.server.terrain.structures.simple_structures.SbbGen;
const SimpleStructureModel = main.server.terrain.biomes.SimpleStructureModel;

sbb: *SbbGen,
chance: f32,

pub fn init(zon: main.ZonElement, _: main.callbacks.Creator) ?*@This() {
	const result = main.worldArena.create(@This());

	const sbbZon = zon.getChild("sbb");

	const vtableModel = SbbGen.loadModel(sbbZon) orelse {
		std.log.err("Error occurred while loading structure for saplings", .{});
		return null;
	};
	result.sbb = vtableModel;
	result.chance = sbbZon.get(f32, "chance") orelse {
		std.log.err("Missing field \"chance\" for sapling event", .{});
		return null;
	};
	return result;
}

pub fn run(self: *@This(), params: main.callbacks.ServerBlockCallback.Params) main.callbacks.Result {

	// copied from SimpleStructureGen.generate.
	const randomValue = main.random.nextFloat(&main.seed);
	if (randomValue < self.chance) {
		self.sbb.placeSbb(self.sbb.structureRef, Vec3i{params.blockPos.x, params.blockPos.y, params.blockPos.z}, null, self.sbb.rotation.getInitialRotation(&main.seed), params.chunk, &main.seed, false);
	}

	return .handled;
}
