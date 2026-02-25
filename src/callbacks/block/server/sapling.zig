const std = @import("std");

const main = @import("main");
const Vec3i = main.vec.Vec3i;
const sbbGen = main.server.terrain.biomes.SimpleStructures.SbbGen;
const SimpleStructureModel = main.server.terrain.biomes.SimpleStructureModel;

structures: main.ZonElement,
sbb: ?*sbbGen.SbbGen,
generationMode: SimpleStructureModel.GenerationMode,
chance: f32,

pub fn init(zon: main.ZonElement) ?*@This() {
	const result = main.worldArena.create(@This());
	result.structures = zon.getChild("sbb").clone(main.worldArena);
	result.sbb = null;
	return result;
}
fn initOfSBB(self: *@This()) void {
	const vtableModel = sbbGen.loadModel(self.structures) orelse {
		std.log.err("Error occurred while loading structure for saplings", .{});
		return;
	};
	self.sbb = vtableModel;
	self.generationMode = std.meta.stringToEnum(SimpleStructureModel.GenerationMode, self.structures.get([]const u8, "generationMode", "")) orelse sbbGen.generationMode;
	self.chance = self.structures.get(f32, "chance", 0.1);
}

pub fn run(self: *@This(), params: main.callbacks.ServerBlockCallback.Params) main.callbacks.Result {
	if (self.sbb == null)
		self.initOfSBB();

	// copied from SimpleStructureGen.generate.
	if (self.sbb) |sbb| {
		const randomValue = main.random.nextFloat(&main.seed);
		if (randomValue < self.chance)
			sbb.placeSbb(sbb.structureRef, Vec3i{params.blockPos.x, params.blockPos.y, params.blockPos.z}, null, sbb.rotation.getInitialRotation(&main.seed), params.chunk, &main.seed, false);
	}

	return .handled;
}
