const std = @import("std");

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

pub var window: GuiWindow = GuiWindow {
	.relativePosition = .{
		.{ .attachedToFrame = .{.selfAttachmentPoint = .lower, .otherAttachmentPoint = .lower} },
		.{ .attachedToFrame = .{.selfAttachmentPoint = .upper, .otherAttachmentPoint = .upper} },
	},
	.scale = 0.75,
	.contentSize = Vec2f{128, 256},
	.showTitleBar = false,
	.hasBackground = false,
	.isHud = true,
	.hideIfMouseIsGrabbed = false,
	.closeable = false,
};

const padding: f32 = 8;
const messageTimeout: i32 = 10000;
const messageFade = 1000;

var history: main.List(*Label) = undefined;
var messageQueue: main.utils.ConcurrentQueue([]const u8) = undefined;
var expirationTime: main.List(i32) = undefined;
var historyStart: u32 = 0;
var fadeOutEnd: u32 = 0;
pub var input: *TextInput = undefined;
var hideInput: bool = true;

fn refresh() void {
	if(window.rootComponent) |old| {
		old.verticalList.children.clearRetainingCapacity();
		old.deinit();
	}
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 0);
	for(history.items[if(hideInput) historyStart else 0 ..]) |msg| {
		msg.pos = .{0, 0};
		list.add(msg);
	}
	if(!hideInput) {
		input.pos = .{0, 0};
		list.add(input);
	}
	list.finish(.center);
	list.scrollBar.currentState = 1;
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	window.contentSize[0] = @max(window.contentSize[0], window.getMinWindowWidth());
	gui.updateWindowPositions();
	if(!hideInput) {
		for(history.items) |label| {
			label.alpha = 1;
		}
	} else {
		list.scrollBar.currentState = 1;
		list.scrollBar.size = .{0, 0};
	}
}

pub fn onOpen() void {
	history = .init(main.globalAllocator);
	expirationTime = .init(main.globalAllocator);
	messageQueue = .init(main.globalAllocator, 16);
	historyStart = 0;
	fadeOutEnd = 0;
	input = TextInput.init(.{0, 0}, 256, 32, "", .{.callback = &sendMessage});
	refresh();
}

pub fn onClose() void {
	for(history.items) |label| {
		label.deinit();
	}
	history.deinit();
	while(messageQueue.dequeue()) |msg| {
		main.globalAllocator.free(msg);
	}
	messageQueue.deinit();
	expirationTime.deinit();
	input.deinit();
	window.rootComponent.?.verticalList.children.clearRetainingCapacity();
	window.rootComponent.?.deinit();
	window.rootComponent = null;
}

pub fn update() void {
	if(!messageQueue.empty()) {
		const currentTime: i32 = @truncate(std.time.milliTimestamp());
		while(messageQueue.dequeue()) |msg| {
			history.append(Label.init(.{0, 0}, 256, msg, .left));
			main.globalAllocator.free(msg);
			expirationTime.append(currentTime +% messageTimeout);
		}
		refresh();
	}

	const currentTime: i32 = @truncate(std.time.milliTimestamp());
	while(fadeOutEnd < history.items.len and currentTime -% expirationTime.items[fadeOutEnd] >= 0) {
		fadeOutEnd += 1;
	}
	if(hideInput != main.Window.grabbed) {
		hideInput = main.Window.grabbed;
		refresh();
	}
	if(hideInput) {
		for(expirationTime.items[historyStart..fadeOutEnd], history.items[historyStart..fadeOutEnd]) |time, label| {
			if(currentTime -% time >= messageFade) {
				historyStart += 1;
				refresh();
			} else {
				const timeDifference: f32 = @floatFromInt(currentTime -% time);
				label.alpha = 1.0 - timeDifference/messageFade;
			}
		}
	}
}

pub fn render() void {
	if(!hideInput) {
		main.graphics.draw.setColor(0x80000000);
		main.graphics.draw.rect(.{0, 0}, window.contentSize);
	}
}

pub fn addMessage(msg: []const u8) void {
	messageQueue.enqueue(main.globalAllocator.dupe(u8, msg));
}

pub fn sendMessage(_: usize) void {
	if(input.currentString.items.len != 0) {
		main.network.Protocols.chat.send(main.game.world.?.conn, input.currentString.items);
		input.clear();
	}
}
