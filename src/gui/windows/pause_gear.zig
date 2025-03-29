const std = @import("std");

const main = @import("main");
const Texture = main.graphics.Texture;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const Label = GuiComponent.Label;
const MutexComponent = GuiComponent.MutexComponent;
const TextInput = GuiComponent.TextInput;
const VerticalList = @import("../components/VerticalList.zig");

pub var window: GuiWindow = GuiWindow{
	.relativePosition = .{
		.{.attachedToFrame = .{.selfAttachmentPoint = .upper, .otherAttachmentPoint = .upper}},
		.{.attachedToFrame = .{.selfAttachmentPoint = .upper, .otherAttachmentPoint = .upper}},
	},
	.scale = 0.5,
	.contentSize = Vec2f{64, 64},
	.showTitleBar = false,
	.hasBackground = false,
	.isHud = true,
	.hideIfMouseIsGrabbed = true,
	.closeable = false,
};

const padding: f32 = 8;
const messageTimeout: i32 = 10000;
const messageFade = 1000;

var mutexComponent: MutexComponent = .{};
var history: main.List(*Label) = undefined;
var expirationTime: main.List(i32) = undefined;
var historyStart: u32 = 0;
var fadeOutEnd: u32 = 0;
var input: *TextInput = undefined;
var hideInput: bool = true;

var pauseIcon: Texture = undefined;

pub fn init() void {
	pauseIcon = Texture.initFromFile("assets/cubyz/ui/pause_icon.png");
}

pub fn deinit() void {
	pauseIcon.deinit();
}

pub fn onOpen() void {
	const button = Button.initIcon(.{0, 0}, .{64, 64}, pauseIcon, true, gui.openWindowCallback("pause"));
	window.contentSize = button.size;
	window.rootComponent = button.toComponent();
}

pub fn onClose() void {
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}
