const std = @import("std");

const blocks = @import("blocks.zig");
const Block = blocks.Block;
const graphics = @import("graphics.zig");
const Color = graphics.Color;
const JsonElement = @import("json.zig").JsonElement;
const main = @import("main.zig");
const chunk = main.chunk;
const random = @import("random.zig");
const vec = @import("vec.zig");
const Mat4f = vec.Mat4f;
const Vec2f = vec.Vec2f;
const Vec2i = vec.Vec2i;
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;

/// Holds the basic properties of a tool crafting material.
const Material = struct {
	/// how much it weighs
	density: f32 = undefined,
	/// how long it takes until the tool breaks
	resistance: f32 = undefined,
	/// how useful it is for block breaking
	power: f32 = undefined,

	/// How rough the texture should look.
	roughness: f32 = undefined,
	/// The colors that are used to make tool textures.
	colorPalette: []Color = undefined,

	pub fn init(self: *Material, allocator: NeverFailingAllocator, json: JsonElement) void {
		self.density = json.get(f32, "density", 1.0);
		self.resistance = json.get(f32, "resistance", 1.0);
		self.power = json.get(f32, "power", 1.0);
		self.roughness = @max(0, json.get(f32, "roughness", 1.0));
		const colors = json.getChild("colors");
		self.colorPalette = allocator.alloc(Color, colors.JsonArray.items.len);
		for(colors.JsonArray.items, self.colorPalette) |item, *color| {
			const colorInt: u32 = @intCast(item.as(i64, 0xff000000) & 0xffffffff);
			color.* = Color {
				.r = @intCast(colorInt>>16 & 0xff),
				.g = @intCast(colorInt>>8 & 0xff),
				.b = @intCast(colorInt>>0 & 0xff),
				.a = @intCast(colorInt>>24 & 0xff),
			};
		}
	}

	pub fn hashCode(self: Material) u32 {
		var hash: u32 = @bitCast(self.density);
		hash = 101*%hash +% @as(u32, @bitCast(self.resistance));
		hash = 101*%hash +% @as(u32, @bitCast(self.power));
		hash = 101*%hash +% @as(u32, @bitCast(self.roughness));
		hash ^= hash >> 24;
		return hash;
	}
};


pub const BaseItem = struct {
	image: graphics.Image,
	texture: ?graphics.Texture, // TODO: Properly deinit
	id: []const u8,
	name: []const u8,

	stackSize: u16,
	material: ?Material,
	block: ?u16,
	foodValue: f32, // TODO: Effects.

	leftClickUse: ?*const fn(world: *main.game.World, pos: Vec3i, relativePlayerPos: Vec3f, playerDir: Vec3f, currentData: *Block) bool,

	var unobtainable = BaseItem {
		.image = graphics.Image.defaultImage,
		.texture = null,
		.id = "unobtainable",
		.name = "unobtainable",
		.stackSize = 0,
		.material = null,
		.block = null,
		.foodValue = 0,
		.leftClickUse = null,
	};

	fn init(self: *BaseItem, allocator: NeverFailingAllocator, texturePath: []const u8, replacementTexturePath: []const u8, id: []const u8, json: JsonElement) void {
		self.id = allocator.dupe(u8, id);
		if(texturePath.len == 0) {
			self.image = graphics.Image.defaultImage;
		} else {
			self.image = graphics.Image.readFromFile(allocator, texturePath) catch graphics.Image.readFromFile(allocator, replacementTexturePath) catch blk: {
				std.log.err("Item texture not found in {s} and {s}.", .{texturePath, replacementTexturePath});
				break :blk graphics.Image.defaultImage;
			};
		}
		self.name = allocator.dupe(u8, json.get([]const u8, "name", id));
		self.stackSize = json.get(u16, "stackSize", 64);
		const material = json.getChild("material");
		if(material == .JsonObject) {
			self.material = Material{};
			self.material.?.init(allocator, material);
		} else {
			self.material = null;
		}
		self.block = blk: {
			break :blk blocks.getByID(json.get(?[]const u8, "block", null) orelse break :blk null);
		};
		self.texture = null;
		self.foodValue = json.get(f32, "food", 0);
		self.leftClickUse = if(std.mem.eql(u8, json.get([]const u8, "onLeftUse", ""), "chisel")) &chiselFunction else null; // TODO: Proper registry.
	}

	fn chiselFunction(world: *main.game.World, pos: Vec3i, relativePlayerPos: Vec3f, playerDir: Vec3f, currentData: *Block) bool {
		if(currentData.mode() == main.rotation.getByID("stairs")) {
			return main.rotation.RotationModes.Stairs.chisel(world, pos, relativePlayerPos, playerDir, currentData);
		}
		return false;
	}

	fn hashCode(self: BaseItem) u32 {
		var hash: u32 = 0;
		for(self.id) |char| {
			hash = hash*%33 +% char;
		}
		return hash;
	}

	pub fn getTexture(self: *BaseItem) graphics.Texture {
		if(self.texture == null) {
			if(self.block) |blockType| {
				self.texture = graphics.generateBlockTexture(blockType);
			} else {
				self.texture = graphics.Texture.init();
				self.texture.?.generate(self.image);
			}
		}
		return self.texture.?;
	}

	fn getTooltip(self: BaseItem) []const u8 {
		return self.name;
	}
};

///Generates the texture of a Tool using the material information.
const TextureGenerator = struct {
	/// Used to translate between grid and pixel coordinates.
	pub const GRID_CENTERS_X = [_]u8 {
		2, 5, 8, 11, 14,
		2, 5, 8, 11, 14,
		2, 5, 8, 11, 14,
		2, 5, 8, 11, 14,
		2, 5, 8, 11, 14,
	};
	/// Used to translate between grid and pixel coordinates.
	pub const GRID_CENTERS_Y = [_]u8  {
		2, 2, 2, 2, 2,
		5, 5, 5, 5, 5,
		8, 8, 8, 8, 8,
		11, 11, 11, 11, 11,
		14, 14, 14, 14, 14,
	};
	
	/// Contains the material(s) of a single pixel and tries to avoid multiple materials.
	const PixelData = struct {
		maxNeighbors: u8 = 0,
		items: main.List(*const BaseItem),
		pub fn init(allocator: NeverFailingAllocator) PixelData {
			return PixelData {
				.items = main.List(*const BaseItem).init(allocator),
			};
		}
		pub fn deinit(self: *PixelData) void {
			self.items.clearAndFree();
		}
		pub fn add(self: *PixelData, item: *const BaseItem, neighbors: u8) void {
			if(neighbors > self.maxNeighbors) {
				self.maxNeighbors = neighbors;
				self.items.clearRetainingCapacity();
			}
			if(neighbors == self.maxNeighbors) {
				self.items.append(item);
			}
		}
	};

	/// Counts the neighbors, while prioritizing direct neighbors over diagonals.
	fn countNeighbors(relativeGrid: *[25]?*const BaseItem) u8 {
		var neighbors: u8 = 0;
		// direct neighbors count 1.5 times as much.
		if(relativeGrid[7] != null) neighbors += 3;
		if(relativeGrid[11] != null) neighbors += 3;
		if(relativeGrid[13] != null) neighbors += 3;
		if(relativeGrid[17] != null) neighbors += 3;

		if(relativeGrid[6] != null) neighbors += 2;
		if(relativeGrid[8] != null) neighbors += 2;
		if(relativeGrid[16] != null) neighbors += 2;
		if(relativeGrid[18] != null) neighbors += 2;

		return neighbors;
	}

	/// This part is responsible for associating each pixel with an item.
	fn drawRegion(relativeGrid: *[25]?*const BaseItem, relativeNeighborCount: *[25]u8, x: u8, y: u8, pixels: *[16][16]PixelData) void {
		if(relativeGrid[12]) |item| {
			// Count diagonal and straight neighbors:
			var diagonalNeighbors: u8 = 0;
			var straightNeighbors: u8 = 0;
			if(relativeGrid[7] != null) straightNeighbors += 1;
			if(relativeGrid[11] != null) straightNeighbors += 1;
			if(relativeGrid[13] != null) straightNeighbors += 1;
			if(relativeGrid[17] != null) straightNeighbors += 1;

			if(relativeGrid[6] != null) diagonalNeighbors += 1;
			if(relativeGrid[8] != null) diagonalNeighbors += 1;
			if(relativeGrid[16] != null) diagonalNeighbors += 1;
			if(relativeGrid[18] != null) diagonalNeighbors += 1;

			const neighbors = diagonalNeighbors + straightNeighbors;

			pixels[x + 1][y + 1].add(item, relativeNeighborCount[12]);
			pixels[x + 1][y + 2].add(item, relativeNeighborCount[12]);
			pixels[x + 2][y + 1].add(item, relativeNeighborCount[12]);
			pixels[x + 2][y + 2].add(item, relativeNeighborCount[12]);

			// Checkout straight neighbors:
			if(relativeGrid[7] != null) {
				if(relativeNeighborCount[7] >= relativeNeighborCount[12]) {
					pixels[x + 1][y].add(item, relativeNeighborCount[12]);
					pixels[x + 2][y].add(item, relativeNeighborCount[12]);
				}
				if(relativeGrid[1] != null and relativeGrid[16] == null and straightNeighbors <= 1) {
					pixels[x + 2][y + 3].add(item, relativeNeighborCount[12]);
				}
				if(relativeGrid[3] != null and relativeGrid[18] == null and straightNeighbors <= 1) {
					pixels[x + 1][y + 3].add(item, relativeNeighborCount[12]);
				}
			}
			if(relativeGrid[11] != null) {
				if(relativeNeighborCount[11] >= relativeNeighborCount[12]) {
					pixels[x][y + 1].add(item, relativeNeighborCount[12]);
					pixels[x][y + 2].add(item, relativeNeighborCount[12]);
				}
				if(relativeGrid[5] != null and relativeGrid[8] == null and straightNeighbors <= 1) {
					pixels[x + 3][y + 2].add(item, relativeNeighborCount[12]);
				}
				if(relativeGrid[15] != null and relativeGrid[18] == null and straightNeighbors <= 1) {
					pixels[x + 3][y + 1].add(item, relativeNeighborCount[12]);
				}
			}
			if(relativeGrid[13] != null) {
				if(relativeNeighborCount[13] >= relativeNeighborCount[12]) {
					pixels[x + 3][y + 1].add(item, relativeNeighborCount[12]);
					pixels[x + 3][y + 2].add(item, relativeNeighborCount[12]);
				}
				if(relativeGrid[9] != null and relativeGrid[6] == null and straightNeighbors <= 1) {
					pixels[x][y + 2].add(item, relativeNeighborCount[12]);
				}
				if(relativeGrid[19] != null and relativeGrid[16] == null and straightNeighbors <= 1) {
					pixels[x][y + 1].add(item, relativeNeighborCount[12]);
				}
			}
			if(relativeGrid[17] != null) {
				if(relativeNeighborCount[17] >= relativeNeighborCount[12]) {
					pixels[x + 1][y + 3].add(item, relativeNeighborCount[12]);
					pixels[x + 2][y + 3].add(item, relativeNeighborCount[12]);
				}
				if(relativeGrid[21] != null and relativeGrid[6] == null and straightNeighbors <= 1) {
					pixels[x + 2][y].add(item, relativeNeighborCount[12]);
				}
				if(relativeGrid[23] != null and relativeGrid[8] == null and straightNeighbors <= 1) {
					pixels[x + 1][y].add(item, relativeNeighborCount[12]);
				}
			}

			// Checkout diagonal neighbors:
			if(relativeGrid[6] != null) {
				if(relativeNeighborCount[6] >= relativeNeighborCount[12]) {
					pixels[x][y].add(item, relativeNeighborCount[12]);
				}
				pixels[x + 1][y].add(item, relativeNeighborCount[12]);
				pixels[x][y + 1].add(item, relativeNeighborCount[12]);
				if(relativeGrid[1] != null and relativeGrid[7] == null and neighbors <= 2) {
					pixels[x + 3][y + 2].add(item, relativeNeighborCount[12]);
				}
				if(relativeGrid[5] != null and relativeGrid[11] == null and neighbors <= 2) {
					pixels[x + 2][y + 3].add(item, relativeNeighborCount[12]);
				}
			}
			if(relativeGrid[8] != null) {
				if(relativeNeighborCount[8] >= relativeNeighborCount[12]) {
					pixels[x + 3][y].add(item, relativeNeighborCount[12]);
				}
				pixels[x + 2][y].add(item, relativeNeighborCount[12]);
				pixels[x + 3][y + 1].add(item, relativeNeighborCount[12]);
				if(relativeGrid[3] != null and relativeGrid[7] == null and neighbors <= 2) {
					pixels[x][y + 2].add(item, relativeNeighborCount[12]);
				}
				if(relativeGrid[9] != null and relativeGrid[13] == null and neighbors <= 2) {
					pixels[x + 1][y + 3].add(item, relativeNeighborCount[12]);
				}
			}
			if(relativeGrid[16] != null) {
				if(relativeNeighborCount[16] >= relativeNeighborCount[12]) {
					pixels[x][y + 3].add(item, relativeNeighborCount[12]);
				}
				pixels[x][y + 2].add(item, relativeNeighborCount[12]);
				pixels[x + 1][y + 3].add(item, relativeNeighborCount[12]);
				if(relativeGrid[21] != null and relativeGrid[17] == null and neighbors <= 2) {
					pixels[x + 3][y + 1].add(item, relativeNeighborCount[12]);
				}
				if(relativeGrid[15] != null and relativeGrid[11] == null and neighbors <= 2) {
					pixels[x + 2][y].add(item, relativeNeighborCount[12]);
				}
			}
			if(relativeGrid[18] != null) {
				if(relativeNeighborCount[18] >= relativeNeighborCount[12]) {
					pixels[x + 3][y + 3].add(item, relativeNeighborCount[12]);
				}
				pixels[x + 2][y + 3].add(item, relativeNeighborCount[12]);
				pixels[x + 3][y + 2].add(item, relativeNeighborCount[12]);
				if(relativeGrid[23] != null and relativeGrid[17] == null and neighbors <= 2) {
					pixels[x][y + 1].add(item, relativeNeighborCount[12]);
				}
				if(relativeGrid[19] != null and relativeGrid[13] == null and neighbors <= 2) {
					pixels[x + 1][y].add(item, relativeNeighborCount[12]);
				}
			}

			// Make stuff more round when there is many incoming connections:
			if(diagonalNeighbors >= 3 or straightNeighbors == 4) {
				pixels[x + 0][y + 1].add(item, relativeNeighborCount[12]);
				pixels[x + 0][y + 2].add(item, relativeNeighborCount[12]);
				pixels[x + 3][y + 1].add(item, relativeNeighborCount[12]);
				pixels[x + 3][y + 2].add(item, relativeNeighborCount[12]);
				pixels[x + 1][y + 0].add(item, relativeNeighborCount[12]);
				pixels[x + 1][y + 3].add(item, relativeNeighborCount[12]);
				pixels[x + 2][y + 0].add(item, relativeNeighborCount[12]);
				pixels[x + 2][y + 3].add(item, relativeNeighborCount[12]);
				// Check which of the neighbors was empty:
				if(relativeGrid[6] == null) {
					pixels[x + 0][y + 0].add(item, relativeNeighborCount[12]);
					pixels[x + 2][y - 1].add(item, relativeNeighborCount[12]);
					pixels[x - 1][y + 2].add(item, relativeNeighborCount[12]);
				}
				if(relativeGrid[8] == null) {
					pixels[x + 3][y + 0].add(item, relativeNeighborCount[12]);
					pixels[x + 1][y - 1].add(item, relativeNeighborCount[12]);
					pixels[x + 4][y + 2].add(item, relativeNeighborCount[12]);
				}
				if(relativeGrid[16] == null) {
					pixels[x + 0][y + 3].add(item, relativeNeighborCount[12]);
					pixels[x + 2][y + 4].add(item, relativeNeighborCount[12]);
					pixels[x - 1][y + 1].add(item, relativeNeighborCount[12]);
				}
				if(relativeGrid[18] == null) {
					pixels[x + 3][y + 3].add(item, relativeNeighborCount[12]);
					pixels[x + 1][y + 4].add(item, relativeNeighborCount[12]);
					pixels[x + 4][y + 1].add(item, relativeNeighborCount[12]);
				}
			}
		}
	}

	fn generateHeightMap(itemGrid: *[16][16]?*const BaseItem, seed: *u64) [17][17]f32 {
		var heightMap: [17][17]f32 = undefined;
		var x: u8 = 0;
		while(x < 17) : (x += 1) {
			var y: u8 = 0;
			while(y < 17) : (y += 1) {
				heightMap[x][y] = 0;
				// The heighmap basically consists of the amount of neighbors this pixel has.
				// Also check if there are different neighbors.
				const oneItem = itemGrid[if(x == 0) x else x-1][if(y == 0) y else y-1];
				var hasDifferentItems: bool = false;
				var dx: i32 = -1;
				while(dx <= 0) : (dx += 1) {
					if(x + dx < 0 or x + dx >= 16) continue;
					var dy: i32 = -1;
					while(dy <= 0) : (dy += 1) {
						if(y + dy < 0 or y + dy >= 16) continue;
						const otherItem = itemGrid[@intCast(x + dx)][@intCast(y + dy)];
						heightMap[x][y] = if(otherItem) |item| (if(item.material) |material| 1 + (4*random.nextFloat(seed) - 2)*material.roughness else 0) else 0;
						if(otherItem != oneItem) {
							hasDifferentItems = true;
						}
					}
				}

				// If there is multiple items at this junction, make it go inward to make embedded parts stick out more:
				if(hasDifferentItems) {
					heightMap[x][y] -= 1;
				}
				
				// Take into account further neighbors with lower priority:
				dx = -2;
				while(dx <= 1) : (dx += 1) {
					if(x + dx < 0 or x + dx >= 16) continue;
					var dy: i32 = -2;
					while(dy <= 1) : (dy += 1) {
						if(y + dy < 0 or y + dy >= 16) continue;
						const otherItem = itemGrid[@intCast(x + dx)][@intCast(y + dy)];
						const dVec = Vec2f{@as(f32, @floatFromInt(dx)) + 0.5, @as(f32, @floatFromInt(dy)) + 0.5};
						heightMap[x][y] += if(otherItem != null) 1.0/vec.dot(dVec, dVec) else 0;
					}
				}
			}
		}
		return heightMap;
	}

	pub fn generate(tool: *Tool) void {
		const img = tool.image;
		var pixelMaterials: [16][16]PixelData = undefined;
		for(0..16) |x| {
			for(0..16) |y| {
				pixelMaterials[x][y] = PixelData.init(main.stackAllocator);
			}
		}

		defer { // TODO: Maybe use an ArenaAllocator?
			for(0..16) |x| {
				for(0..16) |y| {
					pixelMaterials[x][y].deinit();
				}
			}
		}
		
		var seed: u64 = tool.seed;
		random.scrambleSeed(&seed);

		// Count all neighbors:
		var neighborCount: [25]u8 = [_]u8{0} ** 25;
		var x: u8 = 0;
		while(x < 5) : (x += 1) {
			var y: u8 = 0;
			while(y < 5) : (y += 1) {
				var offsetGrid: [25]?*const BaseItem = undefined;
				var dx: i32 = -2;
				while(dx <= 2) : (dx += 1) {
					var dy: i32 = -2;
					while(dy <= 2) : (dy += 1) {
						if(x + dx >= 0 and x + dx < 5 and y + dy >= 0 and y + dy < 5) {
							const index: usize = @intCast(x + dx + 5*(y + dy));
							const offsetIndex: usize = @intCast(2 + dx + 5*(2 + dy));
							offsetGrid[offsetIndex] = tool.craftingGrid[index];
						}
					}
				}
				const index = x + 5*y;
				neighborCount[index] = countNeighbors(&offsetGrid);
			}
		}

		// Push all items from the regions on a 16×16 image grid.
		x = 0;
		while(x < 5) : (x += 1) {
			var y: u8 = 0;
			while(y < 5) : (y += 1) {
				var offsetGrid: [25]?*const BaseItem = .{null} ** 25;
				var offsetNeighborCount: [25]u8 = undefined;
				var dx: i32 = -2;
				while(dx <= 2) : (dx += 1) {
					var dy: i32 = -2;
					while(dy <= 2) : (dy += 1) {
						if(x + dx >= 0 and x + dx < 5 and y + dy >= 0 and y + dy < 5) {
							const index: usize = @intCast(x + dx + 5*(y + dy));
							const offsetIndex: usize = @intCast(2 + dx + 5*(2 + dy));
							offsetGrid[offsetIndex] = tool.craftingGrid[index];
							offsetNeighborCount[offsetIndex] = neighborCount[index];
						}
					}
				}
				const index = x + 5*y;
				drawRegion(&offsetGrid, &offsetNeighborCount, GRID_CENTERS_X[index] - 2, GRID_CENTERS_Y[index] - 2, &pixelMaterials);
			}
		}

		var itemGrid = &tool.materialGrid;
		x = 0;
		while(x < 16) : (x += 1) {
			var y: u8 = 0;
			while(y < 16) : (y += 1) {
				if(pixelMaterials[x][y].items.items.len != 0) {
					// Choose a random material at conflict zones:
					itemGrid[x][y] = pixelMaterials[x][y].items.items[random.nextIntBounded(u8, &seed, @as(u8, @intCast(pixelMaterials[x][y].items.items.len)))];
				} else {
					itemGrid[x][y] = null;
				}
			}
		}

		// Generate a height map, which will be used for lighting calulations.
		const heightMap = generateHeightMap(itemGrid, &seed);
		x = 0;
		while(x < 16) : (x += 1) {
			var y: u8 = 0;
			while(y < 16) : (y += 1) {
				if(itemGrid[x][y]) |item| {
					if(item.material) |material| {
						// Calculate the lighting based on the nearest free space:
						const lightTL = heightMap[x][y] - heightMap[x + 1][y + 1];
						const lightTR = heightMap[x + 1][y] - heightMap[x][y + 1];
						var light = 2 - @as(i32, @intFromFloat(@round((lightTL * 2 + lightTR) / 6)));
						light = @max(@min(light, 4), 0);
						img.setRGB(x, 15 - y, material.colorPalette[@intCast(light)]);
					} else {
						img.setRGB(x, 15 - y, if((x ^ y) & 1 == 0) Color{.r=255, .g=0, .b=255, .a=255} else Color{.r=0, .g=0, .b=0, .a=255});
					}
				} else {
					img.setRGB(x, 15 - y, Color{.r = 0, .g = 0, .b = 0, .a = 0});
				}
			}
		}
	}
};

/// Determines the physical properties of a tool to caclulate in-game parameters such as durability and speed.
const ToolPhysics = struct {
	/// Finds the handle of the tool.
	/// Uses a quite simple algorithm:
	/// It just simply takes the lowest, right-most 2×2 grid of filled pixels.
	/// Returns whether the handle is good or not.
	fn findHandle(tool: *Tool) bool {
		// A handle is a piece of the tool that is normally on the bottom row and has at most one neighbor:
		// Find the bottom row:
		var y: u32 = 20;
		outer:
		while(y > 0) : (y -= 5) {
			var x: u32 = 0;
			while(x < 5) : (x += 5) {
				if(tool.craftingGrid[y + x] != null) {
					break :outer;
				}
			}
		}
		// Find a valid handle:
		// Goes from right to left.
		// TODO: Add left-hander setting that mirrors the x axis of the tools and the crafting grid
		var x: u32 = 4;
		while(true) {
			if(tool.craftingGrid[y + x] != null) {
				tool.handlePosition[0] = @as(f32, @floatFromInt(TextureGenerator.GRID_CENTERS_X[x + y])) - 0.5;
				tool.handlePosition[1] = @as(f32, @floatFromInt(TextureGenerator.GRID_CENTERS_Y[x + y])) - 0.5;
				// Count the neighbors to determine whether it's a good handle:
				var neighbors: u32 = 0;
				if(x != 0 and tool.craftingGrid[y + x - 1] != null)
					neighbors += 1;
				if(x != 4 and tool.craftingGrid[y + x + 1] != null)
					neighbors += 1;
				if(y != 0) {
					if(tool.craftingGrid[y - 5 + x] != null)
						neighbors += 1;
					if(x != 0 and tool.craftingGrid[y - 5 + x - 1] != null)
						neighbors += 1;
					if(x != 4 and tool.craftingGrid[y - 5 + x + 1] != null)
						neighbors += 1;
				}
				if(neighbors <= 1) {
					return true;
				}
			}
			if(x == 0) break;
			x -= 1;
		}
		// No good handle was found on the bottom row.
		return false;
	}

	/// Determines the mass and moment of inertia of handle and center of mass.
	fn determineInertia(tool: *Tool) void {
		// Determines mass and center of mass:
		var mass: f32 = 0;
		var centerOfMass: Vec2f = Vec2f{0, 0};
		var x: u32 = 0;
		while(x < 16) : (x += 1) {
			var y: u32 = 0;
			while(y < 16) : (y += 1) {
				if(tool.materialGrid[x][y]) |item| {
					if(item.material) |material| {
						const localMass = material.density;
						centerOfMass[0] += localMass*(@as(f32, @floatFromInt(x)) + 0.5);
						centerOfMass[1] += localMass*(@as(f32, @floatFromInt(y)) + 0.5);
						mass += localMass;
					}
				}
			}
		}
		tool.centerOfMass = centerOfMass/@as(Vec2f, @splat(mass));
		tool.mass = mass;

		// Determines the moment of intertia relative to the center of mass:
		var inertia: f32 = 0;
		x = 0;
		while(x < 16) : (x += 1) {
			var y: u32 = 0;
			while(y < 16) : (y += 1) {
				if(tool.materialGrid[x][y]) |item| {
					if(item.material) |material| {
						const localMass = material.density;
						const dx = @as(f32, @floatFromInt(x)) + 0.5 - tool.centerOfMass[0];
						const dy = @as(f32, @floatFromInt(y)) + 0.5 - tool.centerOfMass[1];
						inertia += localMass*(dx*dx + dy*dy);
					}
				}
			}
		}
		tool.inertiaCenterOfMass = inertia;
		// Using the parallel axis theorem the inertia relative to the handle can be derived:
		tool.inertiaHandle = inertia + mass*vec.length(tool.centerOfMass - tool.handlePosition);
	}

	/// Determines the sharpness of a point on the tool.
	fn determineSharpness(tool: *Tool, point: *Vec3i, initialAngle: f32) void {
		const center: Vec2f = tool.handlePosition - vec.normalize(tool.centerOfMass - tool.handlePosition)*@as(Vec2f, @splat(16)); // Going 16 pixels away from the handle to simulate arm length.
		// A region is smooth if there is a lot of pixel within similar angle/distance:
		const originalAngle = std.math.atan2(@as(f32, @floatFromInt(point.*[1])) + 0.5 - center[1], @as(f32, @floatFromInt(point.*[0])) + 0.5 - center[0]) - initialAngle;
		const originalDistance = @cos(originalAngle)*vec.length(center - Vec2f{@as(f32, @floatFromInt(point.*[0])) + 0.5, @as(f32, @floatFromInt(point.*[1])) + 0.5});
		var numOfSmoothPixels: u31 = 0;
		var x: f32 = 0;
		while(x < 16) : (x += 1) {
			var y: f32 = 0;
			while(y < 16) : (y += 1) {
				const angle = std.math.atan2(y + 0.5 - center[1], x + 0.5 - center[0]) - initialAngle;
				const distance = @cos(angle)*vec.length(center - Vec2f{x + 0.5, y + 0.5});
				const deltaAngle = @abs(angle - originalAngle);
				const deltaDist = @abs(distance - originalDistance);
				if(deltaAngle <= 0.2 and deltaDist <= 0.7) {
					numOfSmoothPixels += 1;
				}
			}
		}
		point.*[2] = numOfSmoothPixels;
	}

	/// Determines where the tool would collide with the terrain.
	/// Also evaluates the smoothness of the collision point and stores it in the z component.
	fn determineCollisionPoints(tool: *Tool, leftCollisionPoint: *Vec3i, rightCollisionPoint: *Vec3i, frontCollisionPoint: *Vec3i, factor: f32) void {
		// For finding that point the center of rotation is assumed to be 1 arm(16 pixel) begind the handle.
		// Additionally the handle is assumed to go towards the center of mass.
		const center: Vec2f = tool.handlePosition - vec.normalize(tool.centerOfMass - tool.handlePosition)*@as(Vec2f, @splat(factor)); // Going some distance away from the handle to simulate arm length.
		// Angle of the handle.
		const initialAngle = std.math.atan2(tool.handlePosition[1] - center[1], tool.handlePosition[0] - center[0]);
		var leftCollisionAngle: f32 = 0;
		var rightCollisionAngle: f32 = 0;
		var frontCollisionDistance: f32 = 0;
		var x: u8 = 0;
		while(x < 16) : (x += 1) {
			var y: u8 = 0;
			while(y < 16) : (y += 1) {
				if(tool.materialGrid[x][y] == null) continue;
				const x_float: f32 = @floatFromInt(x);
				const y_float: f32 = @floatFromInt(y);
				const angle = std.math.atan2(y_float + 0.5 - center[1], x_float + 0.5 - center[0]) - initialAngle;
				const distance = @cos(angle)*vec.length(center - Vec2f{x_float + 0.5, y_float + 0.5});
				if(angle < leftCollisionAngle) {
					leftCollisionAngle = angle;
					leftCollisionPoint.* = Vec3i{x, y, 0};
				}
				if(angle > rightCollisionAngle) {
					rightCollisionAngle = angle;
					rightCollisionPoint.* = Vec3i{x, y, 0};
				}
				if(distance > frontCollisionDistance) {
					frontCollisionDistance = distance;
					frontCollisionPoint.* = Vec3i{x, y, 0};
				}
			}
		}

		// sharpness is hard.
		determineSharpness(tool, leftCollisionPoint, initialAngle);
		determineSharpness(tool, rightCollisionPoint, initialAngle);
		determineSharpness(tool, frontCollisionPoint, initialAngle);
	}

	fn calculateDurability(tool: *Tool) void {
		// Doesn't do much besides summing up the durability of all it's parts:
		var durability: f32 = 0;
		for(0..16) |x| {
			for(0..16) |y| {
				if(tool.materialGrid[x][y]) |item| {
					if(item.material) |material| {
						durability += material.resistance;
					}
				}
			}
		}
		// Smaller tools are faster to swing. To balance that smaller tools get a lower durability.
		tool.maxDurability = @intFromFloat(@max(1, std.math.pow(f32, durability/4, 1.5)));
		tool.durability = tool.maxDurability;
	}

	/// Determines how hard the tool hits the ground.
	fn calculateImpactEnergy(tool: *Tool, collisionPoint: Vec3i) f32 {
		// Fun fact: Without gravity the impact energy is independent of the mass of the pickaxe(E = ∫ F⃗ ds⃗), but only on the length of the handle.
		var impactEnergy: f32 = vec.length(tool.centerOfMass - tool.handlePosition);

		// But when the pickaxe does get heavier 2 things happen:
		// 1. The player needs to lift a bigger weight, so the tool speed gets reduced(calculated elsewhere).
		// 2. When travelling down the tool also gets additional energy from gravity, so the force is increased by m·g.
		impactEnergy *= tool.materialGrid[@intCast(collisionPoint[0])][@intCast(collisionPoint[1])].?.material.?.power + tool.mass/256;

		return impactEnergy; // TODO: Balancing
	}

	/// Determines how good a pickaxe this side of the tool would make.
	fn evaluatePickaxePower(tool: *Tool, collisionPointLower: Vec3i, collisionPointUpper: Vec3i) f32 {
		// Pickaxes are used for breaking up rocks. This requires a high energy in a small area.
		// So a tool is a good pickaxe, if it delivers a energy force and if it has a sharp tip.

		// A sharp tip has less than two neighbors:
		var neighborsLower: u32 = 0;
		var x: i32 = -1;
		while(x < 2) : (x += 1) {
			var y: i32 = -1;
			while(y <= 2) : (y += 1) {
				if(x + collisionPointLower[0] >= 0 and x + collisionPointLower[0] < 16) {
					if(y + collisionPointLower[1] >= 0 and y + collisionPointLower[1] < 16) {
						if(tool.materialGrid[@intCast(x + collisionPointLower[0])][@intCast(y + collisionPointLower[1])] != null)
							neighborsLower += 1;
					}
				}
			}
		}
		var neighborsUpper: u32 = 0;
		var dirUpper: Vec2i = Vec2i{0, 0};
		x = -1;
		while(x < 2) : (x += 1) {
			var y: i32 = -1;
			while(y <= 2) : (y += 1) {
				if(x + collisionPointUpper[0] >= 0 and x + collisionPointUpper[0] < 16) {
					if(y + collisionPointUpper[1] >= 0 and y + collisionPointUpper[1] < 16) {
						if(tool.materialGrid[@intCast(x + collisionPointUpper[0])][@intCast(y + collisionPointUpper[1])] != null) {
							neighborsUpper += 1;
							dirUpper[0] += x;
							dirUpper[1] += y;
						}
					}
				}
			}
		}
		if(neighborsLower > 3 and neighborsUpper > 3) return 0;

		// A pickaxe never points upwards:
		if(neighborsUpper == 3 and dirUpper[1] == 2) {
			return 0;
		}

		return calculateImpactEnergy(tool, collisionPointLower);
	}

	/// Determines how good an axe this side of the tool would make.
	fn evaluateAxePower(tool: *Tool, collisionPointLower: Vec3i, collisionPointUpper: Vec3i) f32 {
		// Axes are used for breaking up wood. This requires a larger area (= smooth tip) rather than a sharp tip.
		const collisionPointLowerFloat = Vec2f{@floatFromInt(collisionPointLower[0]), @floatFromInt(collisionPointLower[1])};
		const collisionPointUpperFloat = Vec2f{@floatFromInt(collisionPointUpper[0]), @floatFromInt(collisionPointUpper[1])};
		const areaFactor = 0.25 + vec.length(collisionPointLowerFloat - collisionPointUpperFloat)/4;

		return areaFactor*calculateImpactEnergy(tool, collisionPointLower)/8;
	}

	/// Determines how good a shovel this side of the tool would make.
	fn evaluateShovelPower(tool: *Tool, collisionPoint: Vec3i) f32 {
		// Shovels require a large area to put all the sand on.
		// For the sake of simplicity I just assume that every part of the tool can contain sand and that sand piles up in a pyramidial shape.
		var sandPiles: [16][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 16;
		const Entry = struct {
			x: u8,
			y: u8,
		};
		var stack = main.List(Entry).init(main.stackAllocator);
		defer stack.deinit();
		// Uses a simple flood-fill algorithm equivalent to light calculation.
		var x: u8 = 0;
		while(x < 16) : (x += 1) {
			var y: u8 = 0;
			while(y < 16) : (y += 1) {
				sandPiles[x][y] = std.math.maxInt(u8);
				if(tool.materialGrid[x][y] == null) {
					sandPiles[x][y] = 0;
					stack.append(Entry{.x=x, .y=y});
				} else if(x == 0 or x == 15 or y == 0 or y == 15) {
					sandPiles[x][y] = 1;
					stack.append(Entry{.x=x, .y=y});
				}
			}
		}
		while(stack.popOrNull()) |entry| {
			x = entry.x;
			const y = entry.y;
			if(x != 0 and y != 0 and tool.materialGrid[x - 1][y - 1] != null) {
				if(sandPiles[x - 1][y - 1] > sandPiles[x][y] + 1) {
					sandPiles[x - 1][y - 1] = sandPiles[x][y] + 1;
					stack.append(Entry{.x=x-1, .y=y-1});
				}
			}
			if(x != 0 and y != 15 and tool.materialGrid[x - 1][y + 1] != null) {
				if(sandPiles[x - 1][y + 1] > sandPiles[x][y] + 1) {
					sandPiles[x - 1][y + 1] = sandPiles[x][y] + 1;
					stack.append(Entry{.x=x-1, .y=y+1});
				}
			}
			if(x != 15 and y != 0 and tool.materialGrid[x + 1][y - 1] != null) {
				if(sandPiles[x + 1][y - 1] > sandPiles[x][y] + 1) {
					sandPiles[x + 1][y - 1] = sandPiles[x][y] + 1;
					stack.append(Entry{.x=x+1, .y=y-1});
				}
			}
			if(x != 15 and y != 15 and tool.materialGrid[x + 1][y + 1] != null) {
				if(sandPiles[x + 1][y + 1] > sandPiles[x][y] + 1) {
					sandPiles[x + 1][y + 1] = sandPiles[x][y] + 1;
					stack.append(Entry{.x=x+1, .y=y+1});
				}
			}
		}
		// Count the volume:
		var volume: f32 = 0;
		x = 0;
		while(x < 16) : (x += 1) {
			var y: u8 = 0;
			while(y < 16) : (y += 1) {
				volume += @floatFromInt(sandPiles[x][y]);
			}
		}
		volume /= 256; // TODO: Balancing
		return volume*calculateImpactEnergy(tool, collisionPoint);
	}


	/// Determines all the basic properties of the tool.
	pub fn evaluateTool(tool: *Tool) void {
		const hasGoodHandle = findHandle(tool);
		calculateDurability(tool);
		determineInertia(tool);
		var leftCollisionPointLower = Vec3i{0, 0, 0};
		var rightCollisionPointLower = Vec3i{0, 0, 0};
		var frontCollisionPointLower = Vec3i{0, 0, 0};
		var leftCollisionPointUpper = Vec3i{0, 0, 0};
		var rightCollisionPointUpper = Vec3i{0, 0, 0};
		var frontCollisionPointUpper = Vec3i{0, 0, 0};
		determineCollisionPoints(tool, &leftCollisionPointLower, &rightCollisionPointLower, &frontCollisionPointLower, 16);
		determineCollisionPoints(tool, &rightCollisionPointUpper, &leftCollisionPointUpper, &frontCollisionPointUpper, -20);

		const leftPP = evaluatePickaxePower(tool, leftCollisionPointLower, leftCollisionPointUpper);
		const rightPP = evaluatePickaxePower(tool, rightCollisionPointLower, rightCollisionPointUpper);
		tool.pickaxePower = @max(leftPP, rightPP); // TODO: Adjust the swing direction.

		const leftAP = evaluateAxePower(tool, leftCollisionPointLower, leftCollisionPointUpper);
		const rightAP = evaluateAxePower(tool, rightCollisionPointLower, rightCollisionPointUpper);
		tool.axePower = @max(leftAP, rightAP); // TODO: Adjust the swing direction.

		tool.shovelPower = evaluateShovelPower(tool, frontCollisionPointLower);

		// It takes longer to swing a heavy tool.
		tool.swingTime = (tool.mass + tool.inertiaHandle/8)/256; // TODO: Balancing

		if(hasGoodHandle) { // Good handles make tools easier to handle.
			tool.swingTime /= 2.0;
		}

		// TODO: Swords and throwing weapons.

	}
};

pub const Tool = struct {
	craftingGrid: [25]?*const BaseItem,
	materialGrid: [16][16]?*const BaseItem,
	tooltip: ?[]const u8,
	image: graphics.Image,
	texture: ?graphics.Texture,
	seed: u32,

	/// Reduction factor to block breaking time.
	pickaxePower: f32,
	/// Reduction factor to block breaking time.
	axePower: f32,
	/// Reduction factor to block breaking time.
	shovelPower: f32,
	/// TODO: damage
	damage: f32 = 1,

	durability: u32,
	maxDurability: u32,

	/// How long it takes to swing the tool in seconds.
	swingTime: f32,

	mass: f32,

	///  Where the player holds the tool.
	handlePosition: Vec2f,
	/// Moment of inertia relative to the handle.
	inertiaHandle: f32,

	/// Where the tool rotates around when being thrown.
	centerOfMass: Vec2f,
	/// Moment of inertia relative to the center of mass.
	inertiaCenterOfMass: f32,

	pub fn init() *Tool {
		const self = main.globalAllocator.create(Tool);
		self.image = graphics.Image.init(main.globalAllocator, 16, 16);
		self.texture = null;
		self.tooltip = null;
		return self;
	}

	pub fn deinit(self: *const Tool) void {
		if(self.texture) |texture| {
			texture.deinit();
		}
		self.image.deinit(main.globalAllocator);
		if(self.tooltip) |tooltip| main.globalAllocator.free(tooltip);
		main.globalAllocator.destroy(self);
	}

	pub fn initFromCraftingGrid(craftingGrid: [25]?*const BaseItem, seed: u32) *Tool {
		const self = init();
		self.seed = seed;
		self.craftingGrid = craftingGrid;
		// Produce the tool and its textures:
		// The material grid, which comes from texture generation, is needed on both server and client, to generate the tool properties.
		TextureGenerator.generate(self);
		ToolPhysics.evaluateTool(self);
		return self;
	}

	pub fn initFromJson(json: JsonElement) *Tool {
		const self = initFromCraftingGrid(extractItemsFromJson(json.getChild("grid")), json.get(u32, "seed", 0));
		self.durability = json.get(u32, "durability", self.maxDurability);
		return self;
	}

	fn extractItemsFromJson(jsonArray: JsonElement) [25]?*const BaseItem {
		var items: [25]?*const BaseItem = undefined;
		for(&items, 0..) |*item, i| {
			item.* = reverseIndices.get(jsonArray.getAtIndex([]const u8, i, "null"));
		}
		return items;
	}

	pub fn save(self: *const Tool, allocator: NeverFailingAllocator) JsonElement {
		const jsonObject = JsonElement.initObject(allocator);
		const jsonArray = JsonElement.initArray(allocator);
		for(self.craftingGrid) |nullItem| {
			if(nullItem) |item| {
				jsonArray.JsonArray.append(JsonElement{.JsonString=item.id});
			} else {
				jsonArray.JsonArray.append(JsonElement{.JsonNull={}});
			}
		}
		jsonObject.put("grid", jsonArray);
		jsonObject.put("durability", self.durability);
		jsonObject.put("seed", self.seed);
		return jsonObject;
	}

	pub fn hashCode(self: Tool) u32 {
		var hash: u32 = 0;
		for(self.craftingGrid) |nullItem| {
			if(nullItem) |item| {
				hash = 33*%hash +% item.material.?.hashCode();
			}
		}
		return hash;
	}

	fn getTexture(self: *Tool) graphics.Texture {
		if(self.texture == null) {
			self.texture = graphics.Texture.init();
			self.texture.?.generate(self.image);
		}
		return self.texture.?;
	}
	
	fn getTooltip(self: *Tool) []const u8 {
		if(self.tooltip) |tooltip| return tooltip;
		self.tooltip = std.fmt.allocPrint(
			main.globalAllocator.allocator,
			\\Time to swing: {d:.2} s
			\\Pickaxe power: {} %
			\\Axe power: {} %
			\\Shover power: {} %
			\\Durability: {}/{}
			,
			.{
				self.swingTime,
				@as(i32, @intFromFloat(100*self.pickaxePower)),
				@as(i32, @intFromFloat(100*self.axePower)),
				@as(i32, @intFromFloat(100*self.shovelPower)),
				self.durability, self.maxDurability,
			}
		) catch unreachable;
		return self.tooltip.?;
	}

	pub fn getPowerByBlockClass(self: *Tool, blockClass: blocks.BlockClass) f32 {
		return switch(blockClass) {
			.fluid => 0,
			.leaf => 1,
			.sand => self.shovelPower,
			.stone => self.pickaxePower,
			.unbreakable => 0,
			.wood => self.axePower,
		};
	}

	pub fn onUseReturnBroken(self: *Tool) bool {
		self.durability -|= 1;
		return self.durability == 0;
	}
};

pub const Item = union(enum) {
	baseItem: *BaseItem,
	tool: *Tool,

	pub fn init(json: JsonElement) !Item {
		if(reverseIndices.get(json.get([]const u8, "item", "null"))) |baseItem| {
			return Item{.baseItem = baseItem};
		} else {
			const toolJson = json.getChild("tool");
			if(toolJson != .JsonObject) return error.ItemNotFound;
			return Item{.tool = Tool.initFromJson(toolJson)};
		}
	}

	pub fn deinit(self: Item) void {
		switch(self) {
			.baseItem => {
				
			},
			.tool => |_tool| {
				_tool.deinit();
			},
		}
	}

	pub fn stackSize(self: Item) u16 {
		switch(self) {
			.baseItem => |_baseItem| {
				return _baseItem.stackSize;
			},
			.tool => {
				return 1;
			},
		}
	}

	pub fn insertIntoJson(self: Item, allocator: NeverFailingAllocator, jsonObject: JsonElement) void {
		switch(self) {
			.baseItem => |_baseItem| {
				jsonObject.put("item", _baseItem.id);
			},
			.tool => |_tool| {
				jsonObject.put("tool", _tool.save(allocator));
			},
		}
	}

	pub fn getTexture(self: Item) graphics.Texture {
		switch(self) {
			.baseItem => |_baseItem| {
				return _baseItem.getTexture();
			},
			.tool => |_tool| {
				return _tool.getTexture();
			},
		}
	}

	pub fn getTooltip(self: Item) []const u8 {
		switch(self) {
			.baseItem => |_baseItem| {
				return _baseItem.getTooltip();
			},
			.tool => |_tool| {
				return _tool.getTooltip();
			},
		}
	}

	pub fn getImage(self: Item) graphics.Image {
		switch(self) {
			.baseItem => |_baseItem| {
				return _baseItem.image;
			},
			.tool => |_tool| {
				return _tool.image;
			},
		}
	}

	pub fn hashCode(self: Item) u32 {
		switch(self) {
			inline else => |item| {
				return item.hashCode();
			},
		}
	}
};

pub const ItemStack = struct {
	item: ?Item = null,
	amount: u16 = 0,

	/// Moves the content of the given ItemStack into a new ItemStack.
	pub fn moveFrom(self: *ItemStack, supplier: *ItemStack) void {
		std.debug.assert(self.item == null); // Don't want to delete matter.
		self.item = supplier.item;
		self.amount = supplier.amount;
		supplier.clear();
	}

	pub fn filled(self: *const ItemStack) bool {
		if(self.item) |item| {
			return self.amount >= item.stackSize();
		}
		return false;
	}

	pub fn empty(self: *const ItemStack) bool {
		return self.amount == 0;
	}

	/// Returns the number of items actually added/removed.
	pub fn add(self: *ItemStack, item: Item, number: anytype) @TypeOf(number) {
		if(self.item == null) self.item = item;
		var newAmount = self.amount + number;
		var returnValue = number;
		if(newAmount < 0) {
			newAmount = 0;
			returnValue = newAmount - self.amount;
		} else if(newAmount > self.item.?.stackSize()) {
			newAmount = self.item.?.stackSize();
			returnValue = newAmount - self.amount;
		}
		self.amount = @intCast(newAmount);
		if(self.empty()) {
			self.clear();
		}
		return returnValue;
	}

	/// whether the given number of items can be added to this stack.
	pub fn canAddAll(self: *const ItemStack, item: Item, number: u16) bool {
		if(self.item != null and !std.meta.eql(self.item.?, item)) return false;
		return @as(u32, self.amount) + number <= item.stackSize();
	}

	pub fn clear(self: *ItemStack) void {
		if(self.item) |item| {
			item.deinit();
		}
		self.item = null;
		self.amount = 0;
	}

	pub fn storeToJson(self: *const ItemStack, allocator: NeverFailingAllocator, jsonObject: JsonElement) void {
		if(self.item) |item| {
			item.insertIntoJson(allocator, jsonObject);
			jsonObject.put("amount", self.amount);
		}
	}

	pub fn store(self: *const ItemStack, allocator: NeverFailingAllocator) JsonElement {
		const result = JsonElement.initObject(allocator);
		self.storeToJson(allocator, result);
		return result;
	}
};

pub const Inventory = struct {
	items: []ItemStack,

	pub fn init(allocator: NeverFailingAllocator, size: usize) Inventory {
		const self = Inventory{
			.items = allocator.alloc(ItemStack, size),
		};
		for(self.items) |*item| {
			item.* = ItemStack{};
		}
		return self;
	}

	pub fn deinit(self: Inventory, allocator: NeverFailingAllocator) void {
		for(self.items) |*item| {
			item.clear();
		}
		allocator.free(self.items);
	}

	/// Returns the amount of items that didn't fit in the inventory.
	pub fn addItem(self: Inventory, item: Item, _amount: u16) u16 {
		var amount = _amount;
		for(self.items) |*stack| {
			if(!stack.empty() and std.meta.eql(stack.item, item) and !stack.filled()) {
				amount -= stack.add(item, amount);
				if(amount == 0) return 0;
			}
		}
		for(self.items) |*stack| {
			if(stack.empty()) {
				amount -= stack.add(item, amount);
				if(amount == 0) return 0;
			}
		}
		return amount;
	}

	pub fn canCollect(self: Inventory, item: Item) bool {
		for(self.items) |*stack| {
			if(stack.empty()) return true;
			if(stack.item == item and !stack.filled()) {
				return true;
			}
		}
		return false;
	}

	pub fn getItem(self: Inventory, slot: usize) ?Item {
		return self.items[slot].item;
	}

	pub fn getStack(self: Inventory, slot: usize) *ItemStack {
		return &self.items[slot];
	}

	pub fn getAmount(self: Inventory, slot: usize) u16 {
		return self.items[slot].amount;
	}

	pub fn save(self: Inventory, allocator: NeverFailingAllocator) JsonElement {
		const jsonObject = JsonElement.initObject(allocator);
		jsonObject.put("capacity", self.items.len);
		for(self.items, 0..) |stack, i| {
			if(!stack.empty()) {
				var buf: [1024]u8 = undefined;
				jsonObject.put(buf[0..std.fmt.formatIntBuf(&buf, i, 10, .lower, .{})], stack.store(allocator));
			}
		}
		return jsonObject;
	}

	pub fn loadFromJson(self: Inventory, json: JsonElement) void {
		for(self.items, 0..) |*stack, i| {
			stack.clear();
			var buf: [1024]u8 = undefined;
			const stackJson = json.getChild(buf[0..std.fmt.formatIntBuf(&buf, i, 10, .lower, .{})]);
			if(stackJson == .JsonObject) {
				stack.item = Item.init(stackJson) catch |err| {
					const msg = stackJson.toStringEfficient(main.stackAllocator, "");
					defer main.stackAllocator.free(msg);
					std.log.err("Couldn't find item {s}: {s}", .{msg, @errorName(err)});
					stack.clear();
					continue;
				};
				stack.amount = stackJson.get(u16, "amount", 0);
			}
		}
	}
};

const Recipe = struct {
	sourceItems: []*BaseItem,
	sourceAmounts: []u16,
	resultItem: ItemStack,
};

var arena: main.utils.NeverFailingArenaAllocator = undefined;
var reverseIndices: std.StringHashMap(*BaseItem) = undefined;
pub var itemList: [65536]BaseItem = undefined;
pub var itemListSize: u16 = 0;

var recipeList: main.List(Recipe) = undefined;

pub fn iterator() std.StringHashMap(*BaseItem).ValueIterator {
	return reverseIndices.valueIterator();
}

pub fn recipes() []Recipe {
	return recipeList.items;
}

pub fn globalInit() void {
	arena = main.utils.NeverFailingArenaAllocator.init(main.globalAllocator);
	reverseIndices = std.StringHashMap(*BaseItem).init(arena.allocator().allocator);
	recipeList = main.List(Recipe).init(arena.allocator());
	itemListSize = 0;
}

pub fn register(_: []const u8, texturePath: []const u8, replacementTexturePath: []const u8, id: []const u8, json: JsonElement) *BaseItem {
	std.log.info("{s}", .{id});
	if(reverseIndices.contains(id)) {
		std.log.warn("Registered item with id {s} twice!", .{id});
	}
	const newItem = &itemList[itemListSize];
	newItem.init(arena.allocator(), texturePath, replacementTexturePath, id, json);
	reverseIndices.put(newItem.id, newItem) catch unreachable;
	itemListSize += 1;
	return newItem;
}

pub fn registerRecipes(file: []const u8) void {
	var shortcuts = std.StringHashMap(*BaseItem).init(main.stackAllocator.allocator);
	defer shortcuts.deinit();
	defer {
		var keyIterator = shortcuts.keyIterator();
		while(keyIterator.next()) |key| {
			main.stackAllocator.free(key.*);
		}
	}
	var items = main.List(*BaseItem).init(main.stackAllocator);
	defer items.deinit();
	var itemAmounts = main.List(u16).init(main.stackAllocator);
	defer itemAmounts.deinit();
	var string = main.List(u8).init(main.stackAllocator);
	defer string.deinit();
	var lines = std.mem.split(u8, file, "\n");
	while(lines.next()) |line| {
		// shortcuts:
		if(std.mem.containsAtLeast(u8, line, 1, "=")) {
			var parts = std.mem.split(u8, line, "=");
			for(parts.first()) |char| {
				if(std.ascii.isWhitespace(char)) continue; // TODO: Unicode whitespaces
				string.append(char);
			}
			const shortcut = string.toOwnedSlice();
			const id = std.mem.trim(u8, parts.rest(), &std.ascii.whitespace); // TODO: Unicode whitespaces
			const item = shortcuts.get(id) orelse getByID(id) orelse &BaseItem.unobtainable;
			shortcuts.put(shortcut, item) catch unreachable;
		} else if(std.mem.startsWith(u8, line, "result") and items.items.len != 0) {
			defer items.clearAndFree();
			defer itemAmounts.clearAndFree();
			var id = line["result".len..];
			var amount: u16 = 1;
			if(std.mem.containsAtLeast(u8, id, 1, "*")) {
				var parts = std.mem.split(u8, id, "*");
				const amountString = std.mem.trim(u8, parts.first(), &std.ascii.whitespace); // TODO: Unicode whitespaces
				amount = std.fmt.parseInt(u16, amountString, 0) catch 1;
				id = parts.rest();
			}
			id = std.mem.trim(u8, id, &std.ascii.whitespace); // TODO: Unicode whitespaces
			const item = shortcuts.get(id) orelse getByID(id) orelse continue;
			const recipe = Recipe {
				.sourceItems = arena.allocator().dupe(*BaseItem, items.items),
				.sourceAmounts = arena.allocator().dupe(u16, itemAmounts.items),
				.resultItem = ItemStack{.item = Item{.baseItem = item}, .amount = amount},
			};
			recipeList.append(recipe);
		} else {
			var ingredients = std.mem.split(u8, line, ",");
			outer: while(ingredients.next()) |ingredient| {
				var id = ingredient;
				if(id.len == 0) continue;
				var amount: u16 = 1;
				if(std.mem.containsAtLeast(u8, id, 1, "*")) {
					var parts = std.mem.split(u8, id, "*");
					const amountString = std.mem.trim(u8, parts.first(), &std.ascii.whitespace); // TODO: Unicode whitespaces
					amount = std.fmt.parseInt(u16, amountString, 0) catch 1;
					id = parts.rest();
				}
				id = std.mem.trim(u8, id, &std.ascii.whitespace); // TODO: Unicode whitespaces
				const item = shortcuts.get(id) orelse getByID(id) orelse continue;
				// Resolve duplicates:
				for(items.items, 0..) |presentItem, i| {
					if(presentItem == item) {
						itemAmounts.items[i] += amount;
						continue :outer;
					}
				}
				items.append(item);
				itemAmounts.append(amount);
			}
		}
	}
}

pub fn reset() void {
	reverseIndices.clearAndFree();
	recipeList.clearAndFree();
	itemListSize = 0;
	_ = arena.reset(.free_all);
}

pub fn deinit() void {
	reverseIndices.clearAndFree();
	recipeList.clearAndFree();
	arena.deinit();
}

pub fn getByID(id: []const u8) ?*BaseItem {
	if(reverseIndices.get(id)) |result| {
		return result;
	} else {
		std.log.warn("Couldn't find item {s}.", .{id});
		return null;
	}
}