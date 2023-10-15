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
const CraftingResultSlot = @import("components/CraftingResultSlot.zig");
const ImmutableItemSlot = @import("components/ImmutableItemSlot.zig");
const ItemSlot = @import("components/ItemSlot.zig");
const ScrollBar = @import("components/ScrollBar.zig");
const ContinuousSlider = @import("components/ContinuousSlider.zig");
const DiscreteSlider = @import("components/DiscreteSlider.zig");
const TextInput = @import("components/TextInput.zig");
pub const GuiComponent = @import("gui_component.zig").GuiComponent;
pub const GuiWindow = @import("GuiWindow.zig");

pub const windowlist = @import("windows/_windowlist.zig");

var windowList: std.ArrayList(*GuiWindow) = undefined;
var hudWindows: std.ArrayList(*GuiWindow) = undefined;
pub var openWindows: std.ArrayList(*GuiWindow) = undefined;
var selectedWindow: ?*GuiWindow = null;
var selectedTextInput: ?*TextInput = null;
var hoveredAWindow: bool = false;

pub var scale: f32 = undefined;

pub var hoveredItemSlot: ?*ItemSlot = null;
pub var hoveredCraftingSlot: ?*CraftingResultSlot = null;

const GuiCommandQueue = struct {
	const Action = enum {
		open,
		close,
	};
	const Command = struct {
		window: *GuiWindow,
		action: Action,
	};

	var commands: std.ArrayList(Command) = undefined;
	var mutex: std.Thread.Mutex = .{};

	fn init() void {
		mutex.lock();
		defer mutex.unlock();
		commands = std.ArrayList(Command).init(main.globalAllocator);
	}

	fn deinit() void {
		mutex.lock();
		defer mutex.unlock();
		commands.deinit();
	}

	fn scheduleCommand(command: Command) !void {
		mutex.lock();
		defer mutex.unlock();
		try commands.append(command);
	}

	fn executeCommands() !void {
		mutex.lock();
		defer mutex.unlock();
		for(commands.items) |command| {
			switch(command.action) {
				.open => {
					try executeOpenWindowCommand(command.window);
				},
				.close => {
					executeCloseWindowCommand(command.window);
				}
			}
		}
		commands.clearRetainingCapacity();
	}

	fn executeOpenWindowCommand(window: *GuiWindow) !void {
		std.debug.assert(!mutex.tryLock()); // mutex must be locked.
		defer updateWindowPositions();
		for(openWindows.items, 0..) |_openWindow, i| {
			if(_openWindow == window) {
				_ = openWindows.swapRemove(i);
				openWindows.appendAssumeCapacity(window);
				selectedWindow = null;
				return;
			}
		}
		try openWindows.append(window);
		try window.onOpenFn();
		selectedWindow = null;
	}

	fn executeCloseWindowCommand(window: *GuiWindow) void {
		std.debug.assert(!mutex.tryLock()); // mutex must be locked.
		defer updateWindowPositions();
		if(selectedWindow == window) {
			selectedWindow = null;
		}
		for(openWindows.items, 0..) |_openWindow, i| {
			if(_openWindow == window) {
				_ = openWindows.swapRemove(i);
				break;
			}
		}
		window.onCloseFn();
	}
};

pub const Callback = struct {
	callback: ?*const fn(usize) void = null,
	arg: usize = 0,

	pub fn run(self: Callback) void {
		if(self.callback) |callback| {
			callback(self.arg);
		}
	}
};

pub fn init() !void {
	GuiCommandQueue.init();
	windowList = std.ArrayList(*GuiWindow).init(main.globalAllocator);
	hudWindows = std.ArrayList(*GuiWindow).init(main.globalAllocator);
	openWindows = std.ArrayList(*GuiWindow).init(main.globalAllocator);
	inline for(@typeInfo(windowlist).Struct.decls) |decl| {
		const windowStruct = @field(windowlist, decl.name);
		std.debug.assert(std.mem.eql(u8, decl.name, windowStruct.window.id)); // id and file name should be the same.
		try addWindow(&windowStruct.window);
		if(@hasDecl(windowStruct, "init")) {
			try windowStruct.init();
		}
		const functionNames = [_][]const u8{"render", "update", "updateSelected", "updateHovered", "onOpen", "onClose"};
		inline for(functionNames) |function| {
			if(@hasDecl(windowStruct, function)) {
				@field(windowStruct.window, function ++ "Fn") = &@field(windowStruct, function);
			}
		}
	}
	try GuiWindow.__init();
	try Button.__init();
	try CheckBox.__init();
	try CraftingResultSlot.__init();
	try ImmutableItemSlot.__init();
	try ItemSlot.__init();
	try ScrollBar.__init();
	try ContinuousSlider.__init();
	try DiscreteSlider.__init();
	try TextInput.__init();
	try load();
	try inventory.init();
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
	CraftingResultSlot.__deinit();
	ImmutableItemSlot.__deinit();
	ItemSlot.__deinit();
	ScrollBar.__deinit();
	ContinuousSlider.__deinit();
	DiscreteSlider.__deinit();
	TextInput.__deinit();
	inline for(@typeInfo(windowlist).Struct.decls) |decl| {
		const WindowStruct = @field(windowlist, decl.name);
		if(@hasDecl(WindowStruct, "deinit")) {
			WindowStruct.deinit();
		}
	}
	inventory.deinit();
	GuiCommandQueue.deinit();
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
					try relPosJson.put("selfAttachmentPoint", @intFromEnum(attachedToFrame.selfAttachmentPoint));
					try relPosJson.put("otherAttachmentPoint", @intFromEnum(attachedToFrame.otherAttachmentPoint));
				},
				.relativeToWindow => |relativeToWindow| {
					try relPosJson.put("type", "relativeToWindow");
					try relPosJson.put("reference", relativeToWindow.reference.id);
					try relPosJson.put("ratio", relativeToWindow.ratio);
				},
				.attachedToWindow => |attachedToWindow| {
					try relPosJson.put("type", "attachedToWindow");
					try relPosJson.put("reference", attachedToWindow.reference.id);
					try relPosJson.put("selfAttachmentPoint", @intFromEnum(attachedToWindow.selfAttachmentPoint));
					try relPosJson.put("otherAttachmentPoint", @intFromEnum(attachedToWindow.otherAttachmentPoint));
				},
			}
			try windowJson.put(([_][]const u8{"relPos0", "relPos1"})[i], relPosJson);
		}
		try windowJson.put("scale", window.scale);
		try guiJson.put(window.id, windowJson);
	}
	
	try main.files.writeJson("gui_layout.json", guiJson);
}

fn load() !void {
	const json: JsonElement = main.files.readToJson(main.threadAllocator, "gui_layout.json") catch |err| blk: {
		if(err == error.FileNotFound) break :blk JsonElement{.JsonNull={}};
		return err;
	};
	defer json.free(main.threadAllocator);

	for(windowList.items) |window| {
		const windowJson = json.getChild(window.id);
		if(windowJson == .JsonNull) continue;
		for(&window.relativePosition, 0..) |*relPos, i| {
			const relPosJson = windowJson.getChild(([_][]const u8{"relPos0", "relPos1"})[i]);
			const typ = relPosJson.get([]const u8, "type", "ratio");
			if(std.mem.eql(u8, typ, "ratio")) {
				relPos.* = .{.ratio = relPosJson.get(f32, "ratio", 0.5)};
			} else if(std.mem.eql(u8, typ, "attachedToFrame")) {
				relPos.* = .{.attachedToFrame = .{
					.selfAttachmentPoint = @enumFromInt(relPosJson.get(u8, "selfAttachmentPoint", 0)),
					.otherAttachmentPoint = @enumFromInt(relPosJson.get(u8, "otherAttachmentPoint", 0)),
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
					.selfAttachmentPoint = @enumFromInt(relPosJson.get(u8, "selfAttachmentPoint", 0)),
					.otherAttachmentPoint = @enumFromInt(relPosJson.get(u8, "otherAttachmentPoint", 0)),
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
	}
	try windowList.append(window);
}

pub fn openWindow(id: []const u8) Allocator.Error!void {
	defer updateWindowPositions();
	for(windowList.items) |window| {
		if(std.mem.eql(u8, window.id, id)) {
			try openWindowFromRef(window);
			return;
		}
	}
	std.log.warn("Could not find window with id {s}.", .{id});
}

pub fn openWindowFromRef(window: *GuiWindow) Allocator.Error!void {
	try GuiCommandQueue.scheduleCommand(.{.action = .open, .window = window});
}

pub fn toggleWindow(id: []const u8) Allocator.Error!void {
	defer updateWindowPositions();
	for(windowList.items) |window| {
		if(std.mem.eql(u8, window.id, id)) {
			for(openWindows.items, 0..) |_openWindow, i| {
				if(_openWindow == window) {
					_ = openWindows.swapRemove(i);
					selectedWindow = null;
					return;
				}
			}
			try openWindows.append(window);
			try window.onOpenFn();
			selectedWindow = null;
			return;
		}
	}
	std.log.warn("Could not find window with id {s}.", .{id});
}

pub fn openHud() Allocator.Error!void {
	for(windowList.items) |window| {
		if(window.isHud) {
			try openWindowFromRef(window);
		}
	}
}

fn openWindowCallbackFunction(windowPtr: usize) void {
	openWindowFromRef(@ptrFromInt(windowPtr)) catch |err| {
		std.log.err("Encountered error while opening window: {s}", .{@errorName(err)});
	};
}
pub fn openWindowCallback(comptime id: []const u8) Callback {
	return .{
		.callback = &openWindowCallbackFunction,
		.arg = @intFromPtr(&@field(windowlist, id).window),
	};
}

pub fn closeWindow(window: *GuiWindow) !void {
	try GuiCommandQueue.scheduleCommand(.{.action = .close, .window = window});
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
	pub fn char(codepoint: u21) !void {
		if(selectedTextInput) |current| {
			try current.inputCharacter(codepoint);
		}
	}
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
	if(main.Window.grabbed) return;
	inventory.update() catch |err| {
		std.log.err("Encountered error while updating inventory: {s}", .{@errorName(err)});
	};
	if(inventory.carriedItemStack.amount != 0) {
		if(hoveredCraftingSlot) |hovered| {
			hovered.mainButtonPressed(undefined);
		}
		return;
	}
	selectedWindow = null;
	selectedTextInput = null;
	var selectedI: usize = 0;
	for(openWindows.items, 0..) |window, i| {
		var mousePosition = main.Window.getMousePosition()/@as(Vec2f, @splat(scale));
		mousePosition -= window.pos;
		if(@reduce(.And, mousePosition >= Vec2f{0, 0}) and @reduce(.And, mousePosition < window.size)) {
			selectedWindow = window;
			selectedI = i;
		}
	}
	if(selectedWindow) |_selectedWindow| {
		const mousePosition = main.Window.getMousePosition()/@as(Vec2f, @splat(scale));
		_selectedWindow.mainButtonPressed(mousePosition);
		_ = openWindows.orderedRemove(selectedI);
		openWindows.appendAssumeCapacity(_selectedWindow);
	} else if(main.game.world != null) {
		main.Window.setMouseGrabbed(true);
	}
}

pub fn mainButtonReleased() void {
	if(main.Window.grabbed) return;
	inventory.applyChanges(true);
	var oldWindow = selectedWindow;
	selectedWindow = null;
	for(openWindows.items) |window| {
		var mousePosition = main.Window.getMousePosition()/@as(Vec2f, @splat(scale));
		mousePosition -= window.pos;
		if(@reduce(.And, mousePosition >= Vec2f{0, 0}) and @reduce(.And, mousePosition < window.size)) {
			selectedWindow = window;
		}
	}
	if(selectedWindow != oldWindow) { // Unselect the window if the mouse left it.
		selectedWindow = null;
	}
	if(oldWindow) |_oldWindow| {
		const mousePosition = main.Window.getMousePosition()/@as(Vec2f, @splat(scale));
		_oldWindow.mainButtonReleased(mousePosition);
	}
}

pub fn secondaryButtonPressed() void {
	if(main.Window.grabbed) return;
	inventory.update() catch |err| {
		std.log.err("Encountered error while updating inventory: {s}", .{@errorName(err)});
	};
	if(inventory.carriedItemStack.amount != 0) return;
}

pub fn secondaryButtonReleased() void {
	if(main.Window.grabbed) return;
	inventory.applyChanges(false);
}

pub fn updateWindowPositions() void {
	var wasChanged: bool = false;
	for(windowList.items) |window| {
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
	const mousePos = main.Window.getMousePosition()/@as(Vec2f, @splat(scale));
	hoveredAWindow = false;
	try GuiCommandQueue.executeCommands();
	if(!main.Window.grabbed) {
		if(selectedWindow) |selected| {
			try selected.updateSelected(mousePos);
		}
		hoveredItemSlot = null;
		hoveredCraftingSlot = null;
		var i: usize = openWindows.items.len;
		while(i != 0) {
			i -= 1;
			const window: *GuiWindow = openWindows.items[i];
			if(GuiComponent.contains(window.pos, window.size, mousePos)) {
				try window.updateHovered(mousePos);
				hoveredAWindow = true;
				break;
			}
		}
		try inventory.update();
	}
	for(openWindows.items) |window| {
		try window.update();
	}
	if(!main.Window.grabbed) {
		draw.setColor(0x80000000);
		GuiWindow.borderShader.bind();
		graphics.c.glUniform2f(GuiWindow.borderUniforms.effectLength, main.Window.getWindowSize()[0]/6, main.Window.getWindowSize()[1]/6);
		draw.customShadedRect(GuiWindow.borderUniforms, .{0, 0}, main.Window.getWindowSize());
	}
	const oldScale = draw.setScale(scale);
	defer draw.restoreScale(oldScale);
	for(openWindows.items) |window| {
		try window.render(mousePos);
	}
	try inventory.render(mousePos);
}

pub const inventory = struct {
	const ItemStack = main.items.ItemStack;
	pub var carriedItemStack: ItemStack = .{.item = null, .amount = 0};
	var carriedItemSlot: *ItemSlot = undefined;
	var deliveredItemSlots: std.ArrayList(*ItemSlot) = undefined;
	var deliveredItemStacksAmountAdded: std.ArrayList(u16) = undefined;
	var initialAmount: u16 = 0;

	pub fn init() !void {
		deliveredItemSlots = std.ArrayList(*ItemSlot).init(main.globalAllocator);
		deliveredItemStacksAmountAdded = std.ArrayList(u16).init(main.globalAllocator);
		carriedItemSlot = try ItemSlot.init(.{0, 0}, carriedItemStack, undefined, undefined);
		carriedItemSlot.renderFrame = false;
	}

	fn deinit() void {
		carriedItemSlot.deinit();
		deliveredItemSlots.deinit();
		deliveredItemStacksAmountAdded.deinit();
		std.debug.assert(carriedItemStack.amount == 0);
	}

	fn update() !void {
		if(deliveredItemSlots.items.len == 0) {
			initialAmount = carriedItemStack.amount;
		}
		if(hoveredItemSlot) |itemSlot| {
			if(initialAmount == 0) return;
			if(!std.meta.eql(itemSlot.itemStack.item, carriedItemStack.item) and itemSlot.itemStack.item != null) return;

			if(main.KeyBoard.key("mainGuiButton").pressed) {
				for(deliveredItemSlots.items) |deliveredSlot| {
					if(itemSlot == deliveredSlot) {
						return;
					}
				}
				for(deliveredItemSlots.items, deliveredItemStacksAmountAdded.items) |deliveredSlot, oldAmountAdded| {
					deliveredSlot.tryTakingItems(&carriedItemStack, oldAmountAdded);
				}
				initialAmount = carriedItemStack.amount;
				try deliveredItemSlots.append(itemSlot);
				try deliveredItemStacksAmountAdded.append(0);
				carriedItemStack.amount = initialAmount;
				const addedAmount: u16 = @intCast(initialAmount/deliveredItemSlots.items.len);
				for(deliveredItemSlots.items, deliveredItemStacksAmountAdded.items) |deliveredSlot, *amountAdded| {
					const old = carriedItemStack.amount;
					deliveredSlot.tryAddingItems(&carriedItemStack, addedAmount);
					amountAdded.* = old - carriedItemStack.amount;
				}
			} else if(main.KeyBoard.key("secondaryGuiButton").pressed) {
				for(deliveredItemSlots.items) |deliveredStack| {
					if(itemSlot == deliveredStack) {
						return;
					}
				}
				if(carriedItemStack.amount != 0) {
					itemSlot.tryAddingItems(&carriedItemStack, 1);
					try deliveredItemSlots.append(itemSlot);
					try deliveredItemStacksAmountAdded.append(1);
				}
			}
		}
		try carriedItemSlot.updateItemStack(carriedItemStack);
	}

	fn applyChanges(leftClick: bool) void {
		if(main.game.world == null) return;
		if(deliveredItemSlots.items.len != 0) {
			deliveredItemSlots.clearRetainingCapacity();
			deliveredItemStacksAmountAdded.clearRetainingCapacity();
			if(carriedItemStack.amount == 0) {
				carriedItemStack.item = null;
			}
		} else if(hoveredItemSlot) |hovered| {
			if(carriedItemStack.amount != 0) {
				if(leftClick) {
					hovered.trySwappingItems(&carriedItemStack);
				}
			} else {
				if(leftClick) {
					hovered.tryTakingItems(&carriedItemStack, std.math.maxInt(u16));
				} else {
					hovered.tryTakingItems(&carriedItemStack, hovered.itemStack.amount/2);
				}
			}
		} else if(!hoveredAWindow) {
			if(leftClick or carriedItemStack.amount == 1) {
				main.network.Protocols.genericUpdate.itemStackDrop(main.game.world.?.conn, carriedItemStack, @floatCast(main.game.Player.getPosBlocking()), main.game.camera.direction, 20) catch |err| {
					std.log.err("Error while dropping itemStack: {s}", .{@errorName(err)});
				};
				carriedItemStack.clear();
			} else if(carriedItemStack.amount != 0) {
				main.network.Protocols.genericUpdate.itemStackDrop(main.game.world.?.conn, .{.item = carriedItemStack.item, .amount = 1}, @floatCast(main.game.Player.getPosBlocking()), main.game.camera.direction, 20) catch |err| {
					std.log.err("Error while dropping itemStack: {s}", .{@errorName(err)});
				};
				_ = carriedItemStack.add(@as(i32, -1));
			}
		}
	}

	fn render(mousePos: Vec2f) !void {
		carriedItemSlot.pos = mousePos - Vec2f{12, 12};
		try carriedItemSlot.render(.{0, 0});
		// Draw tooltip:
		if(carriedItemStack.amount == 0) if(hoveredItemSlot) |hovered| {
			if(hovered.itemStack.item) |item| {
				const tooltip = try item.getTooltip();
				var textBuffer: graphics.TextBuffer = try graphics.TextBuffer.init(main.threadAllocator, tooltip, .{}, false, .left);
				defer textBuffer.deinit();
				var size = try textBuffer.calculateLineBreaks(16, 256);
				size[0] = 0;
				for(textBuffer.lineBreaks.items) |lineBreak| {
					size[0] = @max(size[0], lineBreak.width);
				}
				var pos = mousePos;
				if(pos[0] + size[0] >= main.Window.getWindowSize()[0]/scale) {
					pos[0] -= size[0];
				}
				if(pos[1] + size[1] >= main.Window.getWindowSize()[1]/scale) {
					pos[1] -= size[1];
				}
				pos = @max(pos, Vec2f{0, 0});
				const border1: f32 = 2;
				const border2: f32 = 1;
				draw.setColor(0xffffff00);
				draw.rect(pos - @as(Vec2f, @splat(border1)), size + @as(Vec2f, @splat(2*border1)));
				draw.setColor(0xff000000);
				draw.rect(pos - @as(Vec2f, @splat(border2)), size + @as(Vec2f, @splat(2*border2)));
				try textBuffer.render(pos[0], pos[1], 16);
			}
		};
	}
};