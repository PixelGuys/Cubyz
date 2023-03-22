const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const Label = GuiComponent.Label;
const MutexComponent = GuiComponent.MutexComponent;
const TextInput = GuiComponent.TextInput;
const VerticalList = @import("../components/VerticalList.zig");

var components: [1]GuiComponent = undefined;
pub var window: GuiWindow = GuiWindow {
	.contentSize = Vec2f{128, 256},
	.id = "cubyz:chat",
	.title = "Chat",
	.onOpenFn = &onOpen,
	.onCloseFn = &onClose,
	.updateFn = &update,
	.renderFn = &render,
	.components = &components,
	.showTitleBar = false,
	.hasBackground = false,
	.isHud = true,
};

const padding: f32 = 8;
const messageTimeout: i32 = 10000;
const messageFade: i32 = 1000;

var mutexComponent: MutexComponent = .{};
var history: std.ArrayList(*Label) = undefined;
var expirationTime: std.ArrayList(i32) = undefined;
var historyStart: u32 = 0;
var fadeOutEnd: u32 = 0;
var input: *TextInput = undefined;
var hideInput: bool = true;

fn refresh(deleteOld: bool) Allocator.Error!void {
	std.debug.assert(!mutexComponent.mutex.tryLock()); // mutex must be locked!
	if(deleteOld) {
		components[0].mutexComponent.child.verticalList.children.clearRetainingCapacity();
		components[0].deinit();
	}
	var list = try VerticalList.init(.{padding, 16 + padding}, 300, 0);
	for(history.items[if(hideInput) historyStart else 0 ..]) |msg| {
		msg.pos = .{0, 0};
		try list.add(msg);
	}
	if(!hideInput) {
		input.pos = .{0, 0};
		try list.add(input);
	}
	list.finish(.center);
	list.scrollBar.currentState = 1;
	try mutexComponent.updateInner(list);
	components[0] = mutexComponent.toComponent();
	window.contentSize = components[0].pos() + components[0].size() + @splat(2, @as(f32, padding));
	gui.updateWindowPositions();
}

pub fn onOpen() Allocator.Error!void {
	history = std.ArrayList(*Label).init(main.globalAllocator);
	expirationTime = std.ArrayList(i32).init(main.globalAllocator);
	historyStart = 0;
	input = try TextInput.init(.{0, 0}, 256, 32, "", &sendMessage);
	mutexComponent.mutex.lock();
	defer mutexComponent.mutex.unlock();
	try refresh(false);
}

pub fn onClose() void {
	mutexComponent.mutex.lock();
	defer mutexComponent.mutex.unlock();
	for(history.items) |label| {
		label.deinit();
	}
	history.deinit();
	expirationTime.deinit();
	input.deinit();
	components[0].mutexComponent.child.verticalList.children.clearRetainingCapacity();
	components[0].deinit();
}

pub fn update() Allocator.Error!void {
	mutexComponent.mutex.lock();
	defer mutexComponent.mutex.unlock();
	while(fadeOutEnd < history.items.len and @truncate(i32, std.time.milliTimestamp()) -% expirationTime.items[fadeOutEnd] >= 0) {
		fadeOutEnd += 1;
	}
	for(expirationTime.items[historyStart..fadeOutEnd], history.items[historyStart..fadeOutEnd]) |time, label| {
		if(@truncate(i32, std.time.milliTimestamp()) -% time >= messageFade) {
			historyStart += 1;
			hideInput = main.Window.grabbed;
			try refresh(true);
		} else {
			label.alpha = 1.0 - @intToFloat(f32, @truncate(i32, std.time.milliTimestamp()) -% time)/@intToFloat(f32, messageFade);
		}
	}
	if(hideInput != main.Window.grabbed) {
		hideInput = main.Window.grabbed;
		try refresh(true);
	}
}

pub fn render() Allocator.Error!void {
	if(!hideInput) {
		main.graphics.draw.setColor(0x80000000);
		main.graphics.draw.rect(.{0, 0}, window.contentSize);
	}
}

pub fn addMessage(message: []const u8) Allocator.Error!void {
	mutexComponent.mutex.lock();
	defer mutexComponent.mutex.unlock();
	try history.append(try Label.init(.{0, 0}, 256, message, .left));
	try expirationTime.append(@truncate(i32, std.time.milliTimestamp()) +% messageTimeout);
	try refresh(true);
}

pub fn sendMessage() void {
	main.network.Protocols.chat.send(main.game.world.?.conn, input.currentString.items) catch |err| {
		std.log.err("Got error while trying to send chat message: {s}", .{@errorName(err)});
	};
	input.clear() catch |err| {
		std.log.err("Got error while trying to send chat message: {s}", .{@errorName(err)});
	};
}