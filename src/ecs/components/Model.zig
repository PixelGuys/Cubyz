const std = @import("std");

const main = @import("main");

const graphics = main.graphics;

const Image = graphics.Image;
const Texture = graphics.Texture;

const ZonElement = main.ZonElement;

const Model = @This();

var entityTextures: [main.entity.maxEntityTypeCount]Image = undefined;
var entityTextureArray: [main.entity.maxEntityTypeCount]Texture = undefined;
var textureIDs: [main.entity.maxEntityTypeCount][]const u8 = undefined;
var numTextures: usize = 0;

texture: u16 = undefined,
model: u16 = undefined,

pub fn loadFromZon(assetFolder: []const u8, _: []const u8, zon: ZonElement) Model {
	return .{
		.texture = readTexture(zon.get(?[]const u8, "texture", null), assetFolder) catch 0,
	};
	// self.model = zon.get([]const u8, "model", "");
	// self.texture = readTexture(zon.get([]const u8, "texture", ""));
}

pub fn finalize() void {}

pub fn copy(self: *Model) Model {
	return .{
		.texture = self.texture,
		.model = self.model,
	};
}

pub fn serialize(self: *Model, writer: *main.utils.BinaryWriter) !void {
	_ = self;
	try writer.writeEnum(main.ecs.Components, .model);
	// ???
}


pub fn deserialize(reader: *main.utils.BinaryReader) !Model {
	// ???
	_ = reader;
	return .{};
}

fn extendedPath(_allocator: main.heap.NeverFailingAllocator, path: []const u8, ending: []const u8) []const u8 {
	return std.fmt.allocPrint(_allocator.allocator, "{s}{s}", .{path, ending}) catch unreachable;
}

fn readTextureFile(_path: []const u8, ending: []const u8, default: Image) Image {
	const path = extendedPath(main.stackAllocator, _path, ending);
	defer main.stackAllocator.free(path);
	return Image.readFromFile(main.globalAllocator, path) catch default;
}

fn readTextureData(_path: []const u8) void {
	const path = _path[0 .. _path.len - ".png".len];
	const textureInfoPath = extendedPath(main.stackAllocator, path, ".zig.zon");
	defer main.stackAllocator.free(textureInfoPath);
	const textureInfoZon = main.files.readToZon(main.stackAllocator, textureInfoPath) catch .null;
	defer textureInfoZon.deinit(main.stackAllocator);
	const base = readTextureFile(path, ".png", Image.defaultImage);
	entityTextures.append(base);
	entityTextureArray.append(.init());
}

pub fn readTexture(_textureId: ?[]const u8, assetFolder: []const u8) !u16 {
	const textureId = _textureId orelse return error.NotFound;
	var result: u16 = undefined;
	var splitter = std.mem.splitScalar(u8, textureId, ':');
	const mod = splitter.first();
	const id = splitter.rest();
	var path = try std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/{s}/entity/textures/{s}.png", .{assetFolder, mod, id});
	defer main.stackAllocator.free(path);
	
	const file = std.fs.cwd().openFile(path, .{}) catch |err| blk: {
		if(err != error.FileNotFound) {
			std.log.err("Could not open file {s}: {s}", .{path, @errorName(err)});
		}
		main.stackAllocator.free(path);
		path = try std.fmt.allocPrint(main.stackAllocator.allocator, "assets/{s}/entity/textures/{s}.png", .{mod, id}); // Default to global assets.
		break :blk std.fs.cwd().openFile(path, .{}) catch |err2| {
			std.log.err("File not found. Searched in \"{s}\" and also in the assetFolder \"{s}\"", .{path, assetFolder});
			return err2;
		};
	};
	file.close(); // It was only openend to check if it exists.
	// Otherwise read it into the list:
	result = @intCast(textureIDs.items.len);

	textureIDs.append(main.globalAllocator.dupe(u8, path));
	readTextureData(path);
	return result;
}