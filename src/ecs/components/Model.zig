const std = @import("std");

const main = @import("main");

const graphics = main.graphics;

const Image = graphics.Image;

const ZonElement = main.ZonElement;

const Model = @This();

texture: main.graphics.Texture = undefined,
model: u16 = undefined,

pub fn loadFromZon(zon: ZonElement) Model {
	_ = zon;
	return .{};
	// self.model = zon.get([]const u8, "model", "");
	// self.texture = readTexture(zon.get([]const u8, "texture", ""));
}

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