const std = @import("std");

const main = @import("main");

const graphics = main.graphics;

const Image = graphics.Image;

const ZonElement = main.ZonElement;

const Model = @This();

const id = "model";
const bit = 1;

texture: main.graphics.Texture = undefined,
model: u16 = undefined,

pub fn loadFromZon(self: *Model, zon: ZonElement) void {
	self.model = zon.get([]const u8, "model", "");
	// self.texture = readTexture(zon.get([]const u8, "texture", ""));
}