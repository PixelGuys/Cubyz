const std = @import("std");

const main = @import("main");
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = main.gui;
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = GuiComponent.Button;
const CheckBox = GuiComponent.CheckBox;
const HorizontalList = GuiComponent.HorizontalList;
const Label = GuiComponent.Label;
const TextInput = GuiComponent.TextInput;
const VerticalList = GuiComponent.VerticalList;

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeIfMouseIsGrabbed = true,
	.closeable = false,
};

const padding: f32 = 8;

var accountCodeLabel: *Label = undefined;
var accountCode: main.network.authentication.AccountCode = undefined;
var fileNameEntry: *TextInput = undefined;

pub const StorageMethod = enum(usize) {
	file = 0,
	paper = 1,
	passwordManager = 2,
};

var storageMethod: StorageMethod = undefined;
var enableTime: std.Io.Timestamp = undefined;
var button: *Button = undefined;

pub fn setStorageMethod(method: StorageMethod) void {
	storageMethod = method;
}

fn next() void {
	switch (storageMethod) {
		.file => {
			main.files.cwd().write(fileNameEntry.currentString.items, accountCode.text) catch |err| {
				std.log.err("Failed to write Account Code to file: {s}", .{@errorName(err)});
				return;
			};
		},
		.paper, .passwordManager => {},
	}
	gui.closeWindowFromRef(&window);
	gui.openWindow("authentication/login");
}

fn copy() void {
	main.Window.setClipboardString(accountCode.text);
}

pub fn onOpen() void {
	accountCode = .initRandomly();

	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	const width = 420;
	list.add(Label.init(.{0, 0}, width, "This is your Account Code:", .center));
	const row = HorizontalList.init();
	accountCodeLabel = Label.init(.{0, 0}, 350, accountCode.text, .left);
	row.add(accountCodeLabel);
	row.add(Button.initText(.{0, 0}, 70, "Copy", .{.onAction = .init(copy)}));
	list.add(row);
	switch (storageMethod) {
		.file => {
			list.add(Label.init(.{0, 0}, width, "Please enter a file name, we will store it there.", .left));
			fileNameEntry = TextInput.init(.{0, 0}, width, 22, "", .{.onNewline = .{}});
			list.add(fileNameEntry);
			button = Button.initText(.{0, 0}, 300, "Safe and return to login", .{.onAction = .init(next), .disabled = false});
			list.add(button);
		},
		.paper, .passwordManager => {
			if (storageMethod == .paper) list.add(Label.init(.{0, 0}, width, "We will give you some time to write it down.", .left));
			if (storageMethod == .passwordManager) list.add(Label.init(.{0, 0}, width, "We will give you some time to copy it to your password manager.", .left));
			list.add(Label.init(.{0, 0}, width, "Note: Do not give your Account Code to anyone else, only enter it in the login screen inside the game.", .left));
			button = Button.initText(.{0, 0}, 300, "Return to login (20)", .{.onAction = .init(next), .disabled = true});
			list.add(button);
		},
	}
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
	enableTime = main.timestamp().addDuration(.fromSeconds(20));
}

pub fn update() void {
	if (button.disabled) {
		const remainingTime = enableTime.nanoseconds -% main.timestamp().nanoseconds;
		const remainTimeSeconds = std.math.divCeil(i96, remainingTime, 1e9) catch unreachable;
		if (remainTimeSeconds <= 0) {
			button.disabled = false;
			button.child.label.updateText("Return to login");
		} else {
			const newText = std.fmt.allocPrint(main.stackAllocator.allocator, "Return to login ({})", .{remainTimeSeconds}) catch unreachable;
			defer main.stackAllocator.free(newText);
			button.child.label.updateText(newText);
		}
	}
}

pub fn onClose() void {
	// Make sure there remains no trace of the account code in memory
	std.crypto.secureZero(@TypeOf(accountCodeLabel.text.glyphs[0]), accountCodeLabel.text.glyphs);
	accountCode.deinit();

	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}
