const std = @import("std");

const main = @import("root");
const ZonElement = @import("zon.zig").ZonElement;
const Neighbor = @import("chunk.zig").Neighbor;
const graphics = @import("graphics.zig");
const Shader = graphics.Shader;
const SSBO = graphics.SSBO;
const Image = graphics.Image;
const Color = graphics.Color;
const TextureArray = graphics.TextureArray;
const items = @import("items.zig");
const models = @import("models.zig");
const rotation = @import("rotation.zig");
const RotationMode = rotation.RotationMode;

pub const BlockClass = enum(u8) {
	wood,
	stone,
	sand,
	unbreakable,
	leaf,
	fluid,
	air,
};

var arena = main.utils.NeverFailingArenaAllocator.init(main.globalAllocator);
const allocator = arena.allocator();

pub const maxBlockCount: usize = 65536; // 16 bit limit

pub const BlockDrop = struct {
	items: []const items.ItemStack,
	chance: f32,
};

/// Ores can be found underground in veins.
/// TODO: Add support for non-stone ores.
pub const Ore = struct {
	/// average size of a vein in blocks
	size: f32,
	/// average density of a vein
	density: f32,
	/// average veins per chunk
	veins: f32,
	/// maximum height this ore can be generated
	maxHeight: i32,

	blockType: u16,

	sources: []u16,

	pub fn canCreateVeinInBlock(self: Ore, blockType: u16) bool {
		for(self.sources) |source| {
			if(blockType == source) return true;
		}
		return false;
	}
};

var _transparent: [maxBlockCount]bool = undefined;
var _collide: [maxBlockCount]bool = undefined;
var _id: [maxBlockCount][]u8 = undefined;
/// Time in seconds to break this block by hand.
var _hardness: [maxBlockCount]f32 = undefined;
/// Minimum pickaxe/axe/shovel power required.
var _breakingPower: [maxBlockCount]f32 = undefined;
var _solid: [maxBlockCount]bool = undefined;
var _selectable: [maxBlockCount]bool = undefined;
var _blockDrops: [maxBlockCount][]BlockDrop = undefined;
/// Meaning undegradable parts of trees or other structures can grow through this block.
var _degradable: [maxBlockCount]bool = undefined;
var _viewThrough: [maxBlockCount]bool = undefined;
var _alwaysViewThrough: [maxBlockCount]bool = undefined;
var _hasBackFace: [maxBlockCount]bool = undefined;
var _blockClass: [maxBlockCount]BlockClass = undefined;
var _light: [maxBlockCount]u32 = undefined;
/// How much light this block absorbs if it is transparent
var _absorption: [maxBlockCount]u32 = undefined;
/// GUI that is opened on click.
var _gui: [maxBlockCount][]u8 = undefined;
var _mode: [maxBlockCount]*RotationMode = undefined;
var _lodReplacement: [maxBlockCount]u16 = undefined;
var _opaqueVariant: [maxBlockCount]u16 = undefined;

var reverseIndices = std.StringHashMap(u16).init(allocator.allocator);

var size: u32 = 0;

pub var ores: main.List(Ore) = .init(allocator);

var unfinishedOreSourceBlockIds: main.List([][]const u8) = undefined;

pub fn init() void {
	unfinishedOreSourceBlockIds = .init(main.globalAllocator);
}

pub fn deinit() void {
	unfinishedOreSourceBlockIds.deinit();
}

pub fn register(_: []const u8, id: []const u8, zon: ZonElement) u16 {
	if(reverseIndices.contains(id)) {
		std.log.warn("Registered block with id {s} twice!", .{id});
	}
	_id[size] = allocator.dupe(u8, id);
	reverseIndices.put(_id[size], @intCast(size)) catch unreachable;

	_mode[size] = rotation.getByID(zon.get([]const u8, "rotation", "no_rotation"));
	_breakingPower[size] = zon.get(f32, "breakingPower", 0);
	_hardness[size] = zon.get(f32, "hardness", 1);

	_blockClass[size] = std.meta.stringToEnum(BlockClass, zon.get([]const u8, "class", "stone")) orelse .stone;
	_light[size] = zon.get(u32, "emittedLight", 0);
	_absorption[size] = zon.get(u32, "absorbedLight", 0xffffff);
	_degradable[size] = zon.get(bool, "degradable", false);
	_selectable[size] = zon.get(bool, "selectable", true);
	_solid[size] = zon.get(bool, "solid", true);
	_gui[size] = allocator.dupe(u8, zon.get([]const u8, "gui", ""));
	_transparent[size] = zon.get(bool, "transparent", false);
	_collide[size] = zon.get(bool, "collide", true);
	_alwaysViewThrough[size] = zon.get(bool, "alwaysViewThrough", false);
	_viewThrough[size] = zon.get(bool, "viewThrough", false) or _transparent[size] or _alwaysViewThrough[size];
	_hasBackFace[size] = zon.get(bool, "hasBackFace", false);

	const oreProperties = zon.getChild("ore");
	if (oreProperties != .null) {
		// Extract the ids:
		const sourceBlocks = oreProperties.getChild("sources").toSlice();
		const oreIds = main.globalAllocator.alloc([]const u8, sourceBlocks.len);
		for(sourceBlocks, oreIds) |source, *oreId| {
			oreId.* = main.globalAllocator.dupe(u8, source.as([]const u8, ""));
		}
		unfinishedOreSourceBlockIds.append(oreIds);
		ores.append(Ore {
			.veins = oreProperties.get(f32, "veins", 0),
			.size = oreProperties.get(f32, "size", 0),
			.maxHeight = oreProperties.get(i32, "height", 0),
			.density = oreProperties.get(f32, "density", 0.5),
			.blockType = @intCast(size),
			.sources = &.{},
		});
	}

	size += 1;
	return @intCast(size - 1);
}

fn registerBlockDrop(typ: u16, zon: ZonElement) void {
	const drops = zon.getChild("drops").toSlice();
	_blockDrops[typ] = allocator.alloc(BlockDrop, drops.len);

	for(drops, 0..) |blockDrop, i| {
		_blockDrops[typ][i].chance = blockDrop.get(f32, "chance", 1);
		const itemZons = blockDrop.getChild("items").toSlice();
		var resultItems = main.List(items.ItemStack).initCapacity(main.stackAllocator, itemZons.len);
		defer resultItems.deinit();

		for(itemZons) |itemZon| {
			var string = itemZon.as([]const u8, "auto");
			string = std.mem.trim(u8, string, " ");
			var iterator = std.mem.splitScalar(u8, string, ' ');
			var name = iterator.first();
			var amount: u16 = 1;
			while(iterator.next()) |next| {
				if(next.len == 0) continue; // skip multiple spaces.
				amount = std.fmt.parseInt(u16, name, 0) catch 1;
				name = next;
				break;
			}

			if(std.mem.eql(u8, name, "auto")) {
				name = _id[typ];
			}

			const item = items.getByID(name) orelse continue;
			resultItems.append(.{.item = .{.baseItem = item}, .amount = amount});
		}

		_blockDrops[typ][i].items = allocator.dupe(items.ItemStack, resultItems.items);
	}
}

fn registerLodReplacement(typ: u16, zon: ZonElement) void {
	if(zon.get(?[]const u8, "lodReplacement", null)) |replacement| {
		_lodReplacement[typ] = getTypeById(replacement);
	} else {
		_lodReplacement[typ] = typ;
	}
}

fn registerOpaqueVariant(typ: u16, zon: ZonElement) void {
	if(zon.get(?[]const u8, "opaqueVariant", null)) |replacement| {
		_opaqueVariant[typ] = getTypeById(replacement);
	} else {
		_opaqueVariant[typ] = typ;
	}
}

pub fn finishBlocks(zonElements: std.StringHashMap(ZonElement)) void {
	var i: u16 = 0;
	while(i < size) : (i += 1) {
		registerBlockDrop(i, zonElements.get(_id[i]) orelse continue);
	}
	i = 0;
	while(i < size) : (i += 1) {
		registerLodReplacement(i, zonElements.get(_id[i]) orelse continue);
		registerOpaqueVariant(i, zonElements.get(_id[i]) orelse continue);
	}
	for(ores.items, unfinishedOreSourceBlockIds.items) |*ore, oreIds| {
		ore.sources = allocator.alloc(u16, oreIds.len);
		for(ore.sources, oreIds) |*source, id| {
			source.* = getTypeById(id);
			main.globalAllocator.free(id);
		}
		main.globalAllocator.free(oreIds);
	}
	unfinishedOreSourceBlockIds.clearRetainingCapacity();
}

pub fn reset() void {
	size = 0;
	ores.clearAndFree();
	meshes.reset();
	_ = arena.reset(.free_all);
	reverseIndices = .init(arena.allocator().allocator);
	std.debug.assert(unfinishedOreSourceBlockIds.items.len == 0);
}

pub fn getTypeById(id: []const u8) u16 {
	if(reverseIndices.get(id)) |result| {
		return result;
	} else {
		std.log.warn("Couldn't find block {s}. Replacing it with air...", .{id});
		return 0;
	}
}

pub fn getBlockById(id: []const u8) Block {
	if(reverseIndices.get(id)) |resultType| {
		var result: Block = .{.typ = resultType, .data = 0};
		result.data = result.mode().naturalStandard;
		return result;
	} else {
		std.log.warn("Couldn't find block {s}. Replacing it with air...", .{id});
		return .{.typ = 0, .data = 0};
	}
}

pub fn hasRegistered(id: []const u8) bool {
	return reverseIndices.contains(id);
}

pub const Block = packed struct { // MARK: Block
	typ: u16,
	data: u16,
	pub fn toInt(self: Block) u32 {
		return @as(u32, self.typ) | @as(u32, self.data)<<16;
	}
	pub fn fromInt(self: u32) Block {
		return Block{.typ=@truncate(self), .data=@intCast(self>>16)};
	}

	pub inline fn transparent(self: Block) bool {
		return _transparent[self.typ];
	}

	pub inline fn collide(self: Block) bool {
		return _collide[self.typ];
	}

	pub inline fn id(self: Block) []u8 {
		return _id[self.typ];
	}

	/// Time in seconds to break this block by hand.
	pub inline fn hardness(self: Block) f32 {
		return _hardness[self.typ];
	}

	/// Minimum pickaxe/axe/shovel power required.
	pub inline fn breakingPower(self: Block) f32 {
		return _breakingPower[self.typ];
	}

	pub inline fn solid(self: Block) bool {
		return _solid[self.typ];
	}

	pub inline fn selectable(self: Block) bool {
		return _selectable[self.typ];
	}

	pub inline fn blockDrops(self: Block) []BlockDrop {
		return _blockDrops[self.typ];
	}

	/// Meaning undegradable parts of trees or other structures can grow through this block.
	pub inline fn degradable(self: Block) bool {
		return _degradable[self.typ];
	}

	pub inline fn viewThrough(self: Block) bool {
		return _viewThrough[self.typ];
	}

	/// shows backfaces even when next to the same block type
	pub inline fn alwaysViewThrough(self: Block) bool {
		return _alwaysViewThrough[self.typ];
	}

	pub inline fn hasBackFace(self: Block) bool {
		return _hasBackFace[self.typ];
	}

	pub inline fn blockClass(self: Block) BlockClass {
		return _blockClass[self.typ];
	}

	pub inline fn light(self: Block) u32 {
		return _light[self.typ];
	}

	/// How much light this block absorbs if it is transparent.
	pub inline fn absorption(self: Block) u32 {
		return _absorption[self.typ];
	}
	
	/// GUI that is opened on click.
	pub inline fn gui(self: Block) []u8 {
		return _gui[self.typ];
	}
	
	pub inline fn mode(self: Block) *RotationMode {
		return _mode[self.typ];
	}
	
	pub inline fn lodReplacement(self: Block) u16 {
		return _lodReplacement[self.typ];
	}
	
	pub inline fn opaqueVariant(self: Block) u16 {
		return _opaqueVariant[self.typ];
	}

	pub fn canBeChangedInto(self: Block, newBlock: Block, item: main.items.ItemStack) main.rotation.RotationMode.CanBeChangedInto {
		return newBlock.mode().canBeChangedInto(self, newBlock, item);
	}
};


pub const meshes = struct { // MARK: meshes
	const AnimationData = extern struct {
		startFrame: u32,
		frames: u32,
		time: u32,
	};

	const TextureData = extern struct {
		textureIndices: [6]u16,
	};
	const FogData = extern struct {
		fogDensity: f32,
		fogColor: u32,
	};
	var size: u32 = 0;
	var _modelIndex: [maxBlockCount]u16 = undefined;
	var textureData: [maxBlockCount]TextureData = undefined;
	/// Stores the number of textures after each block was added. Used to clean additional textures when the world is switched.
	var maxTextureCount: [maxBlockCount]u32 = undefined;
	/// Number of loaded meshes. Used to determine if an update is needed.
	var loadedMeshes: u32 = 0;

	var textureIDs: main.List([]const u8) = undefined;
	var animation: main.List(AnimationData) = undefined;
	var blockTextures: main.List(Image) = undefined;
	var emissionTextures: main.List(Image) = undefined;
	var reflectivityTextures: main.List(Image) = undefined;
	var absorptionTextures: main.List(Image) = undefined;
	var textureFogData: main.List(FogData) = undefined;

	var arenaForWorld: main.utils.NeverFailingArenaAllocator = undefined;

	const sideNames = blk: {
		var names: [6][]const u8 = undefined;
		names[Neighbor.dirDown.toInt()] = "texture_bottom";
		names[Neighbor.dirUp.toInt()] = "texture_top";
		names[Neighbor.dirPosX.toInt()] = "texture_right";
		names[Neighbor.dirNegX.toInt()] = "texture_left";
		names[Neighbor.dirPosY.toInt()] = "texture_front";
		names[Neighbor.dirNegY.toInt()] = "texture_back";
		break :blk names;
	};

	var animationSSBO: ?SSBO = null;
	var animatedTextureSSBO: ?SSBO = null;
	var fogSSBO: ?SSBO = null;

	var animationShader: Shader = undefined;
	var animationUniforms: struct {
		time: c_int,
		size: c_int,
	} = undefined;

	pub var blockTextureArray: TextureArray = undefined;
	pub var emissionTextureArray: TextureArray = undefined;
	pub var reflectivityAndAbsorptionTextureArray: TextureArray = undefined;

	const black: Color = Color{.r=0, .g=0, .b=0, .a=255};
	const magenta: Color = Color{.r=255, .g=0, .b=255, .a=255};
	var undefinedTexture = [_]Color {magenta, black, black, magenta};
	const undefinedImage = Image{.width = 2, .height = 2, .imageData = undefinedTexture[0..]};
	var emptyTexture = [_]Color {black};
	const emptyImage = Image{.width = 1, .height = 1, .imageData = emptyTexture[0..]};

	pub fn init() void {
		animationShader = Shader.initComputeAndGetUniforms("assets/cubyz/shaders/animation_pre_processing.glsl", "", &animationUniforms);
		blockTextureArray = .init();
		emissionTextureArray = .init();
		reflectivityAndAbsorptionTextureArray = .init();
		textureIDs = .init(main.globalAllocator);
		animation = .init(main.globalAllocator);
		blockTextures = .init(main.globalAllocator);
		emissionTextures = .init(main.globalAllocator);
		reflectivityTextures = .init(main.globalAllocator);
		absorptionTextures = .init(main.globalAllocator);
		textureFogData = .init(main.globalAllocator);
		arenaForWorld = .init(main.globalAllocator);
	}

	pub fn deinit() void {
		if(animationSSBO) |ssbo| {
			ssbo.deinit();
		}
		if(animatedTextureSSBO) |ssbo| {
			ssbo.deinit();
		}
		if(fogSSBO) |ssbo| {
			ssbo.deinit();
		}
		animationShader.deinit();
		blockTextureArray.deinit();
		emissionTextureArray.deinit();
		reflectivityAndAbsorptionTextureArray.deinit();
		textureIDs.deinit();
		animation.deinit();
		blockTextures.deinit();
		emissionTextures.deinit();
		reflectivityTextures.deinit();
		absorptionTextures.deinit();
		textureFogData.deinit();
		arenaForWorld.deinit();
	}

	pub fn reset() void {
		meshes.size = 0;
		loadedMeshes = 0;
		textureIDs.clearRetainingCapacity();
		animation.clearRetainingCapacity();
		blockTextures.clearRetainingCapacity();
		emissionTextures.clearRetainingCapacity();
		reflectivityTextures.clearRetainingCapacity();
		absorptionTextures.clearRetainingCapacity();
		textureFogData.clearRetainingCapacity();
		_ = arenaForWorld.reset(.free_all);
	}

	pub inline fn model(block: Block) u16 {
		return block.mode().model(block);
	}

	pub inline fn modelIndexStart(block: Block) u16 {
		return _modelIndex[block.typ];
	}

	pub inline fn fogDensity(block: Block) f32 {
		return textureFogData.items[animation.items[textureData[block.typ].textureIndices[0]].startFrame].fogDensity;
	}

	pub inline fn fogColor(block: Block) u32 {
		return textureFogData.items[animation.items[textureData[block.typ].textureIndices[0]].startFrame].fogColor;
	}

	pub inline fn hasFog(block: Block) bool {
		return fogDensity(block) != 0.0;
	}

	pub inline fn textureIndex(block: Block, orientation: usize) u16 {
		return textureData[block.typ].textureIndices[orientation];
	}

	fn extendedPath(path: []const u8, pathBuffer: []u8, ending: []const u8) []const u8 {
		std.debug.assert(path.ptr == pathBuffer.ptr);
		@memcpy(pathBuffer[path.len..][0..ending.len], ending);
		return pathBuffer[0..path.len+ending.len];
	}

	fn readAuxillaryTexture(_path: []const u8, pathBuffer: []u8, ending: []const u8, default: Image) Image {
		const path = extendedPath(_path, pathBuffer, ending);
		const texture = Image.readFromFile(arenaForWorld.allocator(), path) catch default;
		return texture;
	}

	fn extractAnimationSlice(image: Image, frame: usize, frames: usize) Image {
		if(image.height < frames) return image;
		var startHeight = image.height/frames*frame;
		if(image.height%frames > frame) startHeight += frame
		else startHeight += image.height%frames;
		var endHeight = image.height/frames*(frame + 1);
		if(image.height%frames > frame + 1) endHeight += frame + 1
		else endHeight += image.height%frames;
		var result = image;
		result.height = @intCast(endHeight - startHeight);
		result.imageData = result.imageData[startHeight*image.width..endHeight*image.width];
		return result;
	}

	fn readTextureData(_path: []const u8) void {
		var buffer: [1024]u8 = undefined;
		@memcpy(buffer[0.._path.len], _path);
		const path = buffer[0.._path.len];
		const textureInfoPath = extendedPath(path, &buffer, "_textureInfo.zig.zon");
		const textureInfoZon = main.files.readToZon(main.stackAllocator, textureInfoPath) catch .null;
		defer textureInfoZon.deinit(main.stackAllocator);
		const animationFrames = textureInfoZon.get(u32, "frames", 1);
		const animationTime = textureInfoZon.get(u32, "time", 1);
		animation.append(.{.startFrame = @intCast(blockTextures.items.len), .frames = animationFrames, .time = animationTime});
		const base = Image.readFromFile(arenaForWorld.allocator(), path) catch Image.defaultImage;
		const emission = readAuxillaryTexture(path, &buffer, "_emission.png", Image.emptyImage);
		const reflectivity = readAuxillaryTexture(path, &buffer, "_reflectivity.png", Image.emptyImage);
		const absorption = readAuxillaryTexture(path, &buffer, "_absorption.png", Image.whiteEmptyImage);
		for(0..animationFrames) |i| {
			blockTextures.append(extractAnimationSlice(base, i, animationFrames));
			emissionTextures.append(extractAnimationSlice(emission, i, animationFrames));
			reflectivityTextures.append(extractAnimationSlice(reflectivity, i, animationFrames));
			absorptionTextures.append(extractAnimationSlice(absorption, i, animationFrames));
			textureFogData.append(.{
				.fogDensity = textureInfoZon.get(f32, "fogDensity", 0.0),
				.fogColor = textureInfoZon.get(u32, "fogColor", 0xffffff),
			});
		}
	}

	pub fn readTexture(_textureId: ?[]const u8, assetFolder: []const u8) !u16 {
		const textureId = _textureId orelse return error.NotFound;
		var result: u16 = undefined;
		var splitter = std.mem.splitScalar(u8, textureId, ':');
		const mod = splitter.first();
		const id = splitter.rest();
		var buffer: [1024]u8 = undefined;
		var path = try std.fmt.bufPrint(&buffer, "{s}/{s}/blocks/textures/{s}.png", .{assetFolder, mod, id});
		// Test if it's already in the list:
		for(textureIDs.items, 0..) |other, j| {
			if(std.mem.eql(u8, other, path)) {
				result = @intCast(j);
				return result;
			}
		}
		const file = std.fs.cwd().openFile(path, .{}) catch |err| blk: {
			if(err != error.FileNotFound) {
				std.log.err("Could not open file {s}: {s}", .{path, @errorName(err)});
			}
			path = try std.fmt.bufPrint(&buffer, "assets/{s}/blocks/textures/{s}.png", .{mod, id}); // Default to global assets.
			break :blk std.fs.cwd().openFile(path, .{}) catch |err2| {
				std.log.err("File not found. Searched in \"{s}\" and also in the assetFolder \"{s}\"", .{path, assetFolder});
				return err2;
			};
		};
		file.close(); // It was only openend to check if it exists.
		// Otherwise read it into the list:
		result = @intCast(textureIDs.items.len);

		textureIDs.append(arenaForWorld.allocator().dupe(u8, path));
		readTextureData(path);
		return result;
	}

	pub fn getTextureIndices(zon: ZonElement, assetFolder: []const u8, textureIndicesRef: []u16) void {
		const defaultIndex = readTexture(zon.get(?[]const u8, "texture", null), assetFolder) catch 0;
		for(textureIndicesRef, sideNames) |*ref, name| {
			const textureId = zon.get(?[]const u8, name, null);
			ref.* = readTexture(textureId, assetFolder) catch defaultIndex;
		}
	}

	pub fn register(assetFolder: []const u8, _: []const u8, zon: ZonElement) void {
		_modelIndex[meshes.size] = _mode[meshes.size].createBlockModel(zon.get([]const u8, "model", "cubyz:cube"));

		// The actual model is loaded later, in the rendering thread.
		// But textures can be loaded here:

		getTextureIndices(zon, assetFolder, &textureData[meshes.size].textureIndices);

		maxTextureCount[meshes.size] = @intCast(textureIDs.items.len);

		meshes.size += 1;
	}

	pub fn preProcessAnimationData(time: u32) void {
		animationShader.bind();
		graphics.c.glUniform1ui(animationUniforms.time, time);
		graphics.c.glUniform1ui(animationUniforms.size, @intCast(animation.items.len));
		graphics.c.glDispatchCompute(@intCast(@divFloor(animation.items.len + 63, 64)), 1, 1); // TODO: Replace with @divCeil once available
		graphics.c.glMemoryBarrier(graphics.c.GL_SHADER_STORAGE_BARRIER_BIT);
	}

	pub fn reloadTextures(_: usize) void {
		blockTextures.clearRetainingCapacity();
		emissionTextures.clearRetainingCapacity();
		reflectivityTextures.clearRetainingCapacity();
		absorptionTextures.clearRetainingCapacity();
		textureFogData.clearAndFree();
		for(textureIDs.items) |path| {
			readTextureData(path);
		}
		generateTextureArray();
	}

	pub fn generateTextureArray() void {
		const c = graphics.c;
		blockTextureArray.generate(blockTextures.items, true, true);
		c.glTexParameterf(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_MAX_ANISOTROPY, @floatFromInt(main.settings.anisotropicFiltering));
		emissionTextureArray.generate(emissionTextures.items, true, false);
		c.glTexParameterf(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_MAX_ANISOTROPY, @floatFromInt(main.settings.anisotropicFiltering));
		const reflectivityAndAbsorptionTextures = main.stackAllocator.alloc(Image, reflectivityTextures.items.len);
		defer main.stackAllocator.free(reflectivityAndAbsorptionTextures);
		defer for(reflectivityAndAbsorptionTextures) |texture| {
			texture.deinit(main.stackAllocator);
		};
		for(reflectivityTextures.items, absorptionTextures.items, reflectivityAndAbsorptionTextures) |reflecitivityTexture, absorptionTexture, *resultTexture| {
			const width = @max(reflecitivityTexture.width, absorptionTexture.width);
			const height = @max(reflecitivityTexture.height, absorptionTexture.height);
			resultTexture.* = Image.init(main.stackAllocator, width, height);
			for(0..width) |x| {
				for(0..height) |y| {
					const reflectivity = reflecitivityTexture.getRGB(x*reflecitivityTexture.width/width, y*reflecitivityTexture.height/height);
					const absorption = absorptionTexture.getRGB(x*absorptionTexture.width/width, y*absorptionTexture.height/height);
					resultTexture.setRGB(x, y, .{.r = absorption.r, .g = absorption.g, .b = absorption.b, .a = reflectivity.r});
				}
			}
		}
		reflectivityAndAbsorptionTextureArray.generate(reflectivityAndAbsorptionTextures, true, false);
		c.glTexParameterf(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_MAX_ANISOTROPY, @floatFromInt(main.settings.anisotropicFiltering));

		// Also generate additional buffers:
		if(animationSSBO) |ssbo| {
			ssbo.deinit();
		}
		if(animatedTextureSSBO) |ssbo| {
			ssbo.deinit();
		}
		if(fogSSBO) |ssbo| {
			ssbo.deinit();
		}
		animationSSBO = SSBO.initStatic(AnimationData, animation.items);
		animationSSBO.?.bind(0);
		
		animatedTextureSSBO = SSBO.initStaticSize(u32, animation.items.len);
		animatedTextureSSBO.?.bind(1);
		fogSSBO = SSBO.initStatic(FogData, textureFogData.items);
		fogSSBO.?.bind(7);
	}
};
