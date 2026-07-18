const std = @import("std");

const main = @import("main");
const Vec3i = main.vec.Vec3i;
const sbbGen = main.server.terrain.structures.simple_structures.SbbGen;
const SimpleStructureModel = main.server.terrain.biomes.SimpleStructureModel;

sbb: *sbbGen.SbbGen,
chance: f32,

pub fn init(zon: main.ZonElement, _: main.callbacks.Creator) ?*@This() {
	const result = main.worldArena.create(@This());

	const vtableModel = sbbGen.loadModel(zon.getChild("sbb")) orelse {
		std.log.err("Error occurred while loading structure for saplings", .{});
		return null;
	};
	result.sbb = vtableModel;
	result.chance = zon.get(f32, "chance", 0.1);
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
