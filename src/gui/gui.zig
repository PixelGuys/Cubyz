const std = @import("std");

const main = @import("root");
const graphics = main.graphics;
const draw = graphics.draw;
const ZonElement = main.ZonElement;
const settings = main.settings;
const vec = main.vec;
const Vec2f = vec.Vec2f;
const List = main.List;

const NeverFailingAllocator = main.utils.NeverFailingAllocator;

const Button = @import("components/Button.zig");
const CheckBox = @import("components/CheckBox.zig");
const ItemSlot = @import("components/ItemSlot.zig");
const ScrollBar = @import("components/ScrollBar.zig");
const ContinuousSlider = @import("components/ContinuousSlider.zig");
const DiscreteSlider = @import("components/DiscreteSlider.zig");
const TextInput = @import("components/TextInput.zig");
pub const GuiComponent = @import("gui_component.zig").GuiComponent;
pub const GuiWindow = @import("GuiWindow.zig");

pub const windowlist = @import("windows/_windowlist.zig");
const GamepadCursor = @import("gamepad_cursor.zig");

var windowList: List(*GuiWindow) = undefined;
var hudWindows: List(*GuiWindow) = undefined;
pub var openWindows: List(*GuiWindow) = undefined;
var selectedWindow: ?*GuiWindow = null;
pub var selectedTextInput: ?*TextInput = null;
var hoveredAWindow: bool = false;
pub var reorderWindows: bool = false;
pub var hideGui: bool = false;

pub var scale: f32 = undefined;

pub var hoveredItemSlot: ?*ItemSlot = null;

const GuiCommandQueue = struct { // MARK: GuiCommandQueue
	const Action = enum {
		open,
		close,
	};
	const Command = struct {
		window: *GuiWindow,
		action: Action,
	};

	var commands: main.utils.ConcurrentQueue(Command) = undefined;

	fn init() void {
		commands = .init(main.globalAllocator, 16);
	}

	fn deinit() void {
		commands.deinit();
	}

	fn scheduleCommand(command: Command) void {
		commands.enqueue(command);
	}

	fn executeCommands() void {
		while(commands.dequeue()) |command| {
			switch(command.action) {
				.open => {
					executeOpenWindowCommand(command.window);
				},
				.close => {
					executeCloseWindowCommand(command.window);
				}
			}
		}
	}

	fn executeOpenWindowCommand(window: *GuiWindow) void {
		defer updateWindowPositions();
		for(openWindows.items, 0..) |_openWindow, i| {
			if(_openWindow == window) {
				_ = openWindows.swapRemove(i);
				openWindows.appendAssumeCapacity(window);
				selectedWindow = null;
				return;
			}
		}
		openWindows.append(window);
		window.onOpenFn();
		selectedWindow = null;
	}

	fn executeCloseWindowCommand(window: *GuiWindow) void {
		defer updateWindowPositions();
		if(selectedWindow == window) {
			selectedWindow = null;
		}
		for(openWindows.items, 0..) |_openWindow, i| {
			if(_openWindow == window) {
				_ = openWindows.swapRemove(i);
				window.onCloseFn();
				break;
			}
		}
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

pub fn init() void { // MARK: init()
	GuiCommandQueue.init();
	windowList = .init(main.globalAllocator);
	hudWindows = .init(main.globalAllocator);
	openWindows = .init(main.globalAllocator);
	inline for(@typeInfo(windowlist).@"struct".decls) |decl| {
		const windowStruct = @field(windowlist, decl.name);
		windowStruct.window.id = decl.name;
		addWindow(&windowStruct.window);
		if(@hasDecl(windowStruct, "init")) {
			windowStruct.init();
		}
		const functionNames = [_][]const u8{"render", "update", "updateSelected", "updateHovered", "onOpen", "onClose"};
		inline for(functionNames) |function| {
			if(@hasDecl(windowStruct, function)) {
				@field(windowStruct.window, function ++ "Fn") = &@field(windowStruct, function);
			}
		}
	}
	GuiWindow.__init();
	Button.__init();
	CheckBox.__init();
	ItemSlot.__init();
	ScrollBar.__init();
	ContinuousSlider.__init();
	DiscreteSlider.__init();
	TextInput.__init();
	load();
	GamepadCursor.init();
}

pub fn deinit() void {
	save();
	GamepadCursor.deinit();
	windowList.deinit();
	hudWindows.deinit();
	for(openWindows.items) |window| {
		window.onCloseFn();
	}
	openWindows.deinit();
	GuiWindow.__deinit();
	Button.__deinit();
	CheckBox.__deinit();
	ItemSlot.__deinit();
	ScrollBar.__deinit();
	ContinuousSlider.__deinit();
	DiscreteSlider.__deinit();
	TextInput.__deinit();
	inline for(@typeInfo(windowlist).@"struct".decls) |decl| {
		const WindowStruct = @field(windowlist, decl.name);
		if(@hasDecl(WindowStruct, "deinit")) {
			WindowStruct.deinit();
		}
	}
	GuiCommandQueue.deinit();
}

pub fn save() void { // MARK: save()
	const guiZon = ZonElement.initObject(main.stackAllocator);
	defer guiZon.deinit(main.stackAllocator);
	for(windowList.items) |window| {
		const windowZon = ZonElement.initObject(main.stackAllocator);
		for(window.relativePosition, 0..) |relPos, i| {
			const relPosZon = ZonElement.initObject(main.stackAllocator);
			switch(relPos) {
				.ratio => |ratio| {
					relPosZon.put("type", "ratio");
					relPosZon.put("ratio", ratio);
				},
				.attachedToFrame => |attachedToFrame| {
					relPosZon.put("type", "attachedToFrame");
					relPosZon.put("selfAttachmentPoint", @intFromEnum(attachedToFrame.selfAttachmentPoint));
					relPosZon.put("otherAttachmentPoint", @intFromEnum(attachedToFrame.otherAttachmentPoint));
				},
				.relativeToWindow => |relativeToWindow| {
					relPosZon.put("type", "relativeToWindow");
					relPosZon.put("reference", relativeToWindow.reference.id);
					relPosZon.put("ratio", relativeToWindow.ratio);
				},
				.attachedToWindow => |attachedToWindow| {
					relPosZon.put("type", "attachedToWindow");
					relPosZon.put("reference", attachedToWindow.reference.id);
					relPosZon.put("selfAttachmentPoint", @intFromEnum(attachedToWindow.selfAttachmentPoint));
					relPosZon.put("otherAttachmentPoint", @intFromEnum(attachedToWindow.otherAttachmentPoint));
				},
			}
			windowZon.put(([_][]const u8{"relPos0", "relPos1"})[i], relPosZon);
		}
		windowZon.put("scale", window.scale);
		guiZon.put(window.id, windowZon);
	}

	main.files.cubyzDir().writeZon("gui_layout.zig.zon", guiZon) catch |err| {
		std.log.err("Could not write gui_layout.zig.zon: {s}", .{@errorName(err)});
	};
}

fn load() void {
	const zon: ZonElement = main.files.cubyzDir().readToZon(main.stackAllocator, "gui_layout.zig.zon") catch |err| blk: {
		if(err != error.FileNotFound) {
			std.log.err("Could not read gui_layout.zig.zon: {s}", .{@errorName(err)});
		}
		break :blk .null;
	};
	defer zon.deinit(main.stackAllocator);

	for(windowList.items) |window| {
		const windowZon = zon.getChild(window.id);
		if(windowZon == .null) continue;
		for(&window.relativePosition, 0..) |*relPos, i| {
			const relPosZon = windowZon.getChild(([_][]const u8{"relPos0", "relPos1"})[i]);
			const typ = relPosZon.get([]const u8, "type", "ratio");
			if(std.mem.eql(u8, typ, "ratio")) {
				relPos.* = .{.ratio = relPosZon.get(f32, "ratio", 0.5)};
			} else if(std.mem.eql(u8, typ, "attachedToFrame")) {
				relPos.* = .{.attachedToFrame = .{
					.selfAttachmentPoint = @enumFromInt(relPosZon.get(u8, "selfAttachmentPoint", 0)),
					.otherAttachmentPoint = @enumFromInt(relPosZon.get(u8, "otherAttachmentPoint", 0)),
				}};
			} else if(std.mem.eql(u8, typ, "relativeToWindow")) {
				const reference = getWindowById(relPosZon.get([]const u8, "reference", "")) orelse continue;
				relPos.* = .{.relativeToWindow = .{
					.reference = reference,
					.ratio = relPosZon.get(f32, "ratio", 0.5),
				}};
			} else if(std.mem.eql(u8, typ, "attachedToWindow")) {
				const reference = getWindowById(relPosZon.get([]const u8, "reference", "")) orelse continue;
				relPos.* = .{.attachedToWindow = .{
					.reference = reference,
					.selfAttachmentPoint = @enumFromInt(relPosZon.get(u8, "selfAttachmentPoint", 0)),
					.otherAttachmentPoint = @enumFromInt(relPosZon.get(u8, "otherAttachmentPoint", 0)),
				}};
			} else {
				std.log.warn("Unknown window attachment type: {s}", .{typ});
			}
		}
		window.scale = windowZon.get(f32, "scale", 1);
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

fn addWindow(window: *GuiWindow) void {
	for(windowList.items) |other| {
		if(std.mem.eql(u8, window.id, other.id)) {
			std.log.err("Duplicate window id: {s}", .{window.id});
			return;
		}
	}
	if(window.isHud) {
		hudWindows.append(window);
	}
	windowList.append(window);
}

pub fn openWindow(id: []const u8) void {
	defer updateWindowPositions();
	for(windowList.items) |window| {
		if(std.mem.eql(u8, window.id, id)) {
			openWindowFromRef(window);
			return;
		}
	}
	std.log.warn("Could not find window with id {s}.", .{id});
}

pub fn openWindowFromRef(window: *GuiWindow) void {
	GuiCommandQueue.scheduleCommand(.{.action = .open, .window = window});
}

pub fn toggleWindow(id: []const u8) void {
	defer updateWindowPositions();
	for(windowList.items) |window| {
		if(std.mem.eql(u8, window.id, id)) {
			for(openWindows.items, 0..) |_openWindow, i| {
				if(_openWindow == window) {
					_ = openWindows.swapRemove(i);
					window.onCloseFn();
					selectedWindow = null;
					return;
				}
			}
			openWindows.append(window);
			window.onOpenFn();
			selectedWindow = null;
			return;
		}
	}
	std.log.warn("Could not find window with id {s}.", .{id});
}

pub fn openHud() void {
	inventory.init();
	for(windowList.items) |window| {
		if(window.isHud) {
			openWindowFromRef(window);
		}
	}
	reorderWindows = false;
}

fn openWindowCallbackFunction(windowPtr: usize) void {
	openWindowFromRef(@ptrFromInt(windowPtr));
}
pub fn openWindowCallback(comptime id: []const u8) Callback {
	return .{
		.callback = &openWindowCallbackFunction,
		.arg = @intFromPtr(&@field(windowlist, id).window),
	};
}

pub fn closeWindowFromRef(window: *GuiWindow) void {
	GuiCommandQueue.scheduleCommand(.{.action = .close, .window = window});
}

pub fn closeWindow(id: []const u8) void {
	for(windowList.items) |window| {
		if(std.mem.eql(u8, window.id, id)) {
			closeWindowFromRef(window);
			return;
		}
	}
	std.log.warn("Could not find window with id {s}.", .{id});
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
	pub fn char(codepoint: u21) void {
		if(selectedTextInput) |current| {
			current.inputCharacter(codepoint);
		}
	}
	pub fn left(mods: main.Window.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.left(mods);
		}
	}
	pub fn right(mods: main.Window.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.right(mods);
		}
	}
	pub fn down(mods: main.Window.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.down(mods);
		}
	}
	pub fn up(mods: main.Window.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.up(mods);
		}
	}
	pub fn gotoStart(mods: main.Window.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.gotoStart(mods);
		}
	}
	pub fn gotoEnd(mods: main.Window.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.gotoEnd(mods);
		}
	}
	pub fn deleteLeft(mods: main.Window.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.deleteLeft(mods);
		}
	}
	pub fn deleteRight(mods: main.Window.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.deleteRight(mods);
		}
	}
	pub fn selectAll(mods: main.Window.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.selectAll(mods);
		}
	}
	pub fn copy(mods: main.Window.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.copy(mods);
		}
	}
	pub fn paste(mods: main.Window.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.paste(mods);
		}
	}
	pub fn cut(mods: main.Window.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.cut(mods);
		}
	}
	pub fn newline(mods: main.Window.Key.Modifiers) void {
		if(selectedTextInput) |current| {
			current.newline(mods);
		}
	}
};

pub fn mainButtonPressed() void {
	if(main.Window.grabbed) return;
	inventory.update();
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
	} else if(main.game.world != null and inventory.carried.getItem(0) == null) {
		toggleGameMenu();
	}
}

pub fn mainButtonReleased() void {
	if(main.Window.grabbed) return;
	inventory.applyChanges(true);
	const oldWindow = selectedWindow;
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
	inventory.update();
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

pub fn updateAndRenderGui() void {
	const mousePos = main.Window.getMousePosition()/@as(Vec2f, @splat(scale));
	hoveredAWindow = false;
	GuiCommandQueue.executeCommands();
	if(!main.Window.grabbed) {
		if(selectedWindow) |selected| {
			selected.updateSelected(mousePos);
		}
		hoveredItemSlot = null;
		var i: usize = openWindows.items.len;
		while(i != 0) {
			i -= 1;
			const window: *GuiWindow = openWindows.items[i];
			if(GuiComponent.contains(window.pos, window.size, mousePos)) {
				window.updateHovered(mousePos);
				hoveredAWindow = true;
				break;
			}
		}
		inventory.update();
	}
	for(openWindows.items) |window| {
		window.update();
	}
	if(!hideGui) {
		if(!main.Window.grabbed) {
			draw.setColor(0x80000000);
			GuiWindow.borderShader.bind();
			graphics.c.glUniform2f(GuiWindow.borderUniforms.effectLength, main.Window.getWindowSize()[0]/6, main.Window.getWindowSize()[1]/6);
			draw.customShadedRect(GuiWindow.borderUniforms, .{0, 0}, main.Window.getWindowSize());
		}
		const oldScale = draw.setScale(scale);
		defer draw.restoreScale(oldScale);
		for(openWindows.items) |window| {
			window.render(mousePos);
		}
		inventory.render(mousePos);
	}
	const oldScale = draw.setScale(scale);
	defer draw.restoreScale(oldScale);
	GamepadCursor.render();
}

pub fn toggleGameMenu() void {
	main.Window.setMouseGrabbed(!main.Window.grabbed);
	if(main.Window.grabbed) { // Take of the currently held item stack and close some windows
		main.game.Player.inventory.depositOrDrop(inventory.carried);
		hoveredItemSlot = null;
		var i: usize = 0;
		while(i < openWindows.items.len) {
			const window = openWindows.items[i];
			if(window.closeIfMouseIsGrabbed) {
				_ = openWindows.swapRemove(i);
				window.onCloseFn();
			} else {
				i += 1;
			}
		}
		reorderWindows = false;
	}
}

pub const inventory = struct { // MARK: inventory
	const ItemStack = main.items.ItemStack;
	const Inventory = main.items.Inventory;
	pub var carried: Inventory = undefined;
	var carriedItemSlot: *ItemSlot = undefined;
	var leftClickSlots: List(*ItemSlot) = undefined;
	var rightClickSlots: List(*ItemSlot) = undefined;
	var initialized: bool = false;

	pub fn init() void {
		carried = Inventory.init(main.globalAllocator, 1, .normal, .other);
		leftClickSlots = .init(main.globalAllocator);
		rightClickSlots = .init(main.globalAllocator);
		carriedItemSlot = ItemSlot.init(.{0, 0}, carried, 0, .default, .normal);
		carriedItemSlot.renderFrame = false;
		initialized = true;
	}

	pub fn deinit() void {
		initialized = false;
		carried.deinit(main.globalAllocator);
		carriedItemSlot.deinit();
		leftClickSlots.deinit();
		rightClickSlots.deinit();
	}

	pub fn deleteItemSlotReferences(slot: *const ItemSlot) void {
		if(slot == hoveredItemSlot) {
			hoveredItemSlot = null;
		}
		var i: usize = 0;
		while(i < leftClickSlots.items.len) {
			if(leftClickSlots.items[i] == slot) {
				_ = leftClickSlots.swapRemove(i);
				continue;
			}
			i += 1;
		}
		i = 0;
		while(i < rightClickSlots.items.len) {
			if(rightClickSlots.items[i] == slot) {
				_ = rightClickSlots.swapRemove(i);
				continue;
			}
			i += 1;
		}
	}

	fn update() void {
		if(!initialized) return;
		if(hoveredItemSlot) |itemSlot| {
			if(itemSlot.mode != .normal) return;

			if(carried.getAmount(0) == 0) return;
			if(main.KeyBoard.key("mainGuiButton").pressed) {
				for(leftClickSlots.items) |deliveredSlot| {
					if(itemSlot == deliveredSlot) {
						return;
					}
				}
				if(itemSlot.inventory.getItem(itemSlot.itemSlot) == null) {
					leftClickSlots.append(itemSlot);
				}
			} else if(main.KeyBoard.key("secondaryGuiButton").pressed) {
				for(rightClickSlots.items) |deliveredSlot| {
					if(itemSlot == deliveredSlot) {
						return;
					}
				}
				itemSlot.inventory.deposit(itemSlot.itemSlot, carried, 1);
				rightClickSlots.append(itemSlot);
			}
		}
	}

	fn applyChanges(leftClick: bool) void {
		if(!initialized) return;
		if(main.game.world == null) return;
		if(leftClick) {
			if(leftClickSlots.items.len != 0) {
				const targetInventories = main.stackAllocator.alloc(Inventory, leftClickSlots.items.len);
				defer main.stackAllocator.free(targetInventories);
				const targetSlots = main.stackAllocator.alloc(u32, leftClickSlots.items.len);
				defer main.stackAllocator.free(targetSlots);
				for(0..leftClickSlots.items.len) |i| {
					targetInventories[i] = leftClickSlots.items[i].inventory;
					targetSlots[i] = leftClickSlots.items[i].itemSlot;
				}
				carried.distribute(targetInventories, targetSlots);
				leftClickSlots.clearRetainingCapacity();
			} else if(hoveredItemSlot) |hovered| {
				hovered.inventory.depositOrSwap(hovered.itemSlot, carried);
			} else if(!hoveredAWindow) {
				carried.dropStack(0);
			}
		} else {
			if(rightClickSlots.items.len != 0) {
				rightClickSlots.clearRetainingCapacity();
			} else if(hoveredItemSlot) |hovered| {
				hovered.inventory.takeHalf(hovered.itemSlot, carried);
			} else if(!hoveredAWindow) {
				carried.dropOne(0);
			}
		}
	}

	fn render(mousePos: Vec2f) void {
		if(!initialized) return;
		carriedItemSlot.pos = mousePos - Vec2f{12, 12};
		carriedItemSlot.render(.{0, 0});
		// Draw tooltip:
		if(carried.getAmount(0) == 0) if(hoveredItemSlot) |hovered| {
			if(hovered.inventory.getItem(hovered.itemSlot)) |item| {
				const tooltip = item.getTooltip();
				var textBuffer = graphics.TextBuffer.init(main.stackAllocator, tooltip, .{}, false, .left);
				defer textBuffer.deinit();
				var size = textBuffer.calculateLineBreaks(16, 256);
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
				textBuffer.render(pos[0], pos[1], 16);
			}
		};
	}
};
