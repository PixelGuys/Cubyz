const std = @import("std");

const main = @import("main");
const SimpleStructureModel = main.server.terrain.biomes.SimpleStructureModel;

structures: main.ZonElement,
vegetationModels: ?[]SimpleStructureModel,

pub fn init(zon: main.ZonElement) ?*@This() {
	const result = main.worldArena.create(@This());
	result.structures = zon.getChild("structures").clone(main.worldArena);
	result.vegetationModels = null;
	return result;
}

//TODO: no deinits yet

fn initAfterBiomesHaveBeenInited(self: *@This()) void {
	var vegetation = main.ListUnmanaged(SimpleStructureModel){};
	var totalChance: f32 = 0;
	defer vegetation.deinit(main.stackAllocator);
	for (self.structures.toSlice()) |elem| {
		if (SimpleStructureModel.initModel(elem)) |model| {
			vegetation.append(main.stackAllocator, model);
			totalChance += model.chance;
		}
	}
	if (totalChance > 1) {
		for (vegetation.items) |*model| {
			model.chance /= totalChance;
		}
	}
	self.vegetationModels = main.worldArena.dupe(SimpleStructureModel, vegetation.items);
}

pub fn run(self: *@This(), params: main.callbacks.ServerBlockCallback.Params) main.callbacks.Result {
	if (self.vegetationModels == null)
		self.initAfterBiomesHaveBeenInited();
	const vegetationModels = self.vegetationModels.?;

	const wx = params.chunk.super.pos.wx + params.blockPos.x;
	const wy = params.chunk.super.pos.wy + params.blockPos.y;
	const wz = params.chunk.super.pos.wz + params.blockPos.z;
	const ch = params.chunk;

	// the originals have already deinited long time ago at this point :(
	const caveMap = main.server.terrain.CaveMap.CaveMapView.init(main.stackAllocator, ch.super.pos, ch.super.width, 32);
	defer caveMap.deinit(main.stackAllocator);
	const biomeMap = main.server.terrain.CaveBiomeMap.CaveBiomeMapView.init(main.stackAllocator, ch.super.pos, ch.super.width, 32);
	defer biomeMap.deinit();

	//copied from SimpleStructureGen.generate.
	var seed = main.random.initSeed3D(main.seed, .{wx, wy, wz});
	var randomValue = main.random.nextFloat(&seed);
	for (vegetationModels) |*model| { // TODO: Could probably use an alias table here.
		if (randomValue < model.chance) {

			//const heightFinalized = adjustToCaveMap(biomeMap, caveMap, wpx, wpy, map.pos.wz +% relZ, model, &seed) orelse break;
			model.generate(params.blockPos.x, params.blockPos.y, params.blockPos.z, params.chunk, caveMap, biomeMap, &main.seed, false, false);
			//ch.setChanged();
			//const data = map.allocator.create(SimpleStructure);
			// data.* = .{
			// .wx = wpx,
			// .wy = wpy,
			// .wz = map.pos.wz +% heightFinalized.relZ,
			// .seed = seed,
			// .model = model,
			// .isCeiling = heightFinalized.isCeiling,
			// };
			// if(model.generationMode == .water_surface) {
			// if(wpz != 0) break;
			// data.wz = 0;
			// }
			// map.addStructure(.{
			// .internal = .{
			// .data = @ptrCast(data),
			// .generateFn = &SimpleStructure.generate,
			// },
			// .priority = model.priority,
			// }, .{px -% margin, py -% margin, data.wz -% map.pos.wz -% marginZ}, .{px +% margin, py +% margin, data.wz -% map.pos.wz +% marginZ});

			break;
		} else {
			randomValue -= model.chance;
		}
	}

	return .handled;
}
