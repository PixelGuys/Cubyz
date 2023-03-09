const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const graphics = main.graphics;
const draw = graphics.draw;
const TextBuffer = graphics.TextBuffer;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;

const TextInput = @This();

const fontSize: f32 = 16;

pressed: bool = false,
cursor: ?u32 = null,
selectionStart: ?u32 = null,
currentString: std.ArrayList(u8),
textBuffer: TextBuffer,
maxWidth: f32,
textSize: Vec2f = undefined,

// TODO: Make this scrollable.

pub fn init(allocator: Allocator, pos: Vec2f, maxWidth: f32, text: []const u8) Allocator.Error!GuiComponent {
	var self = TextInput {
		.currentString = std.ArrayList(u8).init(allocator),
		.textBuffer = try TextBuffer.init(allocator, text, .{}, true),
		.maxWidth = maxWidth,
	};
	try self.currentString.appendSlice(text);
	self.textSize = try self.textBuffer.calculateLineBreaks(fontSize, maxWidth);
	return GuiComponent {
		.pos = pos,
		.size = self.textSize,
		.impl = .{.textInput = self}
	};
}

pub fn deinit(self: TextInput) void {
	self.textBuffer.deinit();
	self.currentString.deinit();
}

pub fn mainButtonPressed(self: *TextInput, pos: Vec2f, _: Vec2f, mousePosition: Vec2f) void {
	self.cursor = null;
	self.selectionStart = self.textBuffer.mousePosToIndex(mousePosition - pos, self.currentString.items.len);
	self.pressed = true;
}

pub fn mainButtonReleased(self: *TextInput, pos: Vec2f, _: Vec2f, mousePosition: Vec2f) void {
	if(self.pressed) {
		self.cursor = self.textBuffer.mousePosToIndex(mousePosition - pos, self.currentString.items.len);
		if(self.cursor == self.selectionStart) {
			self.selectionStart = null;
		}
		self.pressed = false;
		gui.setSelectedTextInput(self);
	}
}

pub fn deselect(self: *TextInput) void {
	self.cursor = null;
	self.selectionStart = null;
}

fn reloadText(self: *TextInput) !void {
	self.textBuffer.deinit();
	self.textBuffer = try TextBuffer.init(self.currentString.allocator, self.currentString.items, .{}, true);
	self.textSize = try self.textBuffer.calculateLineBreaks(fontSize, self.maxWidth);
}

fn moveCursorLeft(self: *TextInput, mods: main.Key.Modifiers) void {
	if(mods.control) {
		const text = self.currentString.items;
		if(self.cursor.? == 0) return;
		self.cursor.? -= 1;
		// Find end of previous "word":
		while(!std.ascii.isAlphabetic(text[self.cursor.?]) and std.ascii.isASCII(text[self.cursor.?])) {
			if(self.cursor.? == 0) return;
			self.cursor.? -= 1;
		}
		// Find the start of the previous "word":
		while(std.ascii.isAlphabetic(text[self.cursor.?]) or !std.ascii.isASCII(text[self.cursor.?])) {
			if(self.cursor.? == 0) return;
			self.cursor.? -= 1;
		}
		self.cursor.? += 1;
	} else {
		while(self.cursor.? > 0) {
			self.cursor.? -= 1;
			if((std.unicode.utf8ByteSequenceLength(self.currentString.items[self.cursor.?]) catch 0) != 0) break; // Ugly hack to check if we found a valid start byte.
		}
	}
}

pub fn left(self: *TextInput, mods: main.Key.Modifiers) void {
	if(self.cursor) |*cursor| {
		if(mods.shift) {
			if(self.selectionStart == null) {
				self.selectionStart = cursor.*;
			}
			self.moveCursorLeft(mods);
			if(self.selectionStart == self.cursor) {
				self.selectionStart = null;
			}
		} else {
			if(self.selectionStart) |selectionStart| {
				cursor.* = @min(cursor.*, selectionStart);
				self.selectionStart = null;
			} else {
				self.moveCursorLeft(mods);
			}
		}
	}
}

fn moveCursorRight(self: *TextInput, mods: main.Key.Modifiers) void {
	if(self.cursor.? < self.currentString.items.len) {
		if(mods.control) {
			const text = self.currentString.items;
			// Find start of next "word":
			while(!std.ascii.isAlphabetic(text[self.cursor.?]) and std.ascii.isASCII(text[self.cursor.?])) {
				self.cursor.? += 1;
				if(self.cursor.? >= self.currentString.items.len) return;
			}
			// Find the end of the next "word":
			while(std.ascii.isAlphabetic(text[self.cursor.?]) or !std.ascii.isASCII(text[self.cursor.?])) {
				self.cursor.? += 1;
				if(self.cursor.? >= self.currentString.items.len) return;
			}
		} else {
			self.cursor.? += std.unicode.utf8ByteSequenceLength(self.currentString.items[self.cursor.?]) catch unreachable;
		}
	}
}

pub fn right(self: *TextInput, mods: main.Key.Modifiers) void {
	if(self.cursor) |*cursor| {
		if(mods.shift) {
			if(self.selectionStart == null) {
				self.selectionStart = cursor.*;
			}
			self.moveCursorRight(mods);
			if(self.selectionStart == self.cursor) {
				self.selectionStart = null;
			}
		} else {
			if(self.selectionStart) |selectionStart| {
				cursor.* = @max(cursor.*, selectionStart);
				self.selectionStart = null;
			} else {
				self.moveCursorRight(mods);
			}
		}
	}
}

fn moveCursorVertically(self: *TextInput, relativeLines: f32) void {
	self.cursor = self.textBuffer.mousePosToIndex(self.textBuffer.indexToCursorPos(self.cursor.?) + Vec2f{0, 16*relativeLines}, self.currentString.items.len);
}

pub fn down(self: *TextInput, mods: main.Key.Modifiers) void {
	if(self.cursor) |*cursor| {
		if(mods.shift) {
			if(self.selectionStart == null) {
				self.selectionStart = cursor.*;
			}
			self.moveCursorVertically(1);
			if(self.selectionStart == self.cursor) {
				self.selectionStart = null;
			}
		} else {
			if(self.selectionStart) |selectionStart| {
				cursor.* = @max(cursor.*, selectionStart);
				self.selectionStart = null;
			} else {
				self.moveCursorVertically(1);
			}
		}
	}
}

pub fn up(self: *TextInput, mods: main.Key.Modifiers) void {
	if(self.cursor) |*cursor| {
		if(mods.shift) {
			if(self.selectionStart == null) {
				self.selectionStart = cursor.*;
			}
			self.moveCursorVertically(-1);
			if(self.selectionStart == self.cursor) {
				self.selectionStart = null;
			}
		} else {
			if(self.selectionStart) |selectionStart| {
				cursor.* = @min(cursor.*, selectionStart);
				self.selectionStart = null;
			} else {
				self.moveCursorVertically(-1);
			}
		}
	}
}

fn moveCursorToStart(self: *TextInput, mods: main.Key.Modifiers) void {
	if(mods.control) {
		self.cursor.? = 0;
	} else {
		self.cursor.? = @intCast(u32, if(std.mem.lastIndexOf(u8, self.currentString.items[0..self.cursor.?], "\n")) |nextPos| nextPos + 1 else 0);
	}
}

pub fn gotoStart(self: *TextInput, mods: main.Key.Modifiers) void {
	if(self.cursor) |*cursor| {
		if(mods.shift) {
			if(self.selectionStart == null) {
				self.selectionStart = cursor.*;
			}
			self.moveCursorToStart(mods);
			if(self.selectionStart == self.cursor) {
				self.selectionStart = null;
			}
		} else {
			if(self.selectionStart) |selectionStart| {
				cursor.* = @min(cursor.*, selectionStart);
				self.selectionStart = null;
			} else {
				self.moveCursorToStart(mods);
			}
		}
	}
}

fn moveCursorToEnd(self: *TextInput, mods: main.Key.Modifiers) void {
	if(mods.control) {
		self.cursor.? = @intCast(u32, self.currentString.items.len);
	} else {
		self.cursor.? += @intCast(u32, std.mem.indexOf(u8, self.currentString.items[self.cursor.?..], "\n") orelse self.currentString.items.len - self.cursor.?);
	}
}

pub fn gotoEnd(self: *TextInput, mods: main.Key.Modifiers) void {
	if(self.cursor) |*cursor| {
		if(mods.shift) {
			if(self.selectionStart == null) {
				self.selectionStart = cursor.*;
			}
			self.moveCursorToEnd(mods);
			if(self.selectionStart == self.cursor) {
				self.selectionStart = null;
			}
		} else {
			if(self.selectionStart) |selectionStart| {
				cursor.* = @min(cursor.*, selectionStart);
				self.selectionStart = null;
			} else {
				self.moveCursorToEnd(mods);
			}
		}
	}
}

fn deleteSelection(self: *TextInput) void {
	if(self.selectionStart) |selectionStart| {
		const start = @min(selectionStart, self.cursor.?);
		const end = @max(selectionStart, self.cursor.?);

		self.currentString.replaceRange(start, end - start, &[0]u8{}) catch unreachable;
		self.cursor.? = start;
		self.selectionStart = null;
	}
}

pub fn deleteLeft(self: *TextInput, _: main.Key.Modifiers) void {
	if(self.cursor == null) return;
	if(self.selectionStart == null) {
		self.selectionStart = self.cursor;
		self.moveCursorLeft(.{});
	}
	self.deleteSelection();
	self.reloadText() catch |err| {
		std.log.err("Error while deleting text: {s}", .{@errorName(err)});
	};
}

pub fn deleteRight(self: *TextInput, _: main.Key.Modifiers) void {
	if(self.cursor == null) return;
	if(self.selectionStart == null) {
		self.selectionStart = self.cursor;
		self.moveCursorRight(.{});
	}
	self.deleteSelection();
	self.reloadText() catch |err| {
		std.log.err("Error while deleting text: {s}", .{@errorName(err)});
	};
}

pub fn inputCharacter(self: *TextInput, character: u21) !void {
	if(self.cursor) |*cursor| {
		self.deleteSelection();
		var buf: [4]u8 = undefined;
		var utf8 = buf[0..try std.unicode.utf8Encode(character, &buf)];
		try self.currentString.insertSlice(cursor.*, utf8);
		try self.reloadText();
		cursor.* += @intCast(u32, utf8.len);
	}
}

pub fn copy(self: *TextInput, mods: main.Key.Modifiers) void {
	if(mods.control) {
		if(self.cursor) |cursor| {
			if(self.selectionStart) |selectionStart| {
				const start = @min(cursor, selectionStart);
				const end = @max(cursor, selectionStart);
				main.Window.setClipboardString(self.currentString.items[start..end]);
			}
		}
	}
}

pub fn paste(self: *TextInput, mods: main.Key.Modifiers) void {
	if(mods.control) {
		const string = main.Window.getClipboardString();
		self.deleteSelection();
		self.currentString.insertSlice(self.cursor.?, string) catch |err| {
			std.log.err("Error while pasting text: {s}", .{@errorName(err)});
		};
		self.cursor.? += @intCast(u32, string.len);
		self.reloadText() catch |err| {
			std.log.err("Error while pasting text: {s}", .{@errorName(err)});
		};
	}
}

pub fn cut(self: *TextInput, mods: main.Key.Modifiers) void {
	if(mods.control) {
		self.copy(mods);
		self.deleteSelection();
		self.reloadText() catch |err| {
			std.log.err("Error while cutting text: {s}", .{@errorName(err)});
		};
	}
}

pub fn newline(self: *TextInput, _: main.Key.Modifiers) void {
	self.inputCharacter('\n') catch |err| {
		std.log.err("Error while entering text: {s}", .{@errorName(err)});
	};
}

pub fn render(self: *TextInput, pos: Vec2f, _: Vec2f, mousePosition: Vec2f) !void {
	try self.textBuffer.render(pos[0], pos[1], fontSize);
	if(self.pressed) {
		self.cursor = self.textBuffer.mousePosToIndex(mousePosition - pos, self.currentString.items.len);
	}
	if(self.cursor) |cursor| {
		if(self.selectionStart) |selectionStart| {
			draw.setColor(0x440000ff);
			try self.textBuffer.drawSelection(pos, @min(selectionStart, cursor), @max(selectionStart, cursor));
		}
		draw.setColor(0xff000000);
		const cursorPos = pos + self.textBuffer.indexToCursorPos(cursor);
		draw.line(cursorPos, cursorPos + Vec2f{0, 16});
	}
}