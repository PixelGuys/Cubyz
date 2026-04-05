const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const terrain = main.server.terrain;
const Biome = terrain.biomes.Biome;
const Assets = main.assets.Assets;
const Tag = main.Tag;

pub const CaveLayer = struct {
	minHeight: i32,
	maxHeight: i32,
	layerHeight: i32,
	depthHint: i32,

	biomes: main.utils.AliasTable(*const Biome),
	id: []const u8,

	pub fn init(id: []const u8, zon: ZonElement) ?CaveLayer {
		var result: CaveLayer = undefined;
		result.depthHint = zon.get(?i32, "depthHint", null) orelse {
			std.log.err("Cave layer with id {s} is missing depthHint field. Skipping", .{id});
			return null;
		};
		result.layerHeight = zon.get(?i32, "layerHeight", null) orelse {
			std.log.err("Cave layer with id {s} is missing layerHeight field. Skipping", .{id});
			return null;
		};
		result.id = main.worldArena.dupe(u8, id);

		const tags = Tag.loadTagsFromZon(main.stackAllocator, zon.getChild("tags"));
		defer main.stackAllocator.free(tags);
		var biomes: main.List(*const Biome) = .init(main.stackAllocator);
		defer biomes.deinit();
		outer: for (terrain.biomes.getCaveBiomes()) |*biome| {
			for (tags) |tag| {
				if (biome.hasTag(tag)) {
					biomes.append(biome);
					continue :outer;
				}
			}
		}

		if (biomes.items.len == 0) {
			std.log.err("Cave layer with id {s} has no biomes that match the provided tags. Skipping", .{id});
			return null;
		}
		for (biomes.items) |biome| {
			if (biome.minHeight == std.math.minInt(i32) and biome.maxHeight == std.math.maxInt(i32) and biome.chance != 0) break;
		} else {
			std.log.err("Cave layer with id {s} has no biomes with unbounded height. At least one biome with unbounded height must exist to ensure compatibility with other addons. Skipping", .{id});
			return null;
		}

		result.biomes = .init(main.worldArena, main.worldArena.dupe(*const Biome, biomes.items));

		return result;
	}
};

var finishedLoading: bool = false;
var caveLayers: main.ListUnmanaged(CaveLayer) = .{};

fn register(id: []const u8, zon: ZonElement) void {
	const caveLayer = CaveLayer.init(id, zon) orelse return;
	caveLayers.append(main.worldArena, caveLayer);
}

pub fn registerCaveLayers(caveLayerMap: *Assets.ZonHashMap) !void {
	var iterator = caveLayerMap.iterator();
	while (iterator.next()) |entry| {
		register(entry.key_ptr.*, entry.value_ptr.*);
	}

	std.debug.assert(!finishedLoading);
	finishedLoading = true;

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
	std.log.debug("Registered cave layers:", .{});
	for (caveLayers.items) |caveLayer| {
		std.log.debug("{s}: {} to {}", .{caveLayer.id, caveLayer.minHeight, caveLayer.maxHeight});
	}
}

fn lessThan(_: void, lhs: CaveLayer, rhs: CaveLayer) bool {
	if (lhs.depthHint < rhs.depthHint) return true;
	if (lhs.depthHint > rhs.depthHint) return false;
	return std.ascii.orderIgnoreCase(lhs.id, rhs.id) == .gt;
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
	caveLayers = .{};
}
