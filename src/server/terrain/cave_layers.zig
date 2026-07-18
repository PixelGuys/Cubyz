const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const terrain = main.server.terrain;
const CaveBiomeMapFragment = terrain.CaveBiomeMap.CaveBiomeMapFragment;
const Biome = terrain.biomes.Biome;
const Assets = main.assets.Assets;
const Tag = main.Tag;

pub const CaveLayer = struct {
	minHeight: i32,
	maxHeight: i32,
	layerHeight: i32,
	depthHint: i32,
	caveDensity: f32,
	tags: []Tag,
	biomes: main.utils.AliasTable(*const Biome),
	id: []const u8,

	pub fn init(id: []const u8, zon: ZonElement) ?CaveLayer {
		var result: CaveLayer = undefined;
		result.depthHint = zon.get(i32, "depthHint") orelse {
			std.log.err("Cave layer with id {s} is missing depthHint field. Skipping", .{id});
			return null;
		};
		result.layerHeight = zon.get(i32, "layerHeight") orelse {
			std.log.err("Cave layer with id {s} is missing layerHeight field. Skipping", .{id});
			return null;
		};
		result.caveDensity = zon.get(f32, "caveDensity") orelse 1.0/32.0;
		result.id = main.worldArena.dupe(u8, id);

		result.tags = Tag.loadTagsFromZon(main.worldArena, zon.getChild("tags"));
		if (result.tags.len == 0) {
			std.log.err("Cave layer with id {s} is missing tags. Skipping", .{id});
			return null;
		}
		for (result.tags) |tag| {
			if (!std.mem.endsWith(u8, tag.getName(), "_layer")) {
				std.log.err("Cave layer tags must end with '_layer'. Tag {s} defined in cave layer with id {s} does not. Skipping", .{tag.getName(), id});
				return null;
			}
		}
		return result;
	}
};

var finishedLoading: bool = false;
var caveLayers: main.List(CaveLayer) = .empty;

fn register(id: []const u8, zon: ZonElement) void {
	const caveLayer = CaveLayer.init(id, zon) orelse return;
	caveLayers.append(main.worldArena, caveLayer);
}

pub fn registerCaveLayers(caveLayerMap: *Assets.ZonHashMap) !void {
	//Make cave layers
	var iterator = caveLayerMap.iterator();
	while (iterator.next()) |entry| {
		register(entry.key_ptr.*, entry.value_ptr.*);
	}

	std.mem.sort(CaveLayer, caveLayers.items, {}, lessThan);

	var i: usize = 0;
	while (i + 1 < caveLayers.items.len and caveLayers.items[i].depthHint < 0) {
		i += 1;
	}
	var height = caveLayers.items[i].depthHint;
	for (caveLayers.items[i..]) |*caveLayer| {
		caveLayer.minHeight = height;
		height += caveLayer.layerHeight;
		caveLayer.maxHeight = height;
	}
	height = caveLayers.items[i].depthHint;
	while (i != 0) {
		i -= 1;
		caveLayers.items[i].maxHeight = height;
		height -= caveLayers.items[i].layerHeight;
		caveLayers.items[i].minHeight = height;
	}

	splitCaveLayers();

	std.debug.assert(!finishedLoading);
	finishedLoading = true;

	std.log.debug("Registered cave layers:", .{});
	for (caveLayers.items) |caveLayer| {
		std.log.debug("{s}: {} to {}", .{caveLayer.id, caveLayer.minHeight, caveLayer.maxHeight});
	}
}

pub fn splitCaveLayers() void {
	//Remember where we split
	var splitHeights: main.List(i32) = .empty;
	defer splitHeights.deinit(main.stackAllocator);

	//Add duplicate layers for when we split
	const original_len = caveLayers.items.len;
	for (0..original_len) |i| {
		outer: for (terrain.biomes.getCaveBiomes()) |*biome| {
			for (caveLayers.items[i].tags) |tag| {
				if (biome.hasTag(tag)) {
					if (biome.maxHeight < caveLayers.items[i].maxHeight and biome.maxHeight > caveLayers.items[i].minHeight) {
						var hasSplit: bool = false;
						for (0..splitHeights.items.len) |h| {
							if (splitHeights.items[h] != biome.maxHeight) {
								hasSplit = true;
							}
						}
						if (!hasSplit) {
							caveLayers.append(main.worldArena, caveLayers.items[i]);
							splitHeights.append(main.stackAllocator, biome.maxHeight);
						}
					}
					if (biome.minHeight > caveLayers.items[i].minHeight and biome.minHeight < caveLayers.items[i].maxHeight) {
						var hasSplit: bool = false;
						for (0..splitHeights.items.len) |h| {
							if (splitHeights.items[h] != biome.minHeight) {
								hasSplit = true;
							}
						}
						if (!hasSplit) {
							caveLayers.append(main.worldArena, caveLayers.items[i]);
							splitHeights.append(main.stackAllocator, biome.minHeight);
						}
					}
					continue :outer;
				}
			}
		}
	}

	//Sort new by
	std.mem.sort(CaveLayer, caveLayers.items, {}, lessThan);
	//filter biomes
	for (0..caveLayers.items.len) |i| {
		var biomes: main.List(*const Biome) = .empty;
		defer biomes.deinit(main.stackAllocator);
		outer: for (terrain.biomes.getCaveBiomes()) |*biome| {
			for (caveLayers.items[i].tags) |tag| {
				if (biome.hasTag(tag)) {
					if (caveLayers.items[i].maxHeight > biome.minHeight and caveLayers.items[i].minHeight < biome.maxHeight) {
						if (caveLayers.items[i].maxHeight > biome.maxHeight) {
							//Biome is not full overlap
							caveLayers.items[i].minHeight = biome.maxHeight;
							if (i + 1 < caveLayers.items.len and std.mem.eql(u8, caveLayers.items[i + 1].id, caveLayers.items[i].id)) {
								caveLayers.items[i + 1].maxHeight = biome.maxHeight;
							}
						} else if (caveLayers.items[i].minHeight <= biome.minHeight) {
							//Biome is not full overlap
							caveLayers.items[i].minHeight = biome.minHeight;
							if (i + 1 < caveLayers.items.len and std.mem.eql(u8, caveLayers.items[i + 1].id, caveLayers.items[i].id)) {
								caveLayers.items[i + 1].maxHeight = biome.minHeight;
							}
							biomes.append(main.stackAllocator, biome);
						} else {
							//Biome is full overlap
							biomes.append(main.stackAllocator, biome);
						}
					}
					continue :outer;
				}
			}
		}
		std.debug.assert(biomes.items.len > 0);
		caveLayers.items[i].biomes = .init(main.worldArena, main.worldArena.dupe(*const Biome, biomes.items));
	}
}

fn lessThan(_: void, lhs: CaveLayer, rhs: CaveLayer) bool {
	if (lhs.depthHint < rhs.depthHint) return true;
	if (lhs.depthHint > rhs.depthHint) return false;
	if (lhs.layerHeight < rhs.layerHeight) return true;
	return std.ascii.orderIgnoreCase(lhs.id, rhs.id) == .gt;
}

fn intLessThan(_: void, a: i32, b: i32) bool {
	return a < b;
}

pub fn getLayer(height: i32) CaveLayer {
	var minIndex: usize = 0;
	var maxIndex = caveLayers.items.len - 1;
	while (minIndex != maxIndex) {
		const centerIndex = (minIndex + maxIndex)/2;
		if (caveLayers.items[centerIndex].minHeight > height) {
			maxIndex = centerIndex;
		} else if (caveLayers.items[centerIndex].maxHeight <= height) {
			minIndex = centerIndex + 1;
		} else return caveLayers.items[centerIndex];
	}
	return caveLayers.items[minIndex];
}

pub fn reset() void {
	finishedLoading = false;
	caveLayers = .empty;
}
