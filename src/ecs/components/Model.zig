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

entityId: u32 = undefined,

texture: u16 = undefined,
model: u16 = undefined,

pub fn loadFromZon(_: []const u8, _: []const u8, _: ZonElement) Model {
	return .{};
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