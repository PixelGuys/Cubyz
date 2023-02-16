const std = @import("std");

const main = @import("root");
const vec = main.vec;
const Vec2f = vec.Vec2f;

const Button = @import("components/Button.zig");

const GuiComponent = @This();

pos: Vec2f,
size: Vec2f,
impl: Impl,

const Impl = union(enum) {
	button: Button,
};

pub fn deinit(self: *GuiComponent) void {
	switch(self.impl) {
		inline else => |*impl| {
			// Only call the function if it exists:
			inline for(@typeInfo(@TypeOf(impl.*)).Struct.decls) |decl| {
				if(comptime std.mem.eql(u8, decl.name, "deinit")) {
					impl.deinit();
				}
			}
		}
	}
}

pub fn update(self: *GuiComponent) void {
	switch(self.impl) {
		inline else => |*impl| {
			// Only call the function if it exists:
			inline for(@typeInfo(@TypeOf(impl.*)).Struct.decls) |decl| {
				if(comptime std.mem.eql(u8, decl.name, "update")) {
					impl.update(self);
				}
			}
		}
	}
}

pub fn render(self: *GuiComponent, mousePosition: Vec2f) !void {
	switch(self.impl) {
		inline else => |*impl| {
			// Only call the function if it exists:
			inline for(@typeInfo(@TypeOf(impl.*)).Struct.decls) |decl| {
				if(comptime std.mem.eql(u8, decl.name, "render")) {
					try impl.render(self, mousePosition);
				}
			}
		}
	}
}

pub fn mainButtonPressed(self: *GuiComponent) void {
	switch(self.impl) {
		inline else => |*impl| {
			// Only call the function if it exists:
			inline for(@typeInfo(@TypeOf(impl.*)).Struct.decls) |decl| {
				if(comptime std.mem.eql(u8, decl.name, "mainButtonPressed")) {
					impl.mainButtonPressed(self);
				}
			}
		}
	}
}

pub fn mainButtonReleased(self: *GuiComponent, mousePosition: Vec2f) void {
	switch(self.impl) {
		inline else => |*impl| {
			// Only call the function if it exists:
			inline for(@typeInfo(@TypeOf(impl.*)).Struct.decls) |decl| {
				if(comptime std.mem.eql(u8, decl.name, "mainButtonReleased")) {
					impl.mainButtonReleased(self, mousePosition);
				}
			}
		}
	}
}

pub fn contains(self: GuiComponent, pos: Vec2f) bool {
	return @reduce(.And, pos >= self.pos) and @reduce(.And, pos < self.pos + self.size);
}