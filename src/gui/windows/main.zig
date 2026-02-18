const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const Texture = graphics.Texture;
const draw = graphics.draw;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const Label = @import("../components/Label.zig");
const Icon = @import("../components/Icon.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeable = false,
	.hasBackground = false,
	.showTitleBar = false,
};

const padding: f32 = 8;

var logo: Texture = undefined;

pub fn init() void {
	logo = Texture.initFromFile("assets/cubyz/ui/logo.png");
}

pub fn deinit() void {
	logo.deinit();
}

fn exitGame() void {
	main.Window.c.glfwSetWindowShouldClose(main.Window.window, main.Window.c.GLFW_TRUE);
}
pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 2);
	list.add(Icon.init(.{0, 0}, .{384, 96}, logo, true));
	list.add(Icon.init(.{0, 0}, .{0, 64}, .{.textureID = 0}, false));
	list.add(Button.initMainMenuText(.{0, 0}, 192, "Singleplayer", gui.openWindowCallback("save_selection")));
	list.add(Button.initMainMenuText(.{0, 0}, 192, "Multiplayer", gui.openWindowCallback("multiplayer")));
	list.add(Button.initMainMenuText(.{0, 0}, 192, "Settings", gui.openWindowCallback("settings")));
	list.add(Icon.init(.{0, 0}, .{0, 8}, .{.textureID = 0}, false));
	list.add(Button.initMainMenuText(.{0, 0}, 128, "Quit Game", .init(exitGame)));
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}

pub fn render() void {
	const old = draw.setTranslation(.{0, 0});
	draw.restoreTranslation(.{0, 0});
	defer draw.restoreTranslation(old);

	draw.setColor(0xffffffff);
	draw.print("Cubyz {s}", .{main.settings.version.version}, 9, 9, 8, .left);

	const windowSize = main.Window.getWindowSize()/@as(Vec2f, @splat(gui.scale));
	draw.setColor(0x60ffffff);
	draw.rectBorder(.{7, 7}, windowSize - Vec2f{14, 14}, 1);
}
