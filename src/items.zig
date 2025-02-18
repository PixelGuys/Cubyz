const std = @import("std");

const blocks = @import("blocks.zig");
const Block = blocks.Block;
const graphics = @import("graphics.zig");
const Color = graphics.Color;
const ZonElement = @import("zon.zig").ZonElement;
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

pub const Inventory = @import("Inventory.zig");

/// Holds the basic properties of a tool crafting material.
const Material = struct { // MARK: Material
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

	pub fn init(self: *Material, allocator: NeverFailingAllocator, zon: ZonElement) void {
		self.density = zon.get(f32, "density", 1.0);
		self.resistance = zon.get(f32, "resistance", 1.0);
		self.power = zon.get(f32, "power", 1.0);
		self.roughness = @max(0, zon.get(f32, "roughness", 1.0));
		const colors = zon.getChild("colors");
		self.colorPalette = allocator.alloc(Color, colors.array.items.len);
		for(colors.array.items, self.colorPalette) |item, *color| {
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

	fn getProperty(self: Material, prop: MaterialProperty) f32 {
		switch(prop) {
			inline else => |field| return @field(self, @tagName(field)),
		}
	}
};

const MaterialProperty = enum {
	density,
	resistance,
	power,

	fn fromString(string: []const u8) MaterialProperty {
		return std.meta.stringToEnum(MaterialProperty, string) orelse {
			std.log.err("Couldn't find material property {s}. Replacing it with power", .{string});
			return .power;
		};
	}
};


pub const BaseItem = struct { // MARK: BaseItem
	image: graphics.Image,
	texture: ?graphics.Texture, // TODO: Properly deinit
	id: []const u8,
	name: []const u8,

	stackSize: u16,
	material: ?Material,
	block: ?u16,
	foodValue: f32, // TODO: Effects.

	var unobtainable = BaseItem {
		.image = graphics.Image.defaultImage,
		.texture = null,
		.id = "unobtainable",
		.name = "unobtainable",
		.stackSize = 0,
		.material = null,
		.block = null,
		.foodValue = 0,
	};

	fn init(self: *BaseItem, allocator: NeverFailingAllocator, texturePath: []const u8, replacementTexturePath: []const u8, id: []const u8, zon: ZonElement) void {
		self.id = allocator.dupe(u8, id);
		if(texturePath.len == 0) {
			self.image = graphics.Image.defaultImage;
		} else {
			self.image = graphics.Image.readFromFile(allocator, texturePath) catch graphics.Image.readFromFile(allocator, replacementTexturePath) catch blk: {
				std.log.err("Item texture not found in {s} and {s}.", .{texturePath, replacementTexturePath});
				break :blk graphics.Image.defaultImage;
			};
		}
		self.name = allocator.dupe(u8, zon.get([]const u8, "name", id));
		self.stackSize = zon.get(u16, "stackSize", 120);
		const material = zon.getChild("material");
		if(material == .object) {
			self.material = Material{};
			self.material.?.init(allocator, material);
		} else {
			self.material = null;
		}
		self.block = blk: {
			break :blk blocks.getTypeById(zon.get(?[]const u8, "block", null) orelse break :blk null);
		};
		self.texture = null;
		self.foodValue = zon.get(f32, "food", 0);
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
			if(self.image.imageData.ptr == graphics.Image.defaultImage.imageData.ptr) {
				if(self.block) |blockType| {
					self.texture = graphics.generateBlockTexture(blockType);
				} else {
					self.texture = graphics.Texture.init();
					self.texture.?.generate(self.image);
				}
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
const TextureGenerator = struct { // MARK: TextureGenerator
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
		for(0..16) |x| {
			for(0..16) |y| {
				const source = tool.type.pixelSources[x][y];
				tool.materialGrid[x][y] = if(source < 25) tool.craftingGrid[source] else null;
			}
		}

		var seed: u64 = tool.seed;
		random.scrambleSeed(&seed);

		// Generate a height map, which will be used for lighting calulations.
		const heightMap = generateHeightMap(&tool.materialGrid, &seed);
		var x: u8 = 0;
		while(x < 16) : (x += 1) {
			var y: u8 = 0;
			while(y < 16) : (y += 1) {
				if(tool.materialGrid[x][y]) |item| {
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
const ToolPhysics = struct { // MARK: ToolPhysics
	/// Determines all the basic properties of the tool.
	pub fn evaluateTool(tool: *Tool) void {
		inline for(comptime std.meta.fieldNames(ToolProperty)) |name| {
			@field(tool, name) = 0;
		}
		for(0..25) |i| {
			const material = (tool.craftingGrid[i] orelse continue).material orelse continue;
			for(tool.type.slotInfos[i].parameters) |set| {
				tool.getProperty(set.destination).* += set.factor*set.functionType.eval(material.getProperty(set.source) + set.additionConstant);
			}
		}
		tool.durability = @max(1, std.math.lossyCast(u32, tool.maxDurability));
	}
};

const SlotInfo = struct {// MARK: SlotInfo
	parameters: []ParameterSet = &.{},
	disabled: bool = false,
	optional: bool = false,
};

const ParameterSet = struct {
	source: MaterialProperty,
	destination: ToolProperty,
	factor: f32,
	additionConstant: f32,
	functionType: FunctionType,
};

const FunctionType = enum {
	linear,
	square,
	squareRoot,
	exp2,
	log2,

	fn eval(self: FunctionType, val: f32) f32 {
		switch(self) {
			.linear => return val,
			.square => return val*val,
			.squareRoot => return @sqrt(val),
			.exp2 => return @exp2(val),
			.log2 => return @log2(val),
		}
	}

	fn fromString(string: []const u8) FunctionType {
		return std.meta.stringToEnum(FunctionType, string) orelse {
			std.log.err("Couldn't find function type {s}. Replacing it with linear", .{string});
			return .linear;
		};
	}
};

pub const ToolType = struct { // MARK: ToolType
	id: []const u8,
	blockClass: main.blocks.BlockClass,
	slotInfos: [25]SlotInfo,
	pixelSources: [16][16]u8,
};

const ToolProperty = enum {
	power,
	maxDurability,
	swingTime,

	fn fromString(string: []const u8) ToolProperty {
		return std.meta.stringToEnum(ToolProperty, string) orelse {
			std.log.err("Couldn't find tool property {s}. Replacing it with power", .{string});
			return .power;
		};
	}
};

pub const Tool = struct { // MARK: Tool
	craftingGrid: [25]?*const BaseItem,
	materialGrid: [16][16]?*const BaseItem,
	tooltip: main.List(u8),
	image: graphics.Image,
	texture: ?graphics.Texture,
	seed: u32,
	type: *const ToolType,

	power: f32,

	durability: u32,
	maxDurability: f32,

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
		self.tooltip = .init(main.globalAllocator);
		return self;
	}

	pub fn deinit(self: *const Tool) void {
		if(self.texture) |texture| {
			texture.deinit();
		}
		self.image.deinit(main.globalAllocator);
		self.tooltip.deinit();
		main.globalAllocator.destroy(self);
	}

	pub fn clone(self: *const Tool) *Tool {
		const result = main.globalAllocator.create(Tool);
		result.* = .{
			.craftingGrid = self.craftingGrid,
			.materialGrid = self.materialGrid,
			.tooltip = .init(main.globalAllocator),
			.image = graphics.Image.init(main.globalAllocator, self.image.width, self.image.height),
			.texture = null,
			.seed = self.seed,
			.type = self.type,
			.power = self.power,
			.durability = self.durability,
			.maxDurability = self.maxDurability,
			.swingTime = self.swingTime,
			.mass = self.mass,
			.handlePosition = self.handlePosition,
			.inertiaHandle = self.inertiaHandle,
			.centerOfMass = self.centerOfMass,
			.inertiaCenterOfMass = self.inertiaCenterOfMass,
		};
		@memcpy(result.image.imageData, self.image.imageData);
		return result;

	}

	pub fn initFromCraftingGrid(craftingGrid: [25]?*const BaseItem, seed: u32, typ: *const ToolType) *Tool {
		const self = init();
		self.seed = seed;
		self.craftingGrid = craftingGrid;
		self.type = typ;
		// Produce the tool and its textures:
		// The material grid, which comes from texture generation, is needed on both server and client, to generate the tool properties.
		TextureGenerator.generate(self);
		ToolPhysics.evaluateTool(self);
		return self;
	}

	pub fn initFromZon(zon: ZonElement) *Tool {
		const self = initFromCraftingGrid(extractItemsFromZon(zon.getChild("grid")), zon.get(u32, "seed", 0), getToolTypeByID(zon.get([]const u8, "type", "cubyz:pickaxe")) orelse blk: {
			std.log.err("Couldn't find tool with type {s}. Replacing it with cubyz:pickaxe", .{zon.get([]const u8, "type", "cubyz:pickaxe")});
			break :blk getToolTypeByID("cubyz:pickaxe") orelse @panic("cubyz:pickaxe tool not found. Did you load the game with the correct assets?");
		});
		self.durability = zon.get(u32, "durability", std.math.lossyCast(u32, self.maxDurability));
		return self;
	}

	fn extractItemsFromZon(zonArray: ZonElement) [25]?*const BaseItem {
		var items: [25]?*const BaseItem = undefined;
		for(&items, 0..) |*item, i| {
			item.* = reverseIndices.get(zonArray.getAtIndex([]const u8, i, "null"));
		}
		return items;
	}

	pub fn save(self: *const Tool, allocator: NeverFailingAllocator) ZonElement {
		const zonObject = ZonElement.initObject(allocator);
		const zonArray = ZonElement.initArray(allocator);
		for(self.craftingGrid) |nullItem| {
			if(nullItem) |item| {
				zonArray.array.append(.{.string=item.id});
			} else {
				zonArray.array.append(.null);
			}
		}
		zonObject.put("grid", zonArray);
		zonObject.put("durability", self.durability);
		zonObject.put("seed", self.seed);
		zonObject.put("type", self.type.id);
		return zonObject;
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

	fn getProperty(self: *Tool, prop: ToolProperty) *f32 {
		switch(prop) {
			inline else => |field| return &@field(self, @tagName(field)),
		}
	}

	fn getTexture(self: *Tool) graphics.Texture {
		if(self.texture == null) {
			self.texture = graphics.Texture.init();
			self.texture.?.generate(self.image);
		}
		return self.texture.?;
	}

	fn getTooltip(self: *Tool) []const u8 {
		self.tooltip.clearRetainingCapacity();
		self.tooltip.writer().print(
			\\{s}
			\\Time to swing: {d:.2} s
			\\Power: {} %
			\\Durability: {}/{}
			,
			.{
				self.type.id,
				self.swingTime,
				@as(i32, @intFromFloat(100*self.power)),
				self.durability, std.math.lossyCast(u32, self.maxDurability),
			}
		) catch unreachable;
		return self.tooltip.items;
	}

	pub fn getPowerByBlockClass(self: *Tool, blockClass: blocks.BlockClass) f32 {
		if(blockClass == self.type.blockClass) return self.power;
		return 0;
	}

	pub fn onUseReturnBroken(self: *Tool) bool {
		self.durability -|= 1;
		return self.durability == 0;
	}
};

pub const Item = union(enum) { // MARK: Item
	baseItem: *BaseItem,
	tool: *Tool,

	pub fn init(zon: ZonElement) !Item {
		if(reverseIndices.get(zon.get([]const u8, "item", "null"))) |baseItem| {
			return Item{.baseItem = baseItem};
		} else {
			const toolZon = zon.getChild("tool");
			if(toolZon != .object) return error.ItemNotFound;
			return Item{.tool = Tool.initFromZon(toolZon)};
		}
	}

	pub fn deinit(self: Item) void {
		switch(self) {
			.baseItem => {},
			.tool => |_tool| {
				_tool.deinit();
			},
		}
	}

	pub fn clone(self: Item) Item {
		switch(self) {
			.baseItem => return self,
			.tool => |tool| {
				return .{.tool = tool.clone()};
			}
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

	pub fn insertIntoZon(self: Item, allocator: NeverFailingAllocator, zonObject: ZonElement) void {
		switch(self) {
			.baseItem => |_baseItem| {
				zonObject.put("item", _baseItem.id);
			},
			.tool => |_tool| {
				zonObject.put("tool", _tool.save(allocator));
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

pub const ItemStack = struct { // MARK: ItemStack
	item: ?Item = null,
	amount: u16 = 0,

	pub fn load(zon: ZonElement) !ItemStack {
		return .{
			.item = try Item.init(zon),
			.amount = zon.get(?u16, "amount", null) orelse return error.InvalidAmount,
		};
	}

	pub fn deinit(self: *ItemStack) void {
		if(self.item) |item| {
			item.deinit();
		}
	}

	pub fn clone(self: *const ItemStack) ItemStack {
		const item = self.item orelse return .{};
		return .{
			.item = item.clone(),
			.amount = self.amount,
		};
	}

	pub fn empty(self: *const ItemStack) bool {
		return self.amount == 0;
	}

	pub fn clear(self: *ItemStack) void {
		self.item = null;
		self.amount = 0;
	}

	pub fn storeToZon(self: *const ItemStack, allocator: NeverFailingAllocator, zonObject: ZonElement) void {
		if(self.item) |item| {
			item.insertIntoZon(allocator, zonObject);
			zonObject.put("amount", self.amount);
		}
	}

	pub fn store(self: *const ItemStack, allocator: NeverFailingAllocator) ZonElement {
		const result = ZonElement.initObject(allocator);
		self.storeToZon(allocator, result);
		return result;
	}
};

pub const Recipe = struct { // MARK: Recipe
	sourceItems: []*BaseItem,
	sourceAmounts: []u16,
	resultItem: *BaseItem,
	resultAmount: u16,
	cachedInventory: ?Inventory = null,
};

var arena: main.utils.NeverFailingArenaAllocator = undefined;
var toolTypes: std.StringHashMap(ToolType) = undefined;
var reverseIndices: std.StringHashMap(*BaseItem) = undefined;
pub var itemList: [65536]BaseItem = undefined;
pub var itemListSize: u16 = 0;

var recipeList: main.List(Recipe) = undefined;

pub fn toolTypeIterator() std.StringHashMap(ToolType).ValueIterator {
	return toolTypes.valueIterator();
}

pub fn iterator() std.StringHashMap(*BaseItem).ValueIterator {
	return reverseIndices.valueIterator();
}

pub fn recipes() []Recipe {
	return recipeList.items;
}

pub fn globalInit() void {
	arena = .init(main.globalAllocator);
	toolTypes = .init(arena.allocator().allocator);
	reverseIndices = .init(arena.allocator().allocator);
	recipeList = .init(arena.allocator());
	itemListSize = 0;
	Inventory.Sync.ClientSide.init();
}

pub fn register(_: []const u8, texturePath: []const u8, replacementTexturePath: []const u8, id: []const u8, zon: ZonElement) *BaseItem {
	std.log.info("{s}", .{id});
	if(reverseIndices.contains(id)) {
		std.log.err("Registered item with id {s} twice!", .{id});
	}
	const newItem = &itemList[itemListSize];
	newItem.init(arena.allocator(), texturePath, replacementTexturePath, id, zon);
	reverseIndices.put(newItem.id, newItem) catch unreachable;
	itemListSize += 1;
	return newItem;
}

pub fn registerTool(assetFolder: []const u8, id: []const u8, zon: ZonElement) void {
	std.log.info("Registering tool type {s}", .{id});
	if(toolTypes.contains(id)) {
		std.log.err("Registered tool type with id {s} twice!", .{id});
	}
	var slotTypes = std.StringHashMap(SlotInfo).init(main.stackAllocator.allocator);
	defer slotTypes.deinit();
	slotTypes.put("none", .{.disabled = true}) catch unreachable;
	for(zon.getChild("slotTypes").toSlice()) |typ| {
		const name = typ.get([]const u8, "name", "huh?");
		var parameterSets = main.List(ParameterSet).init(arena.allocator());
		for(typ.getChild("parameterSets").toSlice()) |set| {
			parameterSets.append(.{
				.source = MaterialProperty.fromString(set.get([]const u8, "source", "not specified")),
				.destination = ToolProperty.fromString(set.get([]const u8, "destination", "not specified")),
				.factor = set.get(f32, "factor", 1),
				.additionConstant = set.get(f32, "additionConstant", 0),
				.functionType = FunctionType.fromString(set.get([]const u8, "functionType", "linear")),
			});
		}
		slotTypes.put(name, .{
			.parameters = parameterSets.toOwnedSlice(),
			.optional = typ.get(bool, "optional", false),
		}) catch unreachable;
	}
	var slotInfos: [25]SlotInfo = undefined;
	const slotTypesZon = zon.getChild("slots");
	for(0..25) |i| {
		const slotTypeId = slotTypesZon.getAtIndex([]const u8, i, "none");
		slotInfos[i] = slotTypes.get(slotTypeId) orelse blk: {
			std.log.err("Could not find slot type {s}. It must be specified in the same file.", .{slotTypeId});
			break :blk .{.disabled = true};
		};
	}
	var pixelSources: [16][16]u8 = undefined;
	{
		var split = std.mem.splitScalar(u8, id, ':');
		const mod = split.first();
		const tool = split.rest();
		const path = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/{s}/tools/{s}.png", .{assetFolder, mod, tool}) catch unreachable;
		defer main.stackAllocator.free(path);
		const image = main.graphics.Image.readFromFile(main.stackAllocator, path) catch |err| blk: {
			if(err != error.FileNotFound) {
				std.log.err("Error while reading tool image '{s}': {s}", .{path, @errorName(err)});
			}
			const replacementPath = std.fmt.allocPrint(main.stackAllocator.allocator, "assets/{s}/tools/{s}.png", .{mod, tool}) catch unreachable;
			defer main.stackAllocator.free(replacementPath);
			break :blk main.graphics.Image.readFromFile(main.stackAllocator, replacementPath) catch |err2| {
				std.log.err("Error while reading tool image. Tried '{s}' and '{s}': {s}", .{path, replacementPath, @errorName(err2)});
				break :blk main.graphics.Image.emptyImage;
			};
		};
		defer image.deinit(main.stackAllocator);
		if(image.width != 16 or image.height != 16) {
			std.log.err("Truncating image for {s} with incorrect dimensions. Should be 16×16.", .{id});
		}
		for(0..16) |x| {
			for(0..16) |y| {
				const color = if(image.width != 0 and image.height != 0) image.getRGB(@min(image.width - 1, x), image.height - 1 - @min(image.height - 1, y)) else main.graphics.Color{.r = 0, .g = 0, .b = 0, .a = 0};
				pixelSources[x][y] = blk: {
					if(color.a == 0) break :blk 255;
					const xPos = color.r/52;
					const yPos = color.b/52;
					break :blk xPos + 5*yPos;
				};
			}
		}
	}
	const idDupe = arena.allocator().dupe(u8, id);
	toolTypes.put(idDupe, .{
		.id = idDupe,
		.blockClass = std.meta.stringToEnum(main.blocks.BlockClass, zon.get([]const u8, "blockClass", "none")) orelse .air,
		.slotInfos = slotInfos,
		.pixelSources = pixelSources,
	}) catch unreachable;
}

fn parseRecipeItem(zon: ZonElement) !ItemStack {
	var id = zon.as([]const u8, "");
	id = std.mem.trim(u8, id, &std.ascii.whitespace);
	var result: ItemStack = .{.amount = 1};
	if(std.mem.indexOfScalar(u8, id, ' ')) |index| blk: {
		result.amount = std.fmt.parseInt(u16, id[0..index], 0) catch break :blk;
		id = id[index + 1..];
		id = std.mem.trim(u8, id, &std.ascii.whitespace);
	}
	result.item = .{.baseItem = getByID(id) orelse return error.ItemNotFound};
	return result;
}

fn parseRecipe(zon: ZonElement) !Recipe {
	const inputs = zon.getChild("inputs").toSlice();
	const output = try parseRecipeItem(zon.getChild("output"));
	const recipe = Recipe {
		.sourceItems = arena.allocator().alloc(*BaseItem, inputs.len),
		.sourceAmounts = arena.allocator().alloc(u16, inputs.len),
		.resultItem = output.item.?.baseItem,
		.resultAmount = output.amount,
	};
	errdefer {
		arena.allocator().free(recipe.sourceAmounts);
		arena.allocator().free(recipe.sourceItems);
	}
	for(inputs, 0..) |inputZon, i| {
		const input = try parseRecipeItem(inputZon);
		recipe.sourceItems[i] = input.item.?.baseItem;
		recipe.sourceAmounts[i] = input.amount;
	}
	return recipe;
}

pub fn registerRecipes(zon: ZonElement) void {
	for(zon.toSlice()) |recipeZon| {
		const recipe = parseRecipe(recipeZon) catch continue;
		recipeList.append(recipe);
	}
}

pub fn reset() void {
	toolTypes.clearAndFree();
	reverseIndices.clearAndFree();
	for(recipeList.items) |recipe| {
		if(recipe.cachedInventory) |inv| {
			inv.deinit(main.globalAllocator);
		}
	}
	recipeList.clearAndFree();
	itemListSize = 0;
	_ = arena.reset(.free_all);
}

pub fn deinit() void {
	toolTypes.clearAndFree();
	reverseIndices.clearAndFree();
	for(recipeList.items) |recipe| {
		if(recipe.cachedInventory) |inv| {
			inv.deinit(main.globalAllocator);
		}
	}
	recipeList.clearAndFree();
	arena.deinit();
	Inventory.Sync.ClientSide.deinit();
}

pub fn getByID(id: []const u8) ?*BaseItem {
	if(reverseIndices.get(id)) |result| {
		return result;
	} else {
		std.log.err("Couldn't find item {s}.", .{id});
		return null;
	}
}

pub fn getToolTypeByID(id: []const u8) ?*const ToolType {
	if(toolTypes.getPtr(id)) |result| {
		return result;
	} else {
		std.log.err("Couldn't find item {s}.", .{id});
		return null;
	}
}
