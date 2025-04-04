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
const CircularBufferQueue = main.utils.CircularBufferQueue;

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
	up: CircularBufferQueue([]const u8),
	current: ?[]const u8,
	down: CircularBufferQueue([]const u8),

	fn init(maxSize: u32) History {
		return .{
			.up = .init(main.globalAllocator, maxSize),
			.current = null,
			.down = .init(main.globalAllocator, maxSize),
		};
	}
	fn deinit(self: *History) void {
		self.clear();
		self.up.deinit();
		self.down.deinit();
	}
	fn clear(self: *History) void {
		while(self.up.dequeue()) |msg| {
			main.globalAllocator.free(msg);
		}
		if(self.current) |msg| {
			main.globalAllocator.free(msg);
			self.current = null;
		}
		while(self.down.dequeue()) |msg| {
			main.globalAllocator.free(msg);
		}
	}
	fn canMoveUp(self: *History) bool {
		return self.up.empty() == false;
	}
	fn moveUp(self: *History) void {
		std.debug.assert(self.canMoveUp());
		// This can not overflow because we are moving items between two queues of same size.
		if(self.current) |current| {
			self.down.enqueue_front(current);
		}
		self.current = self.up.dequeue_front();
		std.debug.assert(self.current != null);
	}
	fn canMoveDown(self: *History) bool {
		return self.down.empty() == false;
	}
	fn moveDown(self: *History) void {
		std.debug.assert(self.canMoveDown());
		// This can not overflow because we are moving items between two queues of same size.
		if(self.current) |current| {
			self.up.enqueue_front(current);
		}
		self.current = self.down.dequeue_front();
		std.debug.assert(self.current != null);
	}
	fn flush(self: *History) void {
		if(self.current) |msg| {
			self.up.enqueue_front(msg);
			self.current = null;
		}
		while(self.down.dequeue_front()) |msg| {
			self.up.enqueue_front(msg);
		}
	}
	fn insertIfUnique(self: *History, new: []const u8) bool {
		if(new.len == 0) return false;
		if(self.current) |current| {
			if(std.mem.eql(u8, current, new)) return false;
		}
		if(self.down.peek_front()) |msg| {
			if(std.mem.eql(u8, msg, new)) return false;
		}
		if(self.up.peek_front()) |msg| {
			if(std.mem.eql(u8, msg, new)) return false;
		}
		if(self.down.reachedCapacity()) {
			main.globalAllocator.free(self.down.dequeue_back().?);
		}
		self.down.enqueue_front(main.globalAllocator.dupe(u8, new));
		return true;
	}
	fn pushIfUnique(self: *History, new: []const u8) void {
		if(new.len == 0) return;
		if(self.current) |current| {
			if(std.mem.eql(u8, current, new)) return;
		}
		if(self.down.peek_front()) |msg| {
			if(std.mem.eql(u8, msg, new)) return;
		}
		if(self.up.peek_front()) |msg| {
			if(std.mem.eql(u8, msg, new)) return;
		}
		if(self.up.reachedCapacity()) {
			main.globalAllocator.free(self.up.dequeue_back().?);
		}
		self.up.enqueue_front(main.globalAllocator.dupe(u8, new));
	}
};

pub fn init() void {
	history = .init(main.globalAllocator);
	messageHistory = .init(reusableHistoryMaxSize);
	expirationTime = .init(main.globalAllocator);
	messageQueue = .init(main.globalAllocator, 16);
}

pub fn deinit() void {
	for(history.items) |label| {
		label.deinit();
	}
	history.deinit();
	while(messageQueue.dequeue()) |msg| {
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
	input = TextInput.init(.{0, 0}, 256, 32, "", .{.callback = &sendMessage}, .{.callback = loadNextHistoryEntry}, .{.callback = loadPreviousHistoryEntry});
	refresh();
}

pub fn loadNextHistoryEntry(_: usize) void {
	if(!messageHistory.canMoveUp()) return;

	_ = messageHistory.insertIfUnique(input.currentString.items);
	messageHistory.moveUp();

	if(messageHistory.current) |msg| {
		input.setString(msg);
	}
}

pub fn loadPreviousHistoryEntry(_: usize) void {
	if(!messageHistory.canMoveDown()) return;

	if(messageHistory.insertIfUnique(input.currentString.items)) {
		messageHistory.moveDown();
	}
	messageHistory.moveDown();

	if(messageHistory.current) |msg| {
		input.setString(msg);
	}
}

pub fn onClose() void {
	while(history.popOrNull()) |label| {
		label.deinit();
	}
	while(messageQueue.dequeue()) |msg| {
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
		const data = input.currentString.items;
		if(data.len > 10000 or main.graphics.TextBuffer.Parser.countVisibleCharacters(data) > 1000) {
			std.log.err("Chat message is too long with {}/{} characters. Limits are 1000/10000", .{main.graphics.TextBuffer.Parser.countVisibleCharacters(data), data.len});
		} else {
			messageHistory.flush();
			messageHistory.pushIfUnique(data);

			main.network.Protocols.chat.send(main.game.world.?.conn, data);
			input.clear();
		}
	}
}
