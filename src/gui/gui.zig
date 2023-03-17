const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const graphics = main.graphics;
const draw = graphics.draw;
const JsonElement = main.JsonElement;
const settings = main.settings;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const Button = @import("components/Button.zig");
const CheckBox = @import("components/CheckBox.zig");
const ScrollBar = @import("components/ScrollBar.zig");
const Slider = @import("components/Slider.zig");
const TextInput = @import("components/TextInput.zig");
pub const GuiComponent = @import("GuiComponent.zig");
pub const GuiWindow = @import("GuiWindow.zig");

const windowlist = @import("windows/_windowlist.zig");

var windowList: std.ArrayList(*GuiWindow) = undefined;
var hudWindows: std.ArrayList(*GuiWindow) = undefined;
pub var openWindows: std.ArrayList(*GuiWindow) = undefined;
pub var selectedWindow: ?*GuiWindow = null; // TODO: Make private.
pub var selectedTextInput: ?*TextInput = null;

pub var allocator: Allocator = undefined;

pub var scale: f32 = undefined;

pub fn init(_allocator: Allocator) !void {
	allocator = _allocator;
	windowList = std.ArrayList(*GuiWindow).init(allocator);
	hudWindows = std.ArrayList(*GuiWindow).init(allocator);
	openWindows = std.ArrayList(*GuiWindow).init(allocator);
	inline for(@typeInfo(windowlist).Struct.decls) |decl| {
		try addWindow(&@field(windowlist, decl.name).window);
	}
	try GuiWindow.__init();
	try Button.__init();
	try CheckBox.__init();
	try ScrollBar.__init();
	try Slider.__init();
	try TextInput.__init();
	try load();
}

pub fn deinit() void {
	save() catch |err| {
		std.log.err("Got error while saving gui layout: {s}", .{@errorName(err)});
	};
	windowList.deinit();
	hudWindows.deinit();
	for(openWindows.items) |window| {
		window.onCloseFn();
	}
	openWindows.deinit();
	GuiWindow.__deinit();
	Button.__deinit();
	CheckBox.__deinit();
	ScrollBar.__deinit();
	Slider.__deinit();
	TextInput.__deinit();
}

fn save() !void {
	const guiJson = try JsonElement.initObject(main.threadAllocator);
	defer guiJson.free(main.threadAllocator);
	for(windowList.items) |window| {
		const windowJson = try JsonElement.initObject(main.threadAllocator);
		for(window.relativePosition, 0..) |relPos, i| {
			const relPosJson = try JsonElement.initObject(main.threadAllocator);
			switch(relPos) {
				.ratio => |ratio| {
					try relPosJson.put("type", "ratio");
					try relPosJson.put("ratio", ratio);
				},
				.attachedToFrame => |attachedToFrame| {
					try relPosJson.put("type", "attachedToFrame");
					try relPosJson.put("selfAttachmentPoint", @enumToInt(attachedToFrame.selfAttachmentPoint));
					try relPosJson.put("otherAttachmentPoint", @enumToInt(attachedToFrame.otherAttachmentPoint));
				},
				.relativeToWindow => |relativeToWindow| {
					try relPosJson.put("type", "relativeToWindow");
					try relPosJson.put("reference", relativeToWindow.reference.id);
					try relPosJson.put("ratio", relativeToWindow.ratio);
				},
				.attachedToWindow => |attachedToWindow| {
					try relPosJson.put("type", "attachedToWindow");
					try relPosJson.put("reference", attachedToWindow.reference.id);
					try relPosJson.put("selfAttachmentPoint", @enumToInt(attachedToWindow.selfAttachmentPoint));
					try relPosJson.put("otherAttachmentPoint", @enumToInt(attachedToWindow.otherAttachmentPoint));
				},
			}
			try windowJson.put(([_][]const u8{"relPos0", "relPos1"})[i], relPosJson);
		}
		try windowJson.put("scale", window.scale);
		try guiJson.put(window.id, windowJson);
	}
	
	const string = try guiJson.toStringEfficient(main.threadAllocator, "");
	defer main.threadAllocator.free(string);

	var file = try std.fs.cwd().createFile("gui_layout.json", .{});
	defer file.close();

	try file.writeAll(string);
}

fn load() !void {
	const json: JsonElement = blk: {
		var file = std.fs.cwd().openFile("gui_layout.json", .{}) catch break :blk JsonElement{.JsonNull={}};
		defer file.close();
		const fileString = try file.readToEndAlloc(main.threadAllocator, std.math.maxInt(usize));
		defer main.threadAllocator.free(fileString);
		break :blk JsonElement.parseFromString(main.threadAllocator, fileString);
	};
	defer json.free(main.threadAllocator);

	for(windowList.items) |window| {
		const windowJson = json.getChild(window.id);
		for(&window.relativePosition, 0..) |*relPos, i| {
			const relPosJson = windowJson.getChild(([_][]const u8{"relPos0", "relPos1"})[i]);
			const typ = relPosJson.get([]const u8, "type", "ratio");
			if(std.mem.eql(u8, typ, "ratio")) {
				relPos.* = .{.ratio = relPosJson.get(f32, "ratio", 0.5)};
			} else if(std.mem.eql(u8, typ, "attachedToFrame")) {
				relPos.* = .{.attachedToFrame = .{
					.selfAttachmentPoint = @intToEnum(GuiWindow.AttachmentPoint, relPosJson.get(u8, "selfAttachmentPoint", 0)),
					.otherAttachmentPoint = @intToEnum(GuiWindow.AttachmentPoint, relPosJson.get(u8, "otherAttachmentPoint", 0)),
				}};
			} else if(std.mem.eql(u8, typ, "relativeToWindow")) {
				const reference = getWindowById(relPosJson.get([]const u8, "reference", "")) orelse continue;
				relPos.* = .{.relativeToWindow = .{
					.reference = reference,
					.ratio = relPosJson.get(f32, "ratio", 0.5),
				}};
			} else if(std.mem.eql(u8, typ, "attachedToWindow")) {
				const reference = getWindowById(relPosJson.get([]const u8, "reference", "")) orelse continue;
				relPos.* = .{.attachedToWindow = .{
					.reference = reference,
					.selfAttachmentPoint = @intToEnum(GuiWindow.AttachmentPoint, relPosJson.get(u8, "selfAttachmentPoint", 0)),
					.otherAttachmentPoint = @intToEnum(GuiWindow.AttachmentPoint, relPosJson.get(u8, "otherAttachmentPoint", 0)),
				}};
			} else {
				std.log.warn("Unknown window attachment type: {s}", .{typ});
			}
		}
		window.scale = windowJson.get(f32, "scale", 1);
	}
}

fn getWindowById(id: []const u8) ?*GuiWindow {
	for(windowList.items) |window| {
		if(std.mem.eql(u8, id, window.id)) {
			return window;
		}
	}
	std.log.warn("Could not find window with id: {s}", .{id});
	return null;
}

pub fn updateGuiScale() void {
	if(settings.guiScale) |guiScale| {
		scale = guiScale;
	} else {
		const windowSize = main.Window.getWindowSize();
		const screenWidth = @min(windowSize[0], windowSize[1]*16/9);
		scale = @floor(screenWidth/640.0 + 0.2);
		if(scale < 1) {
			scale = 0.5;
		}
	}
}

fn addWindow(window: *GuiWindow) !void {
	for(windowList.items) |other| {
		if(std.mem.eql(u8, window.id, other.id)) {
			std.log.err("Duplicate window id: {s}", .{window.id});
			return;
		}
	}
	if(window.isHud) {
		try hudWindows.append(window);
		window.showTitleBar = false;
	}
	try windowList.append(window);
}

pub fn openWindow(id: []const u8) Allocator.Error!void {
	defer updateWindowPositions();
	var wasFound: bool = false;
	for(windowList.items) |window| {
		if(std.mem.eql(u8, window.id, id)) {
			wasFound = true;
			for(openWindows.items, 0..) |_openWindow, i| {
				if(_openWindow == window) {
					_ = openWindows.swapRemove(i);
					openWindows.appendAssumeCapacity(window);
					selectedWindow = null;
					return;
				}
			}
			window.showTitleBar = true;
			try openWindows.append(window);
			try window.onOpenFn();
			selectedWindow = null;
			return;
		}
	}
	std.log.warn("Could not find window with id {s}.", .{id});
}

pub fn openWindowFunction(comptime id: []const u8) *const fn() void {
	const function = struct {
		fn function() void {
			@call(.never_inline, openWindow, .{id}) catch {
				std.log.err("Couldn't open window due to out of memory error.", .{});
			};
		}
	}.function;
	return &function;
}

pub fn closeWindow(window: *GuiWindow) void {
	defer updateWindowPositions();
	if(selectedWindow == window) {
		selectedWindow = null;
	}
	for(openWindows.items, 0..) |_openWindow, i| {
		if(_openWindow == window) {
			_ = openWindows.swapRemove(i);
		}
	}
	window.onCloseFn();
}

pub fn setSelectedTextInput(newSelectedTextInput: ?*TextInput) void {
	if(selectedTextInput) |current| {
		if(current != newSelectedTextInput) {
			current.deselect();
		}
	}
	selectedTextInput = newSelectedTextInput;
}

pub const textCallbacks = struct {
	pub fn left(mods: main.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.left(mods);
		}
	}
	pub fn right(mods: main.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.right(mods);
		}
	}
	pub fn down(mods: main.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.down(mods);
		}
	}
	pub fn up(mods: main.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.up(mods);
		}
	}
	pub fn gotoStart(mods: main.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.gotoStart(mods);
		}
	}
	pub fn gotoEnd(mods: main.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.gotoEnd(mods);
		}
	}
	pub fn deleteLeft(mods: main.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.deleteLeft(mods);
		}
	}
	pub fn deleteRight(mods: main.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.deleteRight(mods);
		}
	}
	pub fn copy(mods: main.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.copy(mods);
		}
	}
	pub fn paste(mods: main.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.paste(mods);
		}
	}
	pub fn cut(mods: main.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.cut(mods);
		}
	}
	pub fn newline(mods: main.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.newline(mods);
		}
	}
};

pub fn mainButtonPressed() void {
	selectedWindow = null;
	selectedTextInput = null;
	var selectedI: usize = 0;
	for(openWindows.items, 0..) |window, i| {
		var mousePosition = main.Window.getMousePosition()/@splat(2, scale);
		mousePosition -= window.pos;
		if(@reduce(.And, mousePosition >= Vec2f{0, 0}) and @reduce(.And, mousePosition < window.size)) {
			selectedWindow = window;
			selectedI = i;
		}
	}
	if(selectedWindow) |_selectedWindow| {
		const mousePosition = main.Window.getMousePosition()/@splat(2, scale);
		_selectedWindow.mainButtonPressed(mousePosition);
		_ = openWindows.orderedRemove(selectedI);
		openWindows.appendAssumeCapacity(_selectedWindow);
	}
}

pub fn mainButtonReleased() void {
	var oldWindow = selectedWindow;
	selectedWindow = null;
	for(openWindows.items) |window| {
		var mousePosition = main.Window.getMousePosition()/@splat(2, scale);
		mousePosition -= window.pos;
		if(@reduce(.And, mousePosition >= Vec2f{0, 0}) and @reduce(.And, mousePosition < window.size)) {
			selectedWindow = window;
		}
	}
	if(selectedWindow != oldWindow) { // Unselect the window if the mouse left it.
		selectedWindow = null;
	}
	if(oldWindow) |_oldWindow| {
		const mousePosition = main.Window.getMousePosition()/@splat(2, scale);
		_oldWindow.mainButtonReleased(mousePosition);
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
	const mousePos = main.Window.getMousePosition()/@splat(2, scale);
	if(selectedWindow) |selected| {
		try selected.updateSelected(mousePos);
	}
	var i: usize = openWindows.items.len;
	while(i != 0) {
		i -= 1;
		const window: *GuiWindow = openWindows.items[i];
		if(GuiComponent.contains(window.pos, window.size, mousePos)) {
			try window.updateHovered(mousePos);
			break;
		}
	}
	for(openWindows.items) |window| {
		const oldScale = draw.setScale(scale);
		defer draw.restoreScale(oldScale);
		try window.render(mousePos);
	}
}