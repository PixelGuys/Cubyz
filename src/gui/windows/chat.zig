const std = @import("std");

const main = @import("main");
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const Label = GuiComponent.Label;
const MutexComponent = GuiComponent.MutexComponent;
const TextInput = GuiComponent.TextInput;
const VerticalList = @import("../components/VerticalList.zig");
const FixedSizeCircularBuffer = main.utils.FixedSizeCircularBuffer;

pub var window: GuiWindow = GuiWindow{
	.relativePosition = .{
		.{.attachedToFrame = .{.selfAttachmentPoint = .lower, .otherAttachmentPoint = .lower}},
		.{.attachedToFrame = .{.selfAttachmentPoint = .upper, .otherAttachmentPoint = .upper}},
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
const reusableHistoryMaxSize = 8192;

var history: main.List(*Label) = undefined;
var messageQueue: main.utils.ConcurrentQueue([]const u8) = undefined;
var expirationTime: main.List(i32) = undefined;
var historyStart: u32 = 0;
var fadeOutEnd: u32 = 0;
pub var input: *TextInput = undefined;
var hideInput: bool = true;
var messageHistory: History = undefined;

pub const History = struct {
	up: FixedSizeCircularBuffer([]const u8, reusableHistoryMaxSize),
	down: FixedSizeCircularBuffer([]const u8, reusableHistoryMaxSize),

	fn init() History {
		return .{
			.up = .init(main.globalAllocator),
			.down = .init(main.globalAllocator),
		};
	}
	fn deinit(self: *History) void {
		self.clear();
		self.up.deinit(main.globalAllocator);
		self.down.deinit(main.globalAllocator);
	}
	fn clear(self: *History) void {
		while(self.up.popFront()) |msg| {
			main.globalAllocator.free(msg);
		}
		while(self.down.popFront()) |msg| {
			main.globalAllocator.free(msg);
		}
	}
	fn flushUp(self: *History) void {
		while(self.down.popBack()) |msg| {
			if(msg.len == 0) {
				continue;
			}

			if(self.up.forcePushBack(msg)) |old| {
				main.globalAllocator.free(old);
			}
		}
	}
	pub fn isDuplicate(self: *History, new: []const u8) bool {
		if(new.len == 0) return true;
		if(self.down.peekBack()) |msg| {
			if(std.mem.eql(u8, msg, new)) return true;
		}
		if(self.up.peekBack()) |msg| {
			if(std.mem.eql(u8, msg, new)) return true;
		}
		return false;
	}
	pub fn pushDown(self: *History, new: []const u8) void {
		if(self.down.forcePushBack(new)) |old| {
			main.globalAllocator.free(old);
		}
	}
	pub fn pushUp(self: *History, new: []const u8) void {
		if(self.up.forcePushBack(new)) |old| {
			main.globalAllocator.free(old);
		}
	}
	pub fn cycleUp(self: *History) bool {
		if(self.down.popBack()) |msg| {
			self.pushUp(msg);
			return true;
		}
		return false;
	}
	pub fn cycleDown(self: *History) void {
		if(self.up.popBack()) |msg| {
			self.pushDown(msg);
		}
	}
};

pub fn init() void {
	history = .init(main.globalAllocator);
	messageHistory = .init();
	expirationTime = .init(main.globalAllocator);
	messageQueue = .init(main.globalAllocator, 16);
}

pub fn deinit() void {
	for(history.items) |label| {
		label.deinit();
	}
	history.deinit();
	while(messageQueue.popFront()) |msg| {
		main.globalAllocator.free(msg);
	}
	messageHistory.deinit();
	messageQueue.deinit();
	expirationTime.deinit();
}

fn refresh() void {
	if(window.rootComponent) |old| {
		old.verticalList.children.clearRetainingCapacity();
		old.deinit();
	}
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 0);
	for(history.items[if(hideInput) historyStart else 0..]) |msg| {
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
	input = TextInput.init(.{0, 0}, 256, 32, "", .{.callback = &sendMessage}, .{.onUp = .{.callback = loadNextHistoryEntry}, .onDown = .{.callback = loadPreviousHistoryEntry}});
	refresh();
}

pub fn loadNextHistoryEntry(_: usize) void {
	const isSuccess = messageHistory.cycleUp();
	if(messageHistory.isDuplicate(input.currentString.items)) {
		if(isSuccess) messageHistory.cycleDown();
		messageHistory.cycleDown();
	} else {
		messageHistory.pushDown(main.globalAllocator.dupe(u8, input.currentString.items));
		messageHistory.cycleDown();
	}
	const msg = messageHistory.down.peekBack() orelse "";
	input.setString(msg);
}

pub fn loadPreviousHistoryEntry(_: usize) void {
	_ = messageHistory.cycleUp();
	if(messageHistory.isDuplicate(input.currentString.items)) {} else {
		messageHistory.pushUp(main.globalAllocator.dupe(u8, input.currentString.items));
	}
	const msg = messageHistory.down.peekBack() orelse "";
	input.setString(msg);
}

pub fn onClose() void {
	while(history.popOrNull()) |label| {
		label.deinit();
	}
	while(messageQueue.popFront()) |msg| {
		main.globalAllocator.free(msg);
	}
	messageHistory.clear();
	expirationTime.clearRetainingCapacity();
	historyStart = 0;
	fadeOutEnd = 0;
	input.deinit();
	window.rootComponent.?.verticalList.children.clearRetainingCapacity();
	window.rootComponent.?.deinit();
	window.rootComponent = null;
}

pub fn update() void {
	if(!messageQueue.isEmpty()) {
		const currentTime: i32 = @truncate(main.timestamp().toMilliseconds());
		while(messageQueue.popFront()) |msg| {
			history.append(Label.init(.{0, 0}, 256, msg, .left));
			main.globalAllocator.free(msg);
			expirationTime.append(currentTime +% messageTimeout);
		}
		refresh();
	}

	const currentTime: i32 = @truncate(main.timestamp().toMilliseconds());
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
	messageQueue.pushBack(main.globalAllocator.dupe(u8, msg));
}

pub fn sendMessage(_: usize) void {
	if(input.currentString.items.len != 0) {
		const data = input.currentString.items;
		if(data.len > 10000 or main.graphics.TextBuffer.Parser.countVisibleCharacters(data) > 1000) {
			std.log.err("Chat message is too long with {}/{} characters. Limits are 1000/10000", .{main.graphics.TextBuffer.Parser.countVisibleCharacters(data), data.len});
		} else {
			messageHistory.flushUp();
			if(!messageHistory.isDuplicate(data)) {
				messageHistory.pushUp(main.globalAllocator.dupe(u8, data));
			}

			main.network.protocols.chat.send(main.game.world.?.conn, data);
			input.clear();
		}
	}
}
