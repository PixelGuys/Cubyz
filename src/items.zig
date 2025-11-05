const std = @import("std");

const blocks = @import("blocks.zig");
const Block = blocks.Block;
const graphics = @import("graphics.zig");
const Color = graphics.Color;
const Tag = main.Tag;
const ZonElement = @import("zon.zig").ZonElement;
const main = @import("main");
const ListUnmanaged = main.ListUnmanaged;
const BinaryReader = main.utils.BinaryReader;
const BinaryWriter = main.utils.BinaryWriter;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const chunk = main.chunk;
const random = @import("random.zig");
const vec = @import("vec.zig");
const Mat4f = vec.Mat4f;
const Vec2f = vec.Vec2f;
const Vec2i = vec.Vec2i;
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;

const modifierList = @import("tool/modifiers/_list.zig");
const modifierRestrictionList = @import("tool/modifiers/restrictions/_list.zig");

pub const recipes_zig = @import("items/recipes.zig");

pub const Inventory = @import("Inventory.zig");

const Material = struct { // MARK: Material
	massDamage: f32 = undefined,
	hardnessDamage: f32 = undefined,
	durability: f32 = undefined,
	swingSpeed: f32 = undefined,

	textureRoughness: f32 = undefined,
	colorPalette: []Color = undefined,
	modifiers: []Modifier = undefined,

	pub fn init(self: *Material, allocator: NeverFailingAllocator, zon: ZonElement) void {
		self.massDamage = zon.get(?f32, "massDamage", null) orelse blk: {
			std.log.err("Couldn't find material attribute 'massDamage'", .{});
			break :blk 0;
		};
		self.hardnessDamage = zon.get(?f32, "hardnessDamage", null) orelse blk: {
			std.log.err("Couldn't find material attribute 'hardnessDamage'", .{});
			break :blk 0;
		};
		self.durability = zon.get(?f32, "durability", null) orelse blk: {
			std.log.err("Couldn't find material attribute 'durability'", .{});
			break :blk 0;
		};
		self.swingSpeed = zon.get(?f32, "swingSpeed", null) orelse blk: {
			std.log.err("Couldn't find material attribute 'swingSpeed'", .{});
			break :blk 0;
		};
		self.textureRoughness = @max(0, zon.get(f32, "textureRoughness", 1.0));
		const colors = zon.getChild("colors");
		self.colorPalette = allocator.alloc(Color, colors.toSlice().len);
		for(colors.toSlice(), self.colorPalette) |item, *color| {
			const colorInt: u32 = @intCast(item.as(i64, 0xff000000) & 0xffffffff);
			color.* = Color{
				.r = @intCast(colorInt >> 16 & 0xff),
				.g = @intCast(colorInt >> 8 & 0xff),
				.b = @intCast(colorInt >> 0 & 0xff),
				.a = @intCast(colorInt >> 24 & 0xff),
			};
		}
		const modifiersZon = zon.getChild("modifiers");
		self.modifiers = allocator.alloc(Modifier, modifiersZon.toSlice().len);
		for(modifiersZon.toSlice(), self.modifiers) |item, *modifier| {
			const id = item.get([]const u8, "id", "not specified");
			const vTable = modifiers.get(id) orelse blk: {
				std.log.err("Couldn't find modifier with id '{s}'. Replacing it with 'durable'", .{id});
				break :blk modifiers.get("durable") orelse unreachable;
			};
			modifier.* = .{
				.vTable = vTable,
				.data = vTable.loadData(item),
				.restriction = ModifierRestriction.loadFromZon(allocator, item.getChild("restriction")),
			};
		}
	}

	pub fn hashCode(self: Material) u32 {
		var hash: u32 = 0;
		hash = 101*%hash +% @as(u32, @bitCast(self.massDamage));
		hash = 101*%hash +% @as(u32, @bitCast(self.hardnessDamage));
		hash = 101*%hash +% @as(u32, @bitCast(self.durability));
		hash = 101*%hash +% @as(u32, @bitCast(self.swingSpeed));
		hash = 101*%hash +% @as(u32, @bitCast(self.textureRoughness));
		hash ^= hash >> 24;
		return hash;
	}

	fn getProperty(self: Material, prop: MaterialProperty) f32 {
		switch(prop) {
			inline else => |field| return @field(self, @tagName(field)),
		}
	}

	pub fn printTooltip(self: Material, outString: *main.List(u8)) void {
		if(self.modifiers.len == 0) {
			outString.appendSlice("§#808080Material\n");
		}
		for(self.modifiers) |modifier| {
			if(modifier.restriction.vTable == modifierRestrictions.get("always") orelse unreachable) {
				modifier.printTooltip(outString);
				outString.appendSlice("\n");
			} else {
				outString.appendSlice("§#808080if ");
				modifier.restriction.printTooltip(outString);
				outString.appendSlice("\n  ");
				modifier.printTooltip(outString);
				outString.appendSlice("\n");
			}
		}
	}
};

pub const ModifierRestriction = struct {
	vTable: *const VTable,
	data: *anyopaque,

	pub const VTable = struct {
		satisfied: *const fn(data: *anyopaque, tool: *const Tool, x: i32, y: i32) bool,
		loadFromZon: *const fn(allocator: NeverFailingAllocator, zon: ZonElement) *anyopaque,
		printTooltip: *const fn(data: *anyopaque, outString: *main.List(u8)) void,
	};

	pub fn satisfied(self: ModifierRestriction, tool: *const Tool, x: i32, y: i32) bool {
		return self.vTable.satisfied(self.data, tool, x, y);
	}

	pub fn loadFromZon(allocator: NeverFailingAllocator, zon: ZonElement) ModifierRestriction {
		const id = zon.get([]const u8, "id", "always");
		const vTable = modifierRestrictions.get(id) orelse blk: {
			std.log.err("Couldn't find modifier restriction with id '{s}'. Replacing it with 'always'", .{id});
			break :blk modifierRestrictions.get("always") orelse unreachable;
		};
		return .{
			.vTable = vTable,
			.data = vTable.loadFromZon(allocator, zon),
		};
	}

	pub fn printTooltip(self: ModifierRestriction, outString: *main.List(u8)) void {
		self.vTable.printTooltip(self.data, outString);
	}
};

const Modifier = struct {
	data: VTable.Data,
	restriction: ModifierRestriction,
	vTable: *const VTable,

	pub const VTable = struct {
		const Data = packed struct(u128) {pad: u128};
		combineModifiers: *const fn(data1: Data, data2: Data) ?Data,
		changeToolParameters: *const fn(tool: *Tool, data: Data) void,
		changeBlockDamage: *const fn(damage: f32, block: main.blocks.Block, data: Data) f32,
		printTooltip: *const fn(outString: *main.List(u8), data: Data) void,
		loadData: *const fn(zon: ZonElement) Data,
		priority: f32,
	};

	pub fn combineModifiers(a: Modifier, b: Modifier) ?Modifier {
		std.debug.assert(a.vTable == b.vTable);
		return .{
			.data = a.vTable.combineModifiers(a.data, b.data) orelse return null,
			.vTable = a.vTable,
			.restriction = undefined,
		};
	}

	pub fn changeToolParameters(self: Modifier, tool: *Tool) void {
		self.vTable.changeToolParameters(tool, self.data);
	}

	pub fn changeBlockDamage(self: Modifier, damage: f32, block: main.blocks.Block) f32 {
		return self.vTable.changeBlockDamage(damage, block, self.data);
	}

	pub fn printTooltip(self: Modifier, outString: *main.List(u8)) void {
		self.vTable.printTooltip(outString, self.data);
	}
};

const MaterialProperty = enum {
	massDamage,
	hardnessDamage,
	durability,
	swingSpeed,

	fn fromString(string: []const u8) ?MaterialProperty {
		return std.meta.stringToEnum(MaterialProperty, string) orelse {
			std.log.err("Couldn't find material property {s}.", .{string});
			return null;
		};
	}
};

pub const BaseItemIndex = enum(u16) { // MARK: BaseItemIndex
	_,

	pub fn fromId(_id: []const u8) ?BaseItemIndex {
		return reverseIndices.get(_id);
	}
	pub fn image(self: BaseItemIndex) graphics.Image {
		return itemList[@intFromEnum(self)].image;
	}
	pub fn texture(self: BaseItemIndex) ?graphics.Texture {
		return itemList[@intFromEnum(self)].texture;
	}
	pub fn id(self: BaseItemIndex) []const u8 {
		return itemList[@intFromEnum(self)].id;
	}
	pub fn name(self: BaseItemIndex) []const u8 {
		return itemList[@intFromEnum(self)].name;
	}
	pub fn tags(self: BaseItemIndex) []const Tag {
		return itemList[@intFromEnum(self)].tags;
	}
	pub fn stackSize(self: BaseItemIndex) u16 {
		return itemList[@intFromEnum(self)].stackSize;
	}
	pub fn material(self: BaseItemIndex) ?Material {
		return itemList[@intFromEnum(self)].material;
	}
	pub fn block(self: BaseItemIndex) ?u16 {
		return itemList[@intFromEnum(self)].block;
	}
	pub fn hasTag(self: BaseItemIndex, tag: Tag) bool {
		return itemList[@intFromEnum(self)].hasTag(tag);
	}
	pub fn hashCode(self: BaseItemIndex) u32 {
		return itemList[@intFromEnum(self)].hashCode();
	}
	pub fn getTexture(self: BaseItemIndex) graphics.Texture {
		return itemList[@intFromEnum(self)].getTexture();
	}
	pub fn getTooltip(self: BaseItemIndex) []const u8 {
		return itemList[@intFromEnum(self)].getTooltip();
	}
};

pub const BaseItem = struct { // MARK: BaseItem
	image: graphics.Image,
	texture: ?graphics.Texture, // TODO: Properly deinit
	id: []const u8,
	name: []const u8,
	tags: []const Tag,
	tooltip: []const u8,

	stackSize: u16,
	material: ?Material,
	block: ?u16,
	foodValue: f32, // TODO: Effects.

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
		self.tags = Tag.loadTagsFromZon(allocator, zon.getChild("tags"));
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

		var tooltip: main.List(u8) = .init(allocator);
		tooltip.appendSlice(self.name);
		tooltip.append('\n');
		if(self.material) |mat| {
			mat.printTooltip(&tooltip);
		}
		if(self.tags.len != 0) {
			tooltip.appendSlice("§#808080");
			for(self.tags, 0..) |tag, i| {
				if(i != 0) tooltip.append(' ');
				tooltip.append('.');
				tooltip.appendSlice(tag.getName());
			}
		}
		if(tooltip.items[tooltip.items.len - 1] == '\n') {
			_ = tooltip.swapRemove(tooltip.items.len - 1);
		}
		self.tooltip = tooltip.toOwnedSlice();
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
		return self.tooltip;
	}

	pub fn hasTag(self: *const BaseItem, tag: Tag) bool {
		for(self.tags) |other| {
			if(other == tag) return true;
		}
		return false;
	}
};

/// Generates the texture of a Tool using the material information.
const TextureGenerator = struct { // MARK: TextureGenerator
	fn generateHeightMap(itemGrid: *[16][16]?BaseItemIndex, seed: *u64) [17][17]f32 {
		var heightMap: [17][17]f32 = undefined;
		var x: u8 = 0;
		while(x < 17) : (x += 1) {
			var y: u8 = 0;
			while(y < 17) : (y += 1) {
				heightMap[x][y] = 0;
				// The heighmap basically consists of the amount of neighbors this pixel has.
				// Also check if there are different neighbors.
				const oneItem = itemGrid[if(x == 0) x else x - 1][if(y == 0) y else y - 1];
				var hasDifferentItems: bool = false;
				var dx: i32 = -1;
				while(dx <= 0) : (dx += 1) {
					if(x + dx < 0 or x + dx >= 16) continue;
					var dy: i32 = -1;
					while(dy <= 0) : (dy += 1) {
						if(y + dy < 0 or y + dy >= 16) continue;
						const otherItem = itemGrid[@intCast(x + dx)][@intCast(y + dy)];
						heightMap[x][y] = if(otherItem) |item| (if(item.material()) |material| 1 + (4*random.nextFloat(seed) - 2)*material.textureRoughness else 0) else 0;
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
				const source = tool.type.pixelSources()[x][y];
				const sourceOverlay = tool.type.pixelSourcesOverlay()[x][y];
				if(sourceOverlay < 25 and tool.craftingGrid[sourceOverlay] != null) {
					tool.materialGrid[x][y] = tool.craftingGrid[sourceOverlay];
				} else if(source < 25) {
					tool.materialGrid[x][y] = tool.craftingGrid[source];
				} else {
					tool.materialGrid[x][y] = null;
				}
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
					if(item.material()) |material| {
						// Calculate the lighting based on the nearest free space:
						const lightTL = heightMap[x][y] - heightMap[x + 1][y + 1];
						const lightTR = heightMap[x + 1][y] - heightMap[x][y + 1];
						var light = 2 - @as(i32, @intFromFloat(@round((lightTL*2 + lightTR)/6)));
						light = @max(@min(light, 4), 0);
						img.setRGB(x, 15 - y, material.colorPalette[@intCast(light)]);
					} else {
						img.setRGB(x, 15 - y, if((x ^ y) & 1 == 0) Color{.r = 255, .g = 0, .b = 255, .a = 255} else Color{.r = 0, .g = 0, .b = 0, .a = 255});
					}
				} else {
					img.setRGB(x, 15 - y, Color{.r = 0, .g = 0, .b = 0, .a = 0});
				}
			}
		}
	}
};

/// Determines the physical properties of a tool to calculate in-game parameters such as durability and speed.
const ToolPhysics = struct { // MARK: ToolPhysics
	/// Determines all the basic properties of the tool.
	pub fn evaluateTool(tool: *Tool) void {
		inline for(comptime std.meta.fieldNames(ToolProperty)) |name| {
			@field(tool, name) = 0;
		}
		var tempModifiers: main.List(Modifier) = .init(main.stackAllocator);
		defer tempModifiers.deinit();
		for(tool.type.properties()) |property| {
			var sum: f32 = 0;
			var weight: f32 = 0;
			for(0..25) |i| {
				const material = (tool.craftingGrid[i] orelse continue).material() orelse continue;
				sum += property.weights[i]*material.getProperty(property.source orelse break);
				weight += property.weights[i];
			}
			if(weight == 0) continue;
			switch(property.method) {
				.sum => {},
				.average => {
					sum /= weight;
				},
			}
			sum *= property.resultScale;
			tool.getProperty(property.destination orelse continue).* += sum;
		}
		if(tool.damage < 1) tool.damage = 1/(2 - tool.damage);
		if(tool.swingSpeed < 1) tool.swingSpeed = 1/(2 - tool.swingSpeed);
		for(0..25) |i| {
			const material = (tool.craftingGrid[i] orelse continue).material() orelse continue;
			outer: for(material.modifiers) |newMod| {
				if(!newMod.restriction.satisfied(tool, @intCast(i%5), @intCast(i/5))) continue;
				for(tempModifiers.items) |*oldMod| {
					if(oldMod.vTable == newMod.vTable) {
						oldMod.* = oldMod.combineModifiers(newMod) orelse continue;
						continue :outer;
					}
				}
				tempModifiers.append(newMod);
			}
		}
		std.sort.insertion(Modifier, tempModifiers.items, {}, struct {
			fn lessThan(_: void, lhs: Modifier, rhs: Modifier) bool {
				return lhs.vTable.priority < rhs.vTable.priority;
			}
		}.lessThan);
		tool.modifiers = main.globalAllocator.dupe(Modifier, tempModifiers.items);
		for(tempModifiers.items) |mod| {
			mod.changeToolParameters(tool);
		}

		tool.maxDurability = @round(tool.maxDurability);
		if(tool.maxDurability < 1) tool.maxDurability = 1;
		tool.durability = std.math.lossyCast(u32, tool.maxDurability);

		if(!checkConnectivity(tool)) {
			tool.maxDurability = 0;
			tool.durability = 1;
		}
	}

	fn checkConnectivity(tool: *Tool) bool {
		var gridCellsReached: [16][16]bool = @splat(@splat(false));
		var floodfillQueue = main.utils.CircularBufferQueue(Vec2i).init(main.stackAllocator, 16);
		defer floodfillQueue.deinit();
		outer: for(tool.materialGrid, 0..) |row, x| {
			for(row, 0..) |entry, y| {
				if(entry != null) {
					floodfillQueue.pushBack(.{@intCast(x), @intCast(y)});
					gridCellsReached[x][y] = true;
					break :outer;
				}
			}
		}
		while(floodfillQueue.popFront()) |pos| {
			for([4]Vec2i{.{-1, 0}, .{1, 0}, .{0, -1}, .{0, 1}}) |delta| {
				const newPos = pos + delta;
				if(newPos[0] < 0 or newPos[0] >= gridCellsReached.len) continue;
				if(newPos[1] < 0 or newPos[1] >= gridCellsReached.len) continue;
				const x: usize = @intCast(newPos[0]);
				const y: usize = @intCast(newPos[1]);
				if(gridCellsReached[x][y]) continue;
				if(tool.materialGrid[x][y] == null) continue;
				gridCellsReached[x][y] = true;
				floodfillQueue.pushBack(newPos);
			}
		}
		for(tool.materialGrid, 0..) |row, x| {
			for(row, 0..) |entry, y| {
				if(entry != null and !gridCellsReached[x][y]) {
					return false;
				}
			}
		}
		return true;
	}
};

const SlotInfo = packed struct { // MARK: SlotInfo
	disabled: bool = false,
	optional: bool = false,
};

const PropertyMatrix = struct { // MARK: PropertyMatrix
	source: ?MaterialProperty,
	destination: ?ToolProperty,
	weights: [25]f32,
	resultScale: f32,
	method: Method,

	const Method = enum {
		average,
		sum,

		fn fromString(string: []const u8) ?Method {
			return std.meta.stringToEnum(Method, string) orelse {
				std.log.err("Couldn't find property matrix method {s}.", .{string});
				return null;
			};
		}
	};
};

pub const ToolTypeIndex = enum(u16) {
	_,

	const ToolTypeIterator = struct {
		i: u16 = 0,

		pub fn next(self: *ToolTypeIterator) ?ToolTypeIndex {
			if(self.i >= toolTypeList.items.len) return null;
			defer self.i += 1;
			return @enumFromInt(self.i);
		}
	};

	pub fn iterator() ToolTypeIterator {
		return .{};
	}
	pub fn fromId(_id: []const u8) ?ToolTypeIndex {
		return toolTypeIdToIndex.get(_id);
	}
	pub fn id(self: ToolTypeIndex) []const u8 {
		return toolTypeList.items[@intFromEnum(self)].id;
	}
	pub fn blockTags(self: ToolTypeIndex) []const Tag {
		return toolTypeList.items[@intFromEnum(self)].blockTags;
	}
	pub fn properties(self: ToolTypeIndex) []const PropertyMatrix {
		return toolTypeList.items[@intFromEnum(self)].properties;
	}
	pub fn slotInfos(self: ToolTypeIndex) *const [25]SlotInfo {
		return &toolTypeList.items[@intFromEnum(self)].slotInfos;
	}
	pub fn pixelSources(self: ToolTypeIndex) *const [16][16]u8 {
		return &toolTypeList.items[@intFromEnum(self)].pixelSources;
	}
	pub fn pixelSourcesOverlay(self: ToolTypeIndex) *const [16][16]u8 {
		return &toolTypeList.items[@intFromEnum(self)].pixelSourcesOverlay;
	}
};

pub const ToolType = struct { // MARK: ToolType
	id: []const u8,
	blockTags: []main.Tag,
	properties: []PropertyMatrix,
	slotInfos: [25]SlotInfo,
	pixelSources: [16][16]u8,
	pixelSourcesOverlay: [16][16]u8,
};

const ToolProperty = enum {
	damage,
	maxDurability,
	swingSpeed,

	fn fromString(string: []const u8) ?ToolProperty {
		return std.meta.stringToEnum(ToolProperty, string) orelse {
			std.log.err("Couldn't find tool property {s}.", .{string});
			return null;
		};
	}
};

pub const Tool = struct { // MARK: Tool
	const craftingGridSize = 25;
	const CraftingGridMask = std.meta.Int(.unsigned, craftingGridSize);

	craftingGrid: [craftingGridSize]?BaseItemIndex,
	materialGrid: [16][16]?BaseItemIndex,
	modifiers: []Modifier,
	tooltip: main.List(u8),
	image: graphics.Image,
	texture: ?graphics.Texture,
	seed: u32,
	type: ToolTypeIndex,

	damage: f32,

	durability: u32,
	maxDurability: f32,

	/// swings per second
	swingSpeed: f32,

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
		// TODO: This is leaking textures!
		// if(self.texture) |texture| {
		// texture.deinit();
		// }
		self.image.deinit(main.globalAllocator);
		self.tooltip.deinit();
		main.globalAllocator.free(self.modifiers);
		main.globalAllocator.destroy(self);
	}

	pub fn clone(self: *const Tool) *Tool {
		const result = main.globalAllocator.create(Tool);
		result.* = .{
			.craftingGrid = self.craftingGrid,
			.materialGrid = self.materialGrid,
			.modifiers = main.globalAllocator.dupe(Modifier, self.modifiers),
			.tooltip = .init(main.globalAllocator),
			.image = graphics.Image.init(main.globalAllocator, self.image.width, self.image.height),
			.texture = null,
			.seed = self.seed,
			.type = self.type,
			.damage = self.damage,
			.durability = self.durability,
			.maxDurability = self.maxDurability,
			.swingSpeed = self.swingSpeed,
			.mass = self.mass,
			.handlePosition = self.handlePosition,
			.inertiaHandle = self.inertiaHandle,
			.centerOfMass = self.centerOfMass,
			.inertiaCenterOfMass = self.inertiaCenterOfMass,
		};
		@memcpy(result.image.imageData, self.image.imageData);
		return result;
	}

	pub fn initFromCraftingGrid(craftingGrid: [25]?BaseItemIndex, seed: u32, typ: ToolTypeIndex) *Tool {
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
		const self = initFromCraftingGrid(extractItemsFromZon(zon.getChild("grid")), zon.get(u32, "seed", 0), ToolTypeIndex.fromId(zon.get([]const u8, "type", "cubyz:pickaxe")) orelse blk: {
			std.log.err("Couldn't find tool with type {s}. Replacing it with cubyz:pickaxe", .{zon.get([]const u8, "type", "cubyz:pickaxe")});
			break :blk ToolTypeIndex.fromId("cubyz:pickaxe") orelse @panic("cubyz:pickaxe tool not found. Did you load the game with the correct assets?");
		});
		self.durability = zon.get(u32, "durability", std.math.lossyCast(u32, self.maxDurability));
		return self;
	}

	fn extractItemsFromZon(zonArray: ZonElement) [craftingGridSize]?BaseItemIndex {
		var items: [craftingGridSize]?BaseItemIndex = undefined;
		for(&items, 0..) |*item, i| {
			item.* = .fromId(zonArray.getAtIndex([]const u8, i, "null"));
			if(item.* != null and item.*.?.material() == null) item.* = null;
		}
		return items;
	}

	pub fn save(self: *const Tool, allocator: NeverFailingAllocator) ZonElement {
		const zonObject = ZonElement.initObject(allocator);
		const zonArray = ZonElement.initArray(allocator);
		for(self.craftingGrid) |nullableItem| {
			if(nullableItem) |item| {
				zonArray.array.append(.{.string = item.id()});
			} else {
				zonArray.array.append(.null);
			}
		}
		zonObject.put("grid", zonArray);
		zonObject.put("durability", self.durability);
		zonObject.put("seed", self.seed);
		zonObject.put("type", self.type.id());
		return zonObject;
	}

	pub fn fromBytes(reader: *BinaryReader) !*Tool {
		const durability = try reader.readInt(u32);
		const seed = try reader.readInt(u32);
		const typ = try reader.readEnum(ToolTypeIndex);

		var craftingGridMask = try reader.readInt(CraftingGridMask);
		var craftingGrid: [craftingGridSize]?BaseItemIndex = @splat(null);

		while(craftingGridMask != 0) {
			const i = @ctz(craftingGridMask);
			craftingGridMask &= ~(@as(CraftingGridMask, 1) << @intCast(i));
			craftingGrid[i] = try reader.readEnum(BaseItemIndex);
		}
		const self = initFromCraftingGrid(craftingGrid, seed, typ);

		self.durability = durability;
		return self;
	}

	pub fn toBytes(self: Tool, writer: *BinaryWriter) void {
		writer.writeInt(u32, self.durability);
		writer.writeInt(u32, self.seed);
		writer.writeEnum(ToolTypeIndex, self.type);

		var craftingGridMask: CraftingGridMask = 0;
		for(0..craftingGridSize) |i| {
			if(self.craftingGrid[i] != null) {
				craftingGridMask |= @as(CraftingGridMask, 1) << @intCast(i);
			}
		}
		writer.writeInt(CraftingGridMask, craftingGridMask);

		for(0..craftingGridSize) |i| {
			if(self.craftingGrid[i]) |baseItem| {
				writer.writeEnum(BaseItemIndex, baseItem);
			}
		}
	}

	pub fn hashCode(self: Tool) u32 {
		var hash: u32 = 0;
		for(self.craftingGrid) |nullItem| {
			if(nullItem) |item| {
				hash = 33*%hash +% item.material().?.hashCode();
			}
		}
		return hash;
	}

	pub fn getItemAt(self: *const Tool, x: i32, y: i32) ?BaseItemIndex {
		if(x < 0 or x >= 5) return null;
		if(y < 0 or y >= 5) return null;
		return self.craftingGrid[@intCast(x + y*5)];
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
			\\{d:.2} swings/s
			\\Damage: {d:.2}
			\\Durability: {}/{}
		, .{
			self.type.id(),
			self.swingSpeed,
			self.damage,
			self.durability,
			std.math.lossyCast(u32, self.maxDurability),
		}) catch unreachable;
		if(self.modifiers.len != 0) {
			self.tooltip.appendSlice("\nModifiers:\n");
			for(self.modifiers) |modifier| {
				modifier.printTooltip(&self.tooltip);
				self.tooltip.appendSlice("§\n");
			}
			_ = self.tooltip.pop();
		}
		return self.tooltip.items;
	}

	pub fn isEffectiveOn(self: *Tool, block: main.blocks.Block) bool {
		for(block.blockTags()) |blockTag| {
			for(self.type.blockTags()) |toolTag| {
				if(toolTag == blockTag) return true;
			}
		}
		return false;
	}

	pub fn getBlockDamage(self: *Tool, block: main.blocks.Block) f32 {
		var damage = self.damage;
		for(self.modifiers) |modifier| {
			damage = modifier.changeBlockDamage(damage, block);
		}
		if(self.isEffectiveOn(block)) {
			return damage;
		}
		return main.game.Player.defaultBlockDamage;
	}

	pub fn onUseReturnBroken(self: *Tool) bool {
		self.durability -|= 1;
		return self.durability == 0;
	}
};

const ItemType = enum(u7) {
	baseItem,
	tool,
};

pub const Item = union(ItemType) { // MARK: Item
	baseItem: BaseItemIndex,
	tool: *Tool,

	pub fn init(zon: ZonElement) !Item {
		if(BaseItemIndex.fromId(zon.get([]const u8, "item", "null"))) |baseItem| {
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
			},
		}
	}

	pub fn stackSize(self: Item) u16 {
		switch(self) {
			.baseItem => |_baseItem| {
				return _baseItem.stackSize();
			},
			.tool => {
				return 1;
			},
		}
	}

	pub fn insertIntoZon(self: Item, allocator: NeverFailingAllocator, zonObject: ZonElement) void {
		switch(self) {
			.baseItem => |_baseItem| {
				zonObject.put("item", _baseItem.id());
			},
			.tool => |_tool| {
				zonObject.put("tool", _tool.save(allocator));
			},
		}
	}

	pub fn fromBytes(reader: *BinaryReader) !Item {
		const typ = try reader.readEnum(ItemType);
		switch(typ) {
			.baseItem => {
				return .{.baseItem = try reader.readEnum(BaseItemIndex)};
			},
			.tool => {
				return .{.tool = try Tool.fromBytes(reader)};
			},
		}
	}

	pub fn toBytes(self: Item, writer: *BinaryWriter) void {
		writer.writeEnum(ItemType, self);
		switch(self) {
			.baseItem => writer.writeEnum(BaseItemIndex, self.baseItem),
			.tool => |tool| tool.toBytes(writer),
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

	pub fn id(self: Item) []const u8 {
		switch(self) {
			.tool => |tool| {
				return tool.type.id();
			},
			.baseItem => |item| {
				return item.id();
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
				return _baseItem.image();
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

	pub fn storeToZon(self: *const ItemStack, allocator: NeverFailingAllocator, zonObject: ZonElement) void {
		if(self.item) |item| {
			item.insertIntoZon(allocator, zonObject);
			zonObject.put("amount", self.amount);
		}
	}

	pub fn fromBytes(reader: *BinaryReader) !ItemStack {
		const amount = try reader.readVarInt(u16);
		if(amount == 0) {
			return .{};
		}
		const item = try Item.fromBytes(reader);
		return .{
			.item = item,
			.amount = amount,
		};
	}

	pub fn toBytes(self: *const ItemStack, writer: *BinaryWriter) void {
		if(self.item) |item| {
			writer.writeVarInt(u16, self.amount);
			item.toBytes(writer);
		} else {
			writer.writeVarInt(u16, 0);
		}
	}
};

pub const Recipe = struct { // MARK: Recipe
	sourceItems: []BaseItemIndex,
	sourceAmounts: []u16,
	resultItem: BaseItemIndex,
	resultAmount: u16,
	cachedInventory: ?Inventory = null,
};

var toolTypeList: ListUnmanaged(ToolType) = .{};
var toolTypeIdToIndex: std.StringHashMapUnmanaged(ToolTypeIndex) = .{};

var reverseIndices: std.StringHashMapUnmanaged(BaseItemIndex) = .{};
var modifiers: std.StringHashMapUnmanaged(*const Modifier.VTable) = .{};
var modifierRestrictions: std.StringHashMapUnmanaged(*const ModifierRestriction.VTable) = .{};
pub var itemList: [65536]BaseItem = undefined;
pub var itemListSize: u16 = 0;

var recipeList: main.List(Recipe) = undefined;

pub fn hasRegistered(id: []const u8) bool {
	return reverseIndices.contains(id);
}

pub fn hasRegisteredTool(id: []const u8) bool {
	return toolTypeIdToIndex.contains(id);
}

pub fn iterator() std.StringHashMap(BaseItemIndex).ValueIterator {
	return reverseIndices.valueIterator();
}

pub fn recipes() []Recipe {
	return recipeList.items;
}

pub fn globalInit() void {
	toolTypeIdToIndex = .{};

	recipeList = .init(main.worldArena);
	itemListSize = 0;
	inline for(@typeInfo(modifierList).@"struct".decls) |decl| {
		const ModifierStruct = @field(modifierList, decl.name);
		modifiers.put(main.globalArena.allocator, decl.name, &.{
			.changeToolParameters = @ptrCast(&ModifierStruct.changeToolParameters),
			.changeBlockDamage = @ptrCast(&ModifierStruct.changeBlockDamage),
			.combineModifiers = @ptrCast(&ModifierStruct.combineModifiers),
			.printTooltip = @ptrCast(&ModifierStruct.printTooltip),
			.loadData = @ptrCast(&ModifierStruct.loadData),
			.priority = ModifierStruct.priority,
		}) catch unreachable;
	}
	inline for(@typeInfo(modifierRestrictionList).@"struct".decls) |decl| {
		const ModifierRestrictionStruct = @field(modifierRestrictionList, decl.name);
		modifierRestrictions.put(main.globalArena.allocator, decl.name, &.{
			.satisfied = comptime main.utils.castFunctionSelfToAnyopaque(ModifierRestrictionStruct.satisfied),
			.loadFromZon = comptime main.utils.castFunctionReturnToAnyopaque(ModifierRestrictionStruct.loadFromZon),
			.printTooltip = comptime main.utils.castFunctionSelfToAnyopaque(ModifierRestrictionStruct.printTooltip),
		}) catch unreachable;
	}
	Inventory.Sync.ClientSide.init();
}

pub fn register(_: []const u8, texturePath: []const u8, replacementTexturePath: []const u8, id: []const u8, zon: ZonElement) *BaseItem {
	const newItem = &itemList[itemListSize];
	defer itemListSize += 1;

	newItem.init(main.worldArena, texturePath, replacementTexturePath, id, zon);
	reverseIndices.put(main.worldArena.allocator, newItem.id, @enumFromInt(itemListSize)) catch unreachable;

	std.log.debug("Registered item: {d: >5} '{s}'", .{itemListSize, id});
	return newItem;
}

fn loadPixelSources(assetFolder: []const u8, id: []const u8, layerPostfix: []const u8, pixelSources: *[16][16]u8) void {
	var split = std.mem.splitScalar(u8, id, ':');
	const mod = split.first();
	const tool = split.rest();
	const path = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/{s}/tools/{s}{s}.png", .{assetFolder, mod, tool, layerPostfix}) catch unreachable;
	defer main.stackAllocator.free(path);
	const image = main.graphics.Image.readFromFile(main.stackAllocator, path) catch |err| blk: {
		if(err != error.FileNotFound) {
			std.log.err("Error while reading tool image '{s}': {s}", .{path, @errorName(err)});
		}
		const replacementPath = std.fmt.allocPrint(main.stackAllocator.allocator, "assets/{s}/tools/{s}{s}.png", .{mod, tool, layerPostfix}) catch unreachable;
		defer main.stackAllocator.free(replacementPath);
		break :blk main.graphics.Image.readFromFile(main.stackAllocator, replacementPath) catch |err2| {
			if(layerPostfix.len == 0 or err2 != error.FileNotFound)
				std.log.err("Error while reading tool image. Tried '{s}' and '{s}': {s}", .{path, replacementPath, @errorName(err2)});
			break :blk main.graphics.Image.emptyImage;
		};
	};
	defer image.deinit(main.stackAllocator);
	if((image.width != 16 or image.height != 16) and image.imageData.ptr != main.graphics.Image.emptyImage.imageData.ptr) {
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

pub fn registerTool(assetFolder: []const u8, id: []const u8, zon: ZonElement) void {
	var slotInfos: [25]SlotInfo = @splat(.{});
	for(zon.getChild("disabled").toSlice(), 0..) |zonDisabled, i| {
		if(i >= 25) {
			std.log.err("disabled array of {s} has too many entries", .{id});
			break;
		}
		slotInfos[i].disabled = zonDisabled.as(usize, 0) != 0;
	}
	for(zon.getChild("optional").toSlice(), 0..) |zonDisabled, i| {
		if(i >= 25) {
			std.log.err("disabled array of {s} has too many entries", .{id});
			break;
		}
		slotInfos[i].optional = zonDisabled.as(usize, 0) != 0;
	}
	var parameterMatrices: main.List(PropertyMatrix) = .init(main.worldArena);
	for(zon.getChild("parameters").toSlice()) |paramZon| {
		const val = parameterMatrices.addOne();
		val.source = MaterialProperty.fromString(paramZon.get([]const u8, "source", "not specified"));
		val.destination = ToolProperty.fromString(paramZon.get([]const u8, "destination", "not specified"));
		val.resultScale = paramZon.get(f32, "factor", 1.0);
		val.method = PropertyMatrix.Method.fromString(paramZon.get([]const u8, "method", "not specified")) orelse .sum;
		const matrixZon = paramZon.getChild("matrix");
		var total_weight: f32 = 0.0;
		for(0..25) |i| {
			val.weights[i] = matrixZon.getAtIndex(f32, i, 0.0);
		}
		for(0..25) |i| {
			total_weight += val.weights[i];
		}
		for(0..25) |i| {
			if(val.weights[i] != 0x0) {
				val.weights[i] /= total_weight;
			}
		}
	}
	var pixelSources: [16][16]u8 = undefined;
	loadPixelSources(assetFolder, id, "", &pixelSources);
	var pixelSourcesOverlay: [16][16]u8 = undefined;
	loadPixelSources(assetFolder, id, "_overlay", &pixelSourcesOverlay);

	const idDupe = main.worldArena.dupe(u8, id);
	toolTypeList.append(main.worldArena, .{
		.id = idDupe,
		.blockTags = Tag.loadTagsFromZon(main.worldArena, zon.getChild("blockTags")),
		.slotInfos = slotInfos,
		.properties = parameterMatrices.toOwnedSlice(),
		.pixelSources = pixelSources,
		.pixelSourcesOverlay = pixelSourcesOverlay,
	});
	toolTypeIdToIndex.put(main.worldArena.allocator, idDupe, @enumFromInt(toolTypeList.items.len - 1)) catch unreachable;

	std.log.debug("Registered tool: '{s}'", .{id});
}

fn parseRecipeItem(zon: ZonElement) !ItemStack {
	var id = zon.as([]const u8, "");
	id = std.mem.trim(u8, id, &std.ascii.whitespace);
	var result: ItemStack = .{.amount = 1};
	if(std.mem.indexOfScalar(u8, id, ' ')) |index| blk: {
		result.amount = std.fmt.parseInt(u16, id[0..index], 0) catch break :blk;
		id = id[index + 1 ..];
		id = std.mem.trim(u8, id, &std.ascii.whitespace);
	}
	result.item = .{.baseItem = BaseItemIndex.fromId(id) orelse return error.ItemNotFound};
	return result;
}

fn parseRecipe(zon: ZonElement) !Recipe {
	const inputs = zon.getChild("inputs").toSlice();
	const output = try parseRecipeItem(zon.getChild("output"));
	const recipe = Recipe{
		.sourceItems = main.worldArena.alloc(BaseItemIndex, inputs.len),
		.sourceAmounts = main.worldArena.alloc(u16, inputs.len),
		.resultItem = output.item.?.baseItem,
		.resultAmount = output.amount,
	};
	for(inputs, 0..) |inputZon, i| {
		const input = try parseRecipeItem(inputZon);
		recipe.sourceItems[i] = input.item.?.baseItem;
		recipe.sourceAmounts[i] = input.amount;
	}
	return recipe;
}

pub fn registerRecipes(zon: ZonElement) void {
	for(zon.toSlice()) |recipeZon| {
		recipes_zig.parseRecipe(main.globalAllocator, recipeZon, &recipeList) catch |err| {
			const recipeString = recipeZon.toString(main.stackAllocator);
			defer main.stackAllocator.free(recipeString);
			std.log.err("Skipping recipe with error {s}:\n{s}", .{@errorName(err), recipeString});
			continue;
		};
	}
}

pub fn clearRecipeCachedInventories() void {
	for(recipeList.items) |recipe| {
		main.globalAllocator.free(recipe.sourceItems);
		main.globalAllocator.free(recipe.sourceAmounts);
		if(recipe.cachedInventory) |inv| {
			inv.deinit(main.globalAllocator);
		}
	}
}

pub fn reset() void {
	toolTypeList = .{};
	toolTypeIdToIndex = .{};
	reverseIndices = .{};
	recipeList.clearAndFree();
	itemListSize = 0;
}

pub fn deinit() void {
	Inventory.Sync.ClientSide.deinit();
}
