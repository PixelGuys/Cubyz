const std = @import("std");

const main = @import("main");
const block_props = @import("block_props.zig");
const Block = block_props.Block;
const BlockProps = block_props.BlockProps;
const maxBlockCount = block_props.maxBlockCount;
const graphics = @import("../graphics.zig");
const SSBO = graphics.SSBO;
const Image = graphics.Image;
const Color = graphics.Color;
const TextureArray = graphics.TextureArray;
const models = @import("../models.zig");
const ModelIndex = models.ModelIndex;
const chunk = @import("../chunk.zig");
const Neighbor = chunk.Neighbor;
const ZonElement = @import("../zon.zig").ZonElement;


pub const meshes = struct {
	const AnimationData = extern struct {
		startFrame: u32,
		frames: u32,
		time: u32,
	};

	const FogData = extern struct {
		fogDensity: f32,
		fogColor: u32,
	};
	var size: u32 = 0;
	var _modelIndex: [maxBlockCount]ModelIndex = undefined;
	var textureIndices: [maxBlockCount][16]u16 = undefined;
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
	pub var textureOcclusionData: main.List(bool) = undefined;

	var arenaAllocatorForWorld: main.heap.NeverFailingArenaAllocator = undefined;
	var arenaForWorld: main.heap.NeverFailingAllocator = undefined;

	pub var blockBreakingTextures: main.List(u16) = undefined;

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

	var animationComputePipeline: graphics.ComputePipeline = undefined;
	var animationUniforms: struct {
		time: c_int,
		size: c_int,
	} = undefined;

	pub var blockTextureArray: TextureArray = undefined;
	pub var emissionTextureArray: TextureArray = undefined;
	pub var reflectivityAndAbsorptionTextureArray: TextureArray = undefined;
	pub var ditherTexture: graphics.Texture = undefined;

	const black: Color = Color{.r = 0, .g = 0, .b = 0, .a = 255};
	const magenta: Color = Color{.r = 255, .g = 0, .b = 255, .a = 255};
	var undefinedTexture = [_]Color{magenta, black, black, magenta};
	const undefinedImage = Image{.width = 2, .height = 2, .imageData = undefinedTexture[0..]};
	var emptyTexture = [_]Color{black};
	const emptyImage = Image{.width = 1, .height = 1, .imageData = emptyTexture[0..]};

	pub fn init() void {
		animationComputePipeline = graphics.ComputePipeline.init("assets/cubyz/shaders/animation_pre_processing.comp", "", &animationUniforms);
		blockTextureArray = .init();
		emissionTextureArray = .init();
		reflectivityAndAbsorptionTextureArray = .init();
		ditherTexture = .initFromMipmapFiles("assets/cubyz/blocks/textures/dither/", 64, 0.5);
		textureIDs = .init(main.globalAllocator);
		animation = .init(main.globalAllocator);
		blockTextures = .init(main.globalAllocator);
		emissionTextures = .init(main.globalAllocator);
		reflectivityTextures = .init(main.globalAllocator);
		absorptionTextures = .init(main.globalAllocator);
		textureFogData = .init(main.globalAllocator);
		textureOcclusionData = .init(main.globalAllocator);
		arenaAllocatorForWorld = .init(main.globalAllocator);
		arenaForWorld = arenaAllocatorForWorld.allocator();
		blockBreakingTextures = .init(main.globalAllocator);
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
		animationComputePipeline.deinit();
		blockTextureArray.deinit();
		emissionTextureArray.deinit();
		reflectivityAndAbsorptionTextureArray.deinit();
		ditherTexture.deinit();
		textureIDs.deinit();
		animation.deinit();
		blockTextures.deinit();
		emissionTextures.deinit();
		reflectivityTextures.deinit();
		absorptionTextures.deinit();
		textureFogData.deinit();
		textureOcclusionData.deinit();
		arenaAllocatorForWorld.deinit();
		blockBreakingTextures.deinit();
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
		textureOcclusionData.clearRetainingCapacity();
		blockBreakingTextures.clearRetainingCapacity();
		_ = arenaAllocatorForWorld.reset(.free_all);
	}

	pub inline fn model(block: Block) ModelIndex {
		return block.mode().model(block);
	}

	pub inline fn modelIndexStart(block: Block) ModelIndex {
		return _modelIndex[block.typ];
	}

	pub inline fn fogDensity(block: Block) f32 {
		return textureFogData.items[animation.items[textureIndices[block.typ][0]].startFrame].fogDensity;
	}

	pub inline fn fogColor(block: Block) u32 {
		return textureFogData.items[animation.items[textureIndices[block.typ][0]].startFrame].fogColor;
	}

	pub inline fn hasFog(block: Block) bool {
		return fogDensity(block) != 0.0;
	}

	pub inline fn textureIndex(block: Block, orientation: usize) u16 {
		if(orientation < 16) {
			return textureIndices[block.typ][orientation];
		} else {
			return textureIndices[block.data][orientation - 16];
		}
	}

	fn extendedPath(_allocator: main.heap.NeverFailingAllocator, path: []const u8, ending: []const u8) []const u8 {
		return std.fmt.allocPrint(_allocator.allocator, "{s}{s}", .{path, ending}) catch unreachable;
	}

	fn readTextureFile(_path: []const u8, ending: []const u8, default: Image) Image {
		const path = extendedPath(main.stackAllocator, _path, ending);
		defer main.stackAllocator.free(path);
		return Image.readFromFile(arenaForWorld, path) catch default;
	}

	fn extractAnimationSlice(image: Image, frame: usize, frames: usize) Image {
		if(image.height < frames) return image;
		var startHeight = image.height/frames*frame;
		if(image.height%frames > frame) startHeight += frame else startHeight += image.height%frames;
		var endHeight = image.height/frames*(frame + 1);
		if(image.height%frames > frame + 1) endHeight += frame + 1 else endHeight += image.height%frames;
		var result = image;
		result.height = @intCast(endHeight - startHeight);
		result.imageData = result.imageData[startHeight*image.width .. endHeight*image.width];
		return result;
	}

	fn readTextureData(_path: []const u8) void {
		const path = _path[0 .. _path.len - ".png".len];
		const textureInfoPath = extendedPath(main.stackAllocator, path, ".zig.zon");
		defer main.stackAllocator.free(textureInfoPath);
		const textureInfoZon = main.files.cwd().readToZon(main.stackAllocator, textureInfoPath) catch .null;
		defer textureInfoZon.deinit(main.stackAllocator);
		const animationFrames = textureInfoZon.get(u32, "frames", 1);
		const animationTime = textureInfoZon.get(u32, "time", 1);
		animation.append(.{.startFrame = @intCast(blockTextures.items.len), .frames = animationFrames, .time = animationTime});
		const base = readTextureFile(path, ".png", Image.defaultImage);
		const emission = readTextureFile(path, "_emission.png", Image.emptyImage);
		const reflectivity = readTextureFile(path, "_reflectivity.png", Image.emptyImage);
		const absorption = readTextureFile(path, "_absorption.png", Image.whiteEmptyImage);
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
		textureOcclusionData.append(textureInfoZon.get(bool, "hasOcclusion", true));
	}

	pub fn readTexture(_textureId: ?[]const u8, assetFolder: []const u8) !u16 {
		const textureId = _textureId orelse return error.NotFound;
		var result: u16 = undefined;
		var splitter = std.mem.splitScalar(u8, textureId, ':');
		const mod = splitter.first();
		const id = splitter.rest();
		var path = try std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/{s}/blocks/textures/{s}.png", .{assetFolder, mod, id});
		defer main.stackAllocator.free(path);
		// Test if it's already in the list:
		for(textureIDs.items, 0..) |other, j| {
			if(std.mem.eql(u8, other, path)) {
				result = @intCast(j);
				return result;
			}
		}
		const file = main.files.cwd().openFile(path) catch |err| blk: {
			if(err != error.FileNotFound) {
				std.log.err("Could not open file {s}: {s}", .{path, @errorName(err)});
			}
			main.stackAllocator.free(path);
			path = try std.fmt.allocPrint(main.stackAllocator.allocator, "assets/{s}/blocks/textures/{s}.png", .{mod, id}); // Default to global assets.
			break :blk main.files.cwd().openFile(path) catch |err2| {
				std.log.err("File not found. Searched in \"{s}\" and also in the assetFolder \"{s}\"", .{path, assetFolder});
				return err2;
			};
		};
		file.close(); // It was only openend to check if it exists.
		// Otherwise read it into the list:
		result = @intCast(textureIDs.items.len);

		textureIDs.append(arenaForWorld.dupe(u8, path));
		readTextureData(path);
		return result;
	}

	pub fn getTextureIndices(zon: ZonElement, assetFolder: []const u8, textureIndicesRef: *[16]u16) void {
		const defaultIndex = readTexture(zon.get(?[]const u8, "texture", null), assetFolder) catch 0;
		inline for(textureIndicesRef, 0..) |*ref, i| {
			var textureId = zon.get(?[]const u8, std.fmt.comptimePrint("texture{}", .{i}), null);
			if(i < sideNames.len) {
				textureId = zon.get(?[]const u8, sideNames[i], textureId);
			}
			ref.* = readTexture(textureId, assetFolder) catch defaultIndex;
		}
	}

	pub fn register(assetFolder: []const u8, _: []const u8, zon: ZonElement) void {
		_modelIndex[meshes.size] = BlockProps.mode[meshes.size].createBlockModel(.{.typ = @intCast(meshes.size), .data = 0}, &BlockProps.modeData[meshes.size], zon.getChild("model"));

		// The actual model is loaded later, in the rendering thread.
		// But textures can be loaded here:

		getTextureIndices(zon, assetFolder, &textureIndices[meshes.size]);

		maxTextureCount[meshes.size] = @intCast(textureIDs.items.len);

		meshes.size += 1;
	}

	pub fn registerBlockBreakingAnimation(assetFolder: []const u8) void {
		var i: usize = 0;
		while(true) : (i += 1) {
			const path1 = std.fmt.allocPrint(main.stackAllocator.allocator, "assets/cubyz/blocks/textures/breaking/{}.png", .{i}) catch unreachable;
			defer main.stackAllocator.free(path1);
			const path2 = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/cubyz/blocks/textures/breaking/{}.png", .{assetFolder, i}) catch unreachable;
			defer main.stackAllocator.free(path2);
			if(!main.files.cwd().hasFile(path1) and !main.files.cwd().hasFile(path2)) break;

			const id = std.fmt.allocPrint(main.stackAllocator.allocator, "cubyz:breaking/{}", .{i}) catch unreachable;
			defer main.stackAllocator.free(id);
			blockBreakingTextures.append(readTexture(id, assetFolder) catch break);
		}
	}

	pub fn preProcessAnimationData(time: u32) void {
		animationComputePipeline.bind();
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
		textureOcclusionData.clearAndFree();
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