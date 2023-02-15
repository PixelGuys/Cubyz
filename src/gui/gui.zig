const std = @import("std");

const main = @import("root");
const graphics = main.graphics;
const draw = graphics.draw;
const settings = main.settings;
const vec = main.vec;
const Vec2f = vec.Vec2f;

pub const GuiComponent = @import("GuiComponent.zig");
pub const GuiWindow = @import("GuiWindow.zig");

pub const hotbar = @import("windows/hotbar.zig");
pub const healthbar = @import("windows/healthbar.zig");

var windowList: std.ArrayList(*GuiWindow) = undefined;
var hudWindows: std.ArrayList(*GuiWindow) = undefined;
pub var openWindows: std.ArrayList(*GuiWindow) = undefined;
pub var selectedWindow: ?*GuiWindow = null; // TODO: Make private.

pub fn init() !void {
	windowList = std.ArrayList(*GuiWindow).init(main.globalAllocator);
	hudWindows = std.ArrayList(*GuiWindow).init(main.globalAllocator);
	openWindows = std.ArrayList(*GuiWindow).init(main.globalAllocator);
	try hotbar.init();
	try healthbar.init();
}

pub fn deinit() void {
	windowList.deinit();
	hudWindows.deinit();
	openWindows.deinit();
}

pub fn addWindow(window: *GuiWindow, isHudWindow: bool) !void {
	for(windowList.items) |other| {
		if(std.mem.eql(u8, window.id, other.id)) {
			std.log.err("Duplicate window id: {s}", .{window.id});
			return;
		}
	}
	if(isHudWindow) {
		try hudWindows.append(window);
		window.showTitleBar = false;
	}
	try windowList.append(window);
}

pub fn openWindow(id: []const u8) !void {
	defer updateWindowPositions();
	var wasFound: bool = false;
	outer: for(windowList.items) |window| {
		if(std.mem.eql(u8, window.id, id)) {
			wasFound = true;
			for(openWindows.items) |_openWindow| {
				if(_openWindow == window) {
					std.log.warn("Window with id {s} is already open.", .{id});
					continue :outer;
				}
			}
			window.showTitleBar = true;
			try openWindows.append(window);
			window.pos = .{0, 0};
			window.size = window.contentSize;
			window.onOpenFn();
			return;
		}
	}
	std.log.warn("Could not find window with id {s}.", .{id});
}

pub fn closeWindow(window: *GuiWindow) void {
	defer updateWindowPositions();
	if(selectedWindow == window) {
		selectedWindow = null;
	}
	for(openWindows.items) |_openWindow, i| {
		if(_openWindow == window) {
			openWindows.swapRemove(i);
		}
	}
	window.onCloseFn();
}

pub fn mainButtonPressed() void {
	selectedWindow = null;
	var selectedI: usize = 0;
	for(openWindows.items) |window, i| {
		var mousePosition = main.Window.getMousePosition();
		mousePosition -= window.pos;
		mousePosition /= @splat(2, window.scale*settings.guiScale);
		if(@reduce(.And, mousePosition >= Vec2f{0, 0}) and @reduce(.And, mousePosition < window.size)) {
			selectedWindow = window;
			selectedI = i;
		}
	}
	if(selectedWindow) |_selectedWindow| {
		_selectedWindow.mainButtonPressed();
		_ = openWindows.orderedRemove(selectedI);
		openWindows.appendAssumeCapacity(_selectedWindow);
	}
}

pub fn mainButtonReleased() void {
	var oldWindow = selectedWindow;
	selectedWindow = null;
	for(openWindows.items) |window| {
		var mousePosition = main.Window.getMousePosition();
		mousePosition -= window.pos;
		mousePosition /= @splat(2, window.scale*settings.guiScale);
		if(@reduce(.And, mousePosition >= Vec2f{0, 0}) and @reduce(.And, mousePosition < window.size)) {
			selectedWindow = window;
		}
	}
	if(selectedWindow != oldWindow) { // Unselect the window if the mouse left it.
		selectedWindow = null;
	}
	if(oldWindow) |_oldWindow| {
		_oldWindow.mainButtonReleased();
	}
}

pub fn updateWindowPositions() void {
	var wasChanged: bool = false;
	for(openWindows.items) |window| {
		const oldPos = window.pos;
		window.updateWindowPosition();
		const newPos = window.pos;
		if(vec.lengthSquare(oldPos - newPos) >= 1e-3) {
			wasChanged = true;
		}
	}
	if(wasChanged) @call(.always_tail, updateWindowPositions, .{}); // Very efficient O(n²) algorithm :P
}

pub fn updateAndRenderGui() !void {
	if(selectedWindow) |selected| {
		try selected.update();
	}
	for(openWindows.items) |window| {
		try window.render();
	}
}