const std = @import("std");

const main = @import("root");
const vec = main.vec;
const Vec2f = vec.Vec2f;

pub const Button = @import("components/Button.zig");
pub const CheckBox = @import("components/CheckBox.zig");
pub const Label = @import("components/Label.zig");
pub const Slider = @import("components/Slider.zig");
pub const ScrollBar = @import("components/ScrollBar.zig");
pub const TextInput = @import("components/TextInput.zig");
pub const VerticalList = @import("components/VerticalList.zig");

const GuiComponent = @This();

pos: Vec2f,
size: Vec2f,
impl: Impl,

const Impl = union(enum) {
	button: Button,
	checkBox: CheckBox,
	label: Label,
	scrollBar: ScrollBar,
	slider: Slider,
	textInput: TextInput,
	verticalList: VerticalList,
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

pub fn updateSelected(self: *GuiComponent) void {
	switch(self.impl) {
		inline else => |*impl| {
			// Only call the function if it exists:
			inline for(@typeInfo(@TypeOf(impl.*)).Struct.decls) |decl| {
				if(comptime std.mem.eql(u8, decl.name, "updateSelected")) {
					impl.updateSelected(self.pos, self.size);
				}
			}
		}
	}
}

pub fn updateHovered(self: *GuiComponent, mousePosition: Vec2f) void {
	switch(self.impl) {
		inline else => |*impl| {
			// Only call the function if it exists:
			inline for(@typeInfo(@TypeOf(impl.*)).Struct.decls) |decl| {
				if(comptime std.mem.eql(u8, decl.name, "updateHovered")) {
					impl.updateHovered(self.pos, self.size, mousePosition);
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
					try impl.render(self.pos, self.size, mousePosition);
				}
			}
		}
	}
}

pub fn mainButtonPressed(self: *GuiComponent, mousePosition: Vec2f) void {
	switch(self.impl) {
		inline else => |*impl| {
			// Only call the function if it exists:
			inline for(@typeInfo(@TypeOf(impl.*)).Struct.decls) |decl| {
				if(comptime std.mem.eql(u8, decl.name, "mainButtonPressed")) {
					impl.mainButtonPressed(self.pos, self.size, mousePosition);
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
					impl.mainButtonReleased(self.pos, self.size, mousePosition);
				}
			}
		}
	}
}

pub fn contains(pos: Vec2f, size: Vec2f, point: Vec2f) bool {
	return @reduce(.And, point >= pos) and @reduce(.And, point < pos + size);
}