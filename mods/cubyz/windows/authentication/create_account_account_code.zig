const std = @import("std");
const builtin = @import("builtin");

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

const c = @import("c");

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeIfMouseIsGrabbed = true,
	.closeable = false,
};

const padding: f32 = 8;

var accountCodeLabel: *Label = undefined;
var accountCode: ?main.network.authentication.AccountCode = null;
var fileNameEntry: *Label = undefined;
var fileName: []const u8 = undefined;

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
			main.files.cwd().write(fileName, accountCode.?.text) catch |err| {
				std.log.err("Failed to write Account Code to file: {s}", .{@errorName(err)});
				return;
			};
		},
		.paper, .passwordManager => {},
	}
	gui.closeWindowFromRef(&window);
	gui.openWindow("cubyz:authentication/login");
	// Make sure there remains no trace of the account code in memory
	accountCode.?.deinit();
	accountCode = null;
}

fn back() void {
	gui.closeWindowFromRef(&window);
	gui.openWindow("cubyz:authentication/create_account_storage_method");
}

fn copy() void {
	main.Window.setClipboardString(accountCode.?.text);
}

fn selectFile() void {
	const result: [*:0]const u8 = c.tinyfd_saveFileDialog("Select File to save Account Code", "Cubyz Account.txt", 1, @as([*]const [*:0]const u8, &.{"*.txt"}), "Text Files") orelse return;
	fileName = std.mem.span(result);
	fileNameEntry.updateText(fileName);
}

pub fn onOpen() void {
	if (accountCode == null) accountCode = .initRandomly();

	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	const width = 420;
	list.add(Label.init(.{0, 0}, width, "This is your Account Code:", .center));
	const row = HorizontalList.init();
	accountCodeLabel = Label.init(.{0, 0}, 350, accountCode.?.text, .left);
	row.add(accountCodeLabel);
	row.add(Button.initText(.{0, 0}, 70, "Copy", .{.onAction = .init(copy)}));
	list.add(row);
	switch (storageMethod) {
		.file => {
			list.add(Label.init(.{0, 0}, width, "Please enter a file name, we will store it there.", .left));
			list.add(Button.initText(.{0, 0}, 250, "Select File", .{.onAction = .init(selectFile)}));
			fileNameEntry = Label.init(.{0, 0}, width, "", .center);
			list.add(fileNameEntry);
			button = Button.initText(.{0, 0}, 250, "Save and return to login", .{.onAction = .init(next), .disabled = true});
		},
		.paper, .passwordManager => {
			if (storageMethod == .paper) list.add(Label.init(.{0, 0}, width, "We will give you some time to write it down.", .left));
			if (storageMethod == .passwordManager) list.add(Label.init(.{0, 0}, width, "We will give you some time to copy it to your password manager.", .left));
			list.add(Label.init(.{0, 0}, width, "Note: Do not give your Account Code to anyone else, only enter it in the login screen inside the game.", .left));
			button = Button.initText(.{0, 0}, 250, "Return to login (15)", .{.onAction = .init(next), .disabled = true});
		},
	}
	const buttonRow = HorizontalList.init();
	buttonRow.add(Button.initText(.{0, 0}, 50, "Back", .{.onAction = .init(back)}));
	buttonRow.add(button);
	buttonRow.finish(.{0, 0}, .center);
	list.add(buttonRow);
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
	enableTime = main.timestamp().addDuration(.fromSeconds(15));
}

pub fn update() void {
	switch (storageMethod) {
		.file => {
			button.disabled = fileName.len == 0;
		},
		.paper, .passwordManager => {
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
		},
	}
}

pub fn onClose() void {
	// Make sure there remains no trace of the account code in memory
	std.crypto.secureZero(@TypeOf(accountCodeLabel.text.glyphs[0]), accountCodeLabel.text.glyphs);
	// The account code is cleared in the next() function, otherwise it's kept in case the user goes back in the dialog

	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}

pub fn deinit() void {
	if (accountCode != null) {
		accountCode.?.deinit();
	}
}
