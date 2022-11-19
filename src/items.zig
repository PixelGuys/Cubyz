const std = @import("std");

const Allocator = std.mem.Allocator;

const blocks = @import("blocks.zig");
const Block = blocks.Block;
const graphics = @import("graphics.zig");
const json = @import("json.zig");
const JsonElement = json.JsonElement;
const main = @import("main.zig");
const random = @import("random.zig");
const vec = @import("vec.zig");
const Vec2f = vec.Vec2f;
const Vec2i = vec.Vec2i;
const Vec3i = vec.Vec3i;

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
	colorPalette: []u32 = undefined,

	pub fn init(self: *Material, allocator: Allocator, jsonObject: JsonElement) !void {
		self.density = jsonObject.get(f32, "density", 1.0);
		self.resistance = jsonObject.get(f32, "resistance", 1.0);
		self.power = jsonObject.get(f32, "power", 1.0);
		self.roughness = @max(0, jsonObject.get(f32, "roughness", 1.0));
		const colors = jsonObject.getChild("colors");
		self.colorPalette = try allocator.alloc(u32, colors.JsonArray.items.len);
		for(colors.JsonArray.items) |item, i| {
			self.colorPalette[i] = item.as(u32, 0xff000000);
		}
	}

// TODO: Check if/how this is needed:
//	public Material(float density, float resistance, float power, float roughness, int[] colors) {
//		this.density = density;
//		this.resistance = resistance;
//		this.power = power;
//		this.roughness = roughness;
//		colorPalette = colors;
//	}
//
//	public int hashCode() {
//		int hash = Float.floatToIntBits(density);
//		hash = 101*hash + Float.floatToIntBits(resistance);
//		hash = 101*hash + Float.floatToIntBits(power);
//		hash = 101*hash + Float.floatToIntBits(roughness);
//		return hash;
//	}
};


const BaseItem = struct {
// TODO: Check if/how this is needed:
//	texturePath: []const u8,
//	modelPath: []const u8,
	id: []const u8,
	name: []const u8,

	stackSize: u16,
	material: ?Material,
	block: ?u16,
	foodValue: f32, // TODO: Effects.

	pub fn init(self: *BaseItem, allocator: Allocator, id: []const u8, jsonObject: JsonElement) !void {
		self.id = try allocator.dupe(u8, id);
// TODO: Check if/how this is needed:
//		self.texturePath = "";
//		self.modelPath = "";
		self.name = try allocator.dupe(u8, jsonObject.get([]const u8, "name", id));
		self.stackSize = jsonObject.get(u16, "stackSize", 64);
		const material = jsonObject.getChild("material");
		if(material == .JsonObject) {
			self.material = Material{};
			try self.material.?.init(allocator, material);
		} else {
			self.material = null;
		}
		self.block = blk: {
			break :blk blocks.getByID(jsonObject.get(?[]const u8, "block", null) orelse break :blk null);
		};
		self.foodValue = jsonObject.get(f32, "food", 0);
	}
// TODO: Check if/how this is needed:
//	protected Item(int stackSize) {
//		id = Resource.EMPTY;
//		this.stackSize = stackSize;
//		material = null;
//	}
//	
//	public void update() {}
//	
//	/**
//	 * Returns true if this item should be consumed on use. May be accessed by non-player entities.
//	 * @param user
//	 * @return whether this item is consumed upon use.
//	 */
//	public boolean onUse(Entity user) {
//		return false;
//	}
//	From Consumable.java:
//	@Override
//	public boolean onUse(Entity user) {
//		if ((user.hunger >= user.maxHunger - Math.min(user.maxHunger*0.1, 0.5) && foodValue > 0) || (user.hunger == 0 && foodValue < 0)) return false;
//		user.hunger = Math.min(user.maxHunger, user.hunger+foodValue);
//		return true;
//	}
//	public static Item load(JsonObject json, CurrentWorldRegistries registries) {
//		Item item = registries.itemRegistry.getByID(json.getString("item", "null"));
//		if (item == null) {
//			// Check if it is a tool:
//			JsonObject tool = json.getObject("tool");
//			if (tool != null) {
//				item = new Tool(tool, registries);
//			} else {
//				// item not existant in this version of the game. Can't do much so ignore it.
//			}
//		}
//		return item;
//	}
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
		items: std.ArrayList(*const BaseItem),
		pub fn init(allocator: Allocator) PixelData {
			return PixelData {
				.items = std.ArrayList(*const BaseItem).init(allocator),
			};
		}
		pub fn deinit(self: PixelData) void {
			self.items.clearAndFree();
		}
		pub fn add(self: *PixelData, item: *const BaseItem, neighbors: u8) !void {
			if(neighbors > self.maxNeighbors) {
				self.maxNeighbors = neighbors;
				self.items.clearRetainingCapacity();
			}
			if(neighbors == self.maxNeighbors) {
				try self.items.append(item);
			}
		}
	};

	/// Counts the neighbors, while prioritizing direct neighbors over diagonals.
	fn countNeighbors(relativeGrid: *[25]?*const BaseItem) u8 {
		var neighbors: u8 = 0;
		// direct neighbors count 1.5 times as much.
		if (relativeGrid[7]) neighbors += 3;
		if (relativeGrid[11]) neighbors += 3;
		if (relativeGrid[13]) neighbors += 3;
		if (relativeGrid[17]) neighbors += 3;

		if (relativeGrid[6]) neighbors += 2;
		if (relativeGrid[8]) neighbors += 2;
		if (relativeGrid[16]) neighbors += 2;
		if (relativeGrid[18]) neighbors += 2;
	}

	/// This part is responsible for associating each pixel with an item.
	fn drawRegion(relativeGrid: *[25]?*const BaseItem, relativeNeighborCount: *[25]u8, x: u8, y: u8, pixels: *[16][16]PixelData) void {
		if(relativeGrid[12]) |item| {
			// Count diagonal and straight neighbors:
			var diagonalNeighbors: u8 = 0;
			var straightNeighbors: u8 = 0;
			if (relativeGrid[7]) straightNeighbors += 1;
			if (relativeGrid[11]) straightNeighbors += 1;
			if (relativeGrid[13]) straightNeighbors += 1;
			if (relativeGrid[17]) straightNeighbors += 1;

			if (relativeGrid[6]) diagonalNeighbors += 1;
			if (relativeGrid[8]) diagonalNeighbors += 1;
			if (relativeGrid[16]) diagonalNeighbors += 1;
			if (relativeGrid[18]) diagonalNeighbors += 1;

			const neighbors = diagonalNeighbors + straightNeighbors;

			pixels[x + 1][y + 1].add(item, relativeNeighborCount[12]);
			pixels[x + 1][y + 2].add(item, relativeNeighborCount[12]);
			pixels[x + 2][y + 1].add(item, relativeNeighborCount[12]);
			pixels[x + 2][y + 2].add(item, relativeNeighborCount[12]);

			// Checkout straight neighbors:
			if(relativeGrid[7]) {
				if (relativeNeighborCount[7] >= relativeNeighborCount[12]) {
					pixels[x + 1][y].add(item, relativeNeighborCount[12]);
					pixels[x + 2][y].add(item, relativeNeighborCount[12]);
				}
				if (relativeGrid[1] and !relativeGrid[16] and straightNeighbors <= 1) {
					pixels[x + 2][y + 3].add(item, relativeNeighborCount[12]);
				}
				if (relativeGrid[3] and !relativeGrid[18] and straightNeighbors <= 1) {
					pixels[x + 1][y + 3].add(item, relativeNeighborCount[12]);
				}
			}
			if (relativeGrid[11]) {
				if (relativeNeighborCount[11] >= relativeNeighborCount[12]) {
					pixels[x][y + 1].add(item, relativeNeighborCount[12]);
					pixels[x][y + 2].add(item, relativeNeighborCount[12]);
				}
				if (relativeGrid[5] and !relativeGrid[8] and straightNeighbors <= 1) {
					pixels[x + 3][y + 2].add(item, relativeNeighborCount[12]);
				}
				if (relativeGrid[15] and !relativeGrid[18] and straightNeighbors <= 1) {
					pixels[x + 3][y + 1].add(item, relativeNeighborCount[12]);
				}
			}
			if (relativeGrid[13]) {
				if (relativeNeighborCount[13] >= relativeNeighborCount[12]) {
					pixels[x + 3][y + 1].add(item, relativeNeighborCount[12]);
					pixels[x + 3][y + 2].add(item, relativeNeighborCount[12]);
				}
				if (relativeGrid[9] and !relativeGrid[6] and straightNeighbors <= 1) {
					pixels[x][y + 2].add(item, relativeNeighborCount[12]);
				}
				if (relativeGrid[19] and !relativeGrid[16] and straightNeighbors <= 1) {
					pixels[x][y + 1].add(item, relativeNeighborCount[12]);
				}
			}
			if (relativeGrid[17]) {
				if (relativeNeighborCount[17] >= relativeNeighborCount[12]) {
					pixels[x + 1][y + 3].add(item, relativeNeighborCount[12]);
					pixels[x + 2][y + 3].add(item, relativeNeighborCount[12]);
				}
				if (relativeGrid[21] and !relativeGrid[6] and straightNeighbors <= 1) {
					pixels[x + 2][y].add(item, relativeNeighborCount[12]);
				}
				if (relativeGrid[23] and !relativeGrid[8] and straightNeighbors <= 1) {
					pixels[x + 1][y].add(item, relativeNeighborCount[12]);
				}
			}

			// Checkout diagonal neighbors:
			if (relativeGrid[6]) {
				if (relativeNeighborCount[6] >= relativeNeighborCount[12]) {
					pixels[x][y].add(item, relativeNeighborCount[12]);
				}
				pixels[x + 1][y].add(item, relativeNeighborCount[12]);
				pixels[x][y + 1].add(item, relativeNeighborCount[12]);
				if (relativeGrid[1] and !relativeGrid[7] and neighbors <= 2) {
					pixels[x + 3][y + 2].add(item, relativeNeighborCount[12]);
				}
				if (relativeGrid[5] and !relativeGrid[11] and neighbors <= 2) {
					pixels[x + 2][y + 3].add(item, relativeNeighborCount[12]);
				}
			}
			if (relativeGrid[8]) {
				if (relativeNeighborCount[8] >= relativeNeighborCount[12]) {
					pixels[x + 3][y].add(item, relativeNeighborCount[12]);
				}
				pixels[x + 2][y].add(item, relativeNeighborCount[12]);
				pixels[x + 3][y + 1].add(item, relativeNeighborCount[12]);
				if (relativeGrid[3] and !relativeGrid[7] and neighbors <= 2) {
					pixels[x][y + 2].add(item, relativeNeighborCount[12]);
				}
				if (relativeGrid[9] and !relativeGrid[13] and neighbors <= 2) {
					pixels[x + 1][y + 3].add(item, relativeNeighborCount[12]);
				}
			}
			if (relativeGrid[16]) {
				if (relativeNeighborCount[16] >= relativeNeighborCount[12]) {
					pixels[x][y + 3].add(item, relativeNeighborCount[12]);
				}
				pixels[x][y + 2].add(item, relativeNeighborCount[12]);
				pixels[x + 1][y + 3].add(item, relativeNeighborCount[12]);
				if (relativeGrid[21] and !relativeGrid[17] and neighbors <= 2) {
					pixels[x + 3][y + 1].add(item, relativeNeighborCount[12]);
				}
				if (relativeGrid[15] and !relativeGrid[11] and neighbors <= 2) {
					pixels[x + 2][y].add(item, relativeNeighborCount[12]);
				}
			}
			if (relativeGrid[18]) {
				if (relativeNeighborCount[18] >= relativeNeighborCount[12]) {
					pixels[x + 3][y + 3].add(item, relativeNeighborCount[12]);
				}
				pixels[x + 2][y + 3].add(item, relativeNeighborCount[12]);
				pixels[x + 3][y + 2].add(item, relativeNeighborCount[12]);
				if (relativeGrid[23] and !relativeGrid[17] and neighbors <= 2) {
					pixels[x][y + 1].add(item, relativeNeighborCount[12]);
				}
				if (relativeGrid[19] and !relativeGrid[13] and neighbors <= 2) {
					pixels[x + 1][y].add(item, relativeNeighborCount[12]);
				}
			}

			// Make stuff more round when there is many incoming connections:
			if (diagonalNeighbors >= 3 or straightNeighbors == 4) {
				pixels[x + 0][y + 1].add(item, relativeNeighborCount[12]);
				pixels[x + 0][y + 2].add(item, relativeNeighborCount[12]);
				pixels[x + 3][y + 1].add(item, relativeNeighborCount[12]);
				pixels[x + 3][y + 2].add(item, relativeNeighborCount[12]);
				pixels[x + 1][y + 0].add(item, relativeNeighborCount[12]);
				pixels[x + 1][y + 3].add(item, relativeNeighborCount[12]);
				pixels[x + 2][y + 0].add(item, relativeNeighborCount[12]);
				pixels[x + 2][y + 3].add(item, relativeNeighborCount[12]);
				// Check which of the neighbors was empty:
				if (relativeGrid[6] == null) {
					pixels[x + 0][y + 0].add(item, relativeNeighborCount[12]);
					pixels[x + 2][y - 1].add(item, relativeNeighborCount[12]);
					pixels[x - 1][y + 2].add(item, relativeNeighborCount[12]);
				}
				if (relativeGrid[8] == null) {
					pixels[x + 3][y + 0].add(item, relativeNeighborCount[12]);
					pixels[x + 1][y - 1].add(item, relativeNeighborCount[12]);
					pixels[x + 4][y + 2].add(item, relativeNeighborCount[12]);
				}
				if (relativeGrid[16] == null) {
					pixels[x + 0][y + 3].add(item, relativeNeighborCount[12]);
					pixels[x + 2][y + 4].add(item, relativeNeighborCount[12]);
					pixels[x - 1][y + 1].add(item, relativeNeighborCount[12]);
				}
				if (relativeGrid[18] == null) {
					pixels[x + 3][y + 3].add(item, relativeNeighborCount[12]);
					pixels[x + 1][y + 4].add(item, relativeNeighborCount[12]);
					pixels[x + 4][y + 1].add(item, relativeNeighborCount[12]);
				}
			}
		}
	}

	fn generateHeightMap(itemGrid: *[16][16]?*BaseItem, seed: *u64) [17][17]f32 {
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
						const otherItem = itemGrid[@intCast(usize, x + dx)][@intCast(usize, y + dy)];
						heightMap[x][y] = if(otherItem) |item| 1 + (4*random.nextFloat(seed) - 2)*item.material.roughness else 0;
						if(otherItem != oneItem) {
							hasDifferentItems = true;
						}
					}
				}

				// If there is multiple items at this junction, make it go inward to make embedded parts stick out more:
				if (hasDifferentItems) {
					heightMap[x][y] -= 1;
				}
				
				// Take into account further neighbors with lower priority:
				dx = -2;
				while(dx <= 1) : (dx += 1) {
					if(x + dx < 0 or x + dx >= 16) continue;
					var dy: i32 = -2;
					while(dy <= 1) : (dy += 1) {
						if(y + dy < 0 or y + dy >= 16) continue;
						const otherItem = itemGrid[@intCast(usize, x + dx)][@intCast(usize, y + dy)];
						const dVec = Vec2f{@intToFloat(f32, dx) + 0.5, @intToFloat(f32, dy) + 0.5};
						heightMap[x][y] += if(otherItem) 1.0/vec.dot(dVec, dVec) else 0;
					}
				}
			}
		}
		return heightMap;
	}

	pub fn generate(tool: *Tool) void {
		const img = tool.texture;
		var pixelMaterials: [16][16]PixelData = undefined;
		var x: u8 = 0;
		while(x < 16) : (x += 1) {
			var y: u8 = 0;
			while(y < 16) : (y += 1) {
				pixelMaterials[x][y] = PixelData.init(main.threadAllocator);
			}
		}

		defer { // TODO: Maybe use an ArenaAllocator?
			x = 0;
			while(x < 16) : (x += 1) {
				var y: u8 = 0;
				while(y < 16) : (y += 1) {
					pixelMaterials[x][y].deinit();
				}
			}
		}
		
		var seed: u64 = tool.seed;
		random.scrambleSeed(&seed);

		// Count all neighbors:
		var neighborCount: [25]u8 = [_]u8{0} ** 25;
		x = 0;
		while(x < 5) : (x += 1) {
			var y: u8 = 0;
			while(y < 5) : (y += 1) {
				var offsetGrid: [25]?*const BaseItem = undefined;
				var dx: i32 = -2;
				while(dx <= 2) : (dx += 1) {
					var dy: i32 = -2;
					while(dy <= 2) : (dy += 1) {
						if(x + dx >= 0 and x + dx < 5 and y + dy >= 0 and y + dy < 5) {
							const index = @intCast(usize, x + dx + 5*(y + dy));
							const offsetIndex = @intCast(usize, 2 + dx + 5*(2 + dy));
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
				var offsetGrid: [25]?*const BaseItem = undefined;
				var offsetNeighborCount: [25]u8 = undefined;
				var dx: i32 = -2;
				while(dx <= 2) : (dx += 1) {
					var dy: i32 = -2;
					while(dy <= 2) : (dy += 1) {
						if(x + dx >= 0 and x + dx < 5 and y + dy >= 0 and y + dy < 5) {
							const index = @intCast(usize, x + dx + 5*(y + dy));
							const offsetIndex = @intCast(usize, 2 + dx + 5*(2 + dy));
							offsetGrid[offsetIndex] = tool.craftingGrid[index];
							offsetNeighborCount[offsetIndex] = neighborCount[index];
						}
					}
				}
				const index = x + 5*y;
				drawRegion(&offsetGrid, &offsetNeighborCount, GRID_CENTERS_X[index] - 2, GRID_CENTERS_Y[index] - 2, pixelMaterials);
			}
		}

		var itemGrid = &tool.materialGrid;
		x = 0;
		while(x < 16) : (x += 1) {
			var y: u8 = 0;
			while(y < 16) : (y += 1) {
				if(pixelMaterials[x][y].items.items.len != 0) {
					// Choose a random material at conflict zones:
					itemGrid[x][y] = pixelMaterials[x][y].items.items[random.nextIntBounded(u8, &seed, pixelMaterials[x][y].items.items.len)];
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
						const light = 2 - @floatToInt(u32, @round((lightTL * 2 + lightTR) / 6));
						light = @max(@min(light, 4), 0);
						img.setRGB(x, y, material.colorPalette[light]);
					}
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
				if(tool.craftingGrid[y + x]) {
					break :outer;
				}
			}
		}
		// Find a valid handle:
		// Goes from right to left.
		// TODO: Add left-hander setting that mirrors the x axis of the tools and the crafting grid
		var x: u32 = 4;
		while(true) {
			if(tool.craftingGrid[y + x]) {
				tool.handlePosition.x = TextureGenerator.GRID_CENTERS_X[x + y] - 0.5;
				tool.handlePosition.y = TextureGenerator.GRID_CENTERS_Y[x + y] - 0.5;
				// Count the neighbors to determine whether it's a good handle:
				var neighbors: u32 = 0;
				if(x != 0 and tool.craftingGrid[y + x - 1])
					neighbors += 1;
				if(x != 4 and tool.craftingGrid[y + x + 1])
					neighbors += 1;
				if(y != 0) {
					if(tool.craftingGrid[y - 5 + x])
						neighbors += 1;
					if(x != 0 and tool.craftingGrid[y - 5 + x - 1])
						neighbors += 1;
					if(x != 4 and tool.craftingGrid[y - 5 + x + 1])
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
						centerOfMass.x += localMass*(@intToFloat(f32, x) + 0.5);
						centerOfMass.y += localMass*(@intToFloat(f32, y) + 0.5);
						mass += localMass;
					}
				}
			}
		}
		tool.centerOfMass = centerOfMass/@splat(2, mass);
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
						const dx = @intToFloat(f32, x) + 0.5 - tool.centerOfMass.x;
						const dy = @intToFloat(f32, y) + 0.5 - tool.centerOfMass.y;
						inertia += localMass*(dx*dx + dy*dy);
					}
				}
			}
		}
		tool.inertiaCenterOfMass = inertia;
		// Using the parallel axis theorem the inertia relative to the handle can be derived:
		tool.inertiaHandle = inertia + mass * tool.centerOfMass.distance(tool.handlePosition);
	}

	/// Determines the sharpness of a point on the tool.
	fn determineSharpness(tool: *Tool, point: *Vec3i, initialAngle: f32) void {
		const center: Vec2f = tool.handlePosition - vec.normalize(tool.centerOfMass - tool.handlePosition)*16; // Going 16 pixels away from the handle to simulate arm length.
		// A region is smooth if there is a lot of pixel within similar angle/distance:
		const originalAngle = std.math.atan2(f32, @intToFloat(f32, point.y) + 0.5 - center.y, @intToFloat(f32, point.x) + 0.5 - center.x) - initialAngle;
		const originalDistance = @cos(originalAngle)*vec.length(center - Vec2f{@intToFloat(f32, point.x) + 0.5, @intToFloat(f32, point.y) + 0.5});
		var numOfSmoothPixels: u32 = 0;
		var x: f32 = 0;
		while(x < 16) : (x += 1) {
			var y: f32 = 0;
			while(y < 16) : (y += 1) {
				const angle = std.math.atan2(f32, y + 0.5 - center.y, x + 0.5 - center.x) - initialAngle;
				const distance = @cos(angle)*vec.length(center - Vec2f{x + 0.5, y + 0.5});
				const deltaAngle = @fabs(angle - originalAngle);
				const deltaDist = @fabs(distance - originalDistance);
				if(deltaAngle <= 0.2 and deltaDist <= 0.7) {
					numOfSmoothPixels += 1;
				}
			}
		}
		point.z = numOfSmoothPixels;
	}

	/// Determines where the tool would collide with the terrain.
	/// Also evaluates the smoothness of the collision point and stores it in the z component.
	fn determineCollisionPoints(tool: *Tool, leftCollisionPoint: *Vec3i, rightCollisionPoint: *Vec3i, frontCollisionPoint: *Vec3i, factor: f32) void {
		// For finding that point the center of rotation is assumed to be 1 arm(16 pixel) begind the handle.
		// Additionally the handle is assumed to go towards the center of mass.
		const center: Vec2f = tool.handlePosition - vec.normalize(tool.centerOfMass - tool.handlePosition)*factor; // Going some distance away from the handle to simulate arm length.
		// Angle of the handle.
		const initialAngle = std.math.atan2(f32, tool.handlePosition.y - center.y, tool.handlePosition.x - center.x);
		var leftCollisionAngle: f32 = 0;
		var rightCollisionAngle: f32 = 0;
		var frontCollisionDistance: f32 = 0;
		var x: i32 = 0;
		while(x < 16) : (x += 1) {
			var y: i32 = 0;
			while(y < 16) : (y += 1) {
				if(!tool.materialGrid[x][y]) continue;
				const x_float = @intToFloat(f32, x);
				const y_float = @intToFloat(f32, y);
				const angle = std.math.atan2(f32, y_float + 0.5 - center.y, x_float + 0.5 - center.x) - initialAngle;
				const distance = @cos(angle)*vec.length(center - Vec2f{x_float + 0.5, y_float + 0.5});
				if(angle < leftCollisionAngle) {
					leftCollisionAngle = angle;
					leftCollisionPoint = Vec3i{x, y, 0};
				}
				if(angle > rightCollisionAngle) {
					rightCollisionAngle = angle;
					rightCollisionPoint = Vec3i{x, y, 0};
				}
				if(distance > frontCollisionDistance) {
					frontCollisionDistance = distance;
					frontCollisionPoint = Vec3i{x, y, 0};
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
		var x: u32 = 0;
		while(x < 16) : (x += 1) {
			var y: u32 = 0;
			while(y < 16) : (y += 1) {
				if(tool.materialGrid[x][y]) |item| {
					if(item.material) |material| {
						durability += material.resistance;
					}
				}
			}
		}
		// Smaller tools are faster to swing. To balance that smaller tools get a lower durability.
		tool.maxDurability = @max(1, std.math.pow(f32, durability/4, 1.5));
		tool.durability = tool.maxDurability;
	}

	/// Determines how hard the tool hits the ground.
	fn calculateImpactEnergy(tool: *Tool, collisionPoint: Vec3i) f32 {
		// Fun fact: Without gravity the impact energy is independent of the mass of the pickaxe(E = ∫ F⃗ ds⃗), but only on the length of the handle.
		var impactEnergy: f32 = vec.length(tool.centerOfMass - tool.handlePosition);

		// But when the pickaxe does get heavier 2 things happen:
		// 1. The player needs to lift a bigger weight, so the tool speed gets reduced(calculated elsewhere).
		// 2. When travelling down the tool also gets additional energy from gravity, so the force is increased by m·g.
		impactEnergy *= tool.materialGrid[collisionPoint.x][collisionPoint.y].?.material.?.power + tool.mass/256;

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
				if(x + collisionPointLower.x >= 0 and x + collisionPointLower.x < 16) {
					if(y + collisionPointLower.y >= 0 and y + collisionPointLower.y < 16) {
						if(tool.materialGrid[x + collisionPointLower.x][y + collisionPointLower.y])
							neighborsLower += 1;
					}
				}
			}
		}
		var neighborsUpper: u32 = 0;
		var dirUpper: Vec2i = Vec2i{0};
//		Vector2i dirUpper = new Vector2i();
		x = -1;
		while(x < 2) : (x += 1) {
			var y: i32 = -1;
			while(y <= 2) : (y += 1) {
				if(x + collisionPointUpper.x >= 0 and x + collisionPointUpper.x < 16) {
					if(y + collisionPointUpper.y >= 0 and y + collisionPointUpper.y < 16) {
						if(tool.materialGrid[x + collisionPointUpper.x][y + collisionPointUpper.y]) {
							neighborsUpper += 1;
							dirUpper.x += x;
							dirUpper.y += y;
						}
					}
				}
			}
		}
		if (neighborsLower > 3 and neighborsUpper > 3) return 0;

		// A pickaxe never points upwards:
		if (neighborsUpper == 3 and dirUpper.y == 2) {
			return 0;
		}

		return calculateImpactEnergy(tool, collisionPointLower);
	}

	/// Determines how good an axe this side of the tool would make.
	fn evaluateAxePower(tool: *Tool, collisionPointLower: Vec3i, collisionPointUpper: Vec3i) f32 {
		// Axes are used for breaking up wood. This requires a larger area (= smooth tip) rather than a sharp tip.
		const collisionPointLowerFloat = Vec2f{@intToFloat(f32, collisionPointLower.x), @intToFloat(f32, collisionPointLower.y)};
		const collisionPointUpperFloat = Vec2f{@intToFloat(f32, collisionPointUpper.x), @intToFloat(f32, collisionPointUpper.y)};
		const areaFactor = 0.25 + vec.length(collisionPointLowerFloat - collisionPointUpperFloat)/4;

		return areaFactor*calculateImpactEnergy(tool, collisionPointLower)/8;
	}

	/// Determines how good a shovel this side of the tool would make.
	fn evaluateShovelPower(tool: *Tool, collisionPoint: Vec3i) !f32 {
		// Shovels require a large area to put all the sand on.
		// For the sake of simplicity I just assume that every part of the tool can contain sand and that sand piles up in a pyramidial shape.
		var sandPiles: [16][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 16;
		const Entry = struct {
			x: u8,
			y: u8,
		};
		var stack = std.ArrayList(Entry).init(main.threadAllocator);
		defer stack.deinit();
		// Uses a simple flood-fill algorithm equivalent to light calculation.
		var x: u8 = 0;
		while(x < 16) : (x += 1) {
			var y: u8 = 0;
			while(y < 16) : (y += 1) {
				sandPiles[x][y] = std.math.maxInt(u8);
				if (!tool.materialGrid[x][y]) {
					sandPiles[x][y] = 0;
					try stack.append(Entry{.x=x, .y=y});
				} else if (x == 0 or x == 15 or y == 0 or y == 15) {
					sandPiles[x][y] = 1;
					try stack.append(Entry{.x=x, .y=y});
				}
			}
		}
		while(stack.popOrNull()) |entry| {
			x = entry.x;
			const y = entry.y;
			if(x != 0 and y != 0 and tool.materialGrid[x - 1][y - 1]) {
				if(sandPiles[x - 1][y - 1] > sandPiles[x][y] + 1) {
					sandPiles[x - 1][y - 1] = sandPiles[x][y] + 1;
					stack.append(Entry{.x=x-1, .y=y-1});
				}
			}
			if(x != 0 and y != 15 and tool.materialGrid[x - 1][y + 1]) {
				if(sandPiles[x - 1][y + 1] > sandPiles[x][y] + 1) {
					sandPiles[x - 1][y + 1] = sandPiles[x][y] + 1;
					stack.append(Entry{.x=x-1, .y=y+1});
				}
			}
			if(x != 15 and y != 0 and tool.materialGrid[x + 1][y - 1]) {
				if(sandPiles[x + 1][y - 1] > sandPiles[x][y] + 1) {
					sandPiles[x + 1][y - 1] = sandPiles[x][y] + 1;
					stack.append(Entry{.x=x+1, .y=y-1});
				}
			}
			if(x != 15 and y != 15 and tool.materialGrid[x + 1][y + 1]) {
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
				volume += sandPiles[x][y];
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
		var leftCollisionPointLower = Vec3i{};
		var rightCollisionPointLower = Vec3i{};
		var frontCollisionPointLower = Vec3i{};
		var leftCollisionPointUpper = Vec3i{};
		var rightCollisionPointUpper = Vec3i{};
		var frontCollisionPointUpper = Vec3i{};
		determineCollisionPoints(tool, &leftCollisionPointLower, &rightCollisionPointLower, &frontCollisionPointLower, 16);
		determineCollisionPoints(tool, &rightCollisionPointUpper, &leftCollisionPointUpper, &frontCollisionPointUpper, -20);

		const leftPP = evaluatePickaxePower(tool, &leftCollisionPointLower, &leftCollisionPointUpper);
		const rightPP = evaluatePickaxePower(tool, &rightCollisionPointLower, &rightCollisionPointUpper);
		tool.pickaxePower = @max(leftPP, rightPP); // TODO: Adjust the swing direction.

		const leftAP = evaluateAxePower(tool, &leftCollisionPointLower, &leftCollisionPointUpper);
		const rightAP = evaluateAxePower(tool, &rightCollisionPointLower, &rightCollisionPointUpper);
		tool.axePower = @max(leftAP, rightAP); // TODO: Adjust the swing direction.

		tool.shovelPower = evaluateShovelPower(tool, &frontCollisionPointLower);

		// It takes longer to swing a heavy tool.
		tool.swingTime = (tool.mass + tool.inertiaHandle/8)/256; // TODO: Balancing

		if (hasGoodHandle) { // Good handles make tools easier to handle.
			tool.swingTime /= 2.0;
		}

		// TODO: Swords and throwing weapons.

	}
};

const Tool = struct {
	craftingGrid: [25]?*const BaseItem,
	materialGrid: [16][16]?*const BaseItem,
	texture: graphics.Image,
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

	pub fn init(allocator: Allocator) !*Tool {
		var self = try allocator.create(Tool);
		self.texture = try graphics.Image.init(allocator, 16, 16);
		return self;
	}

	pub fn deinit(self: *Tool, allocator: Allocator) void {
		allocator.destroy(self);
		self.texture.deinit(allocator);
	}

	pub fn initFromCraftingGrid(allocator: Allocator, craftingGrid: [25]?*const BaseItem, seed: u32) !*Tool {
		var self = try init(allocator);
		self.seed = seed;
		self.craftingGrid = craftingGrid;
		// Produce the tool and its textures:
		// The material grid, which comes from texture generation, is needed on both server and client, to generate the tool properties.
		TextureGenerator.generate(self);
		ToolPhysics.evaluateTool(self);
		return self;
	}

	pub fn initFromJson(allocator: Allocator, jsonObject: JsonElement) !*Tool {
		var self = try initFromCraftingGrid(allocator, extractItemsFromJson(jsonObject.getChild("grid")), jsonObject.get(u32, "seed", 0));
		self.durability = jsonObject.get(i32, "durability", self.maxDurability);
		return self;
	}

	fn extractItemsFromJson(jsonArray: JsonElement) [25]?*const BaseItem {
		var items: [25]?*const BaseItem = undefined;
		for(items) |*item, i| {
			item.* = reverseIndices.get(jsonArray.getAtIndex([]const u8, i, "null"));
		}
		return items;
	}

	pub fn save(self: *Tool, allocator: Allocator) !JsonElement {
		var jsonObject = try JsonElement.initObject(allocator);
		var jsonArray = try JsonElement.initArray(allocator);
		for(self.craftingGrid) |nullItem| {
			if(nullItem) |item| {
				try jsonArray.JsonArray.append(JsonElement{.JsonString=item.id});
			} else {
				try jsonArray.JsonArray.append(JsonElement{.JsonNull={}});
			}
		}
		try jsonObject.put("grid", jsonArray);
		try jsonObject.put("durability", self.durability);
		try jsonObject.put("seed", self.seed);
		return jsonObject;
	}
// TODO: Check if/how this is needed:
//	@Override
//	public int hashCode() {
//		int hash = 0;
//		for(Item item : craftingGrid) {
//			if (item != null) {
//				hash = 33 * hash + item.material.hashCode();
//			}
//		}
//		return hash;
//	}

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

pub const Item = union(u8) {
	baseItem: *const BaseItem,
	tool: *const Tool,

	pub fn init(self: *Item, allocator: Allocator) !void {
		_ = allocator;
		_ = self;

	}

	pub fn deinit(self: Item, allocator: Allocator) void {
		switch(self) {
			.baseItem => {
				
			},
			.tool => |_tool| {
				_tool.deinit(allocator);
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

	pub fn insertIntoJson(self: Item, allocator: Allocator, jsonObject: JsonElement) !void {
		switch(self) {
			.baseItem => |_baseItem| {
				try jsonObject.put("item", _baseItem.id);
			},
			.tool => |_tool| {
				json.put("tool", _tool.toJson(allocator));
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

	pub fn filled(self: *ItemStack) bool {
		if(self.item) |item| {
			return self.amount >= item.stackSize();
		}
	}

	pub fn empty(self: *ItemStack) bool {
		return self.amount == 0;
	}

	/// Returns the number of items actually added/removed.
	pub fn add(self: *ItemStack, number: i32) i32 {
		std.debug.assert(self.item);
		const newAmount = self.amount + number;
		var returnValue: i32 = 0;
		if(newAmount < 0) {
			returnValue = number - newAmount;
			newAmount = 0;
		} else if(newAmount > self.item.?.stackSize()) {
			returnValue = number - newAmount + self.item.?.stackSize();
			newAmount = self.item.?.stackSize();
		}
		self.amount = @intCast(u16, newAmount);
		if(self.empty()) {
			self.clear();
		}
		return returnValue;
	}

	/// whether the given number of items can be added to this stack.
	pub fn canAddAll(self: *ItemStack, number: u16) bool {
		std.debug.assert(self.item);
		return @as(u32, self.amount) + number <= self.item.?.stackSize();
	}

	pub fn clear(self: *ItemStack) void {
		if(self.item) |item| {
			item.deinit();
		}
		self.item = null;
		self.amount = 0;
	}

	pub fn store(self: *ItemStack, allocator: Allocator) !JsonElement {
		var result = try JsonElement.initObject(allocator);
		if(self.item) |item| {
			item.insertToJson(allocator, result);
			result.put("amount", self.amount);
		}
		return result;
	}

// TODO: Check if/how this is needed:
//	public void update() {}
//	
//	public int getBlock() {
//		if (item == null)
//			return 0;
//		if (item instanceof ItemBlock)
//			return ((ItemBlock) item).getBlock();
//		else
//			return 0;
//	}
};

var arena: std.heap.ArenaAllocator = undefined;
var reverseIndices: std.StringHashMap(*BaseItem) = undefined;
var itemList: std.ArrayList(BaseItem) = undefined;


pub fn globalInit() void {
	arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
	reverseIndices = std.StringHashMap(*BaseItem).init(arena.allocator());
	itemList = std.ArrayList(BaseItem).init(arena.allocator());
}

pub fn register(_: []const u8, id: []const u8, jsonObject: JsonElement) !void {
	if(reverseIndices.contains(id)) {
		std.log.warn("Registered block with id {s} twice!", .{id});
	}
	try (try itemList.addOne()).init(arena.allocator(), id, jsonObject);
}

pub fn reset() void {
	reverseIndices.clearAndFree();
	itemList.clearAndFree();
	// TODO: Use arena.reset() instead.
	arena.deinit();
	arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
}

pub fn deinit() void {
	reverseIndices.clearAndFree();
	itemList.clearAndFree();
	arena.deinit();
}