const main = @import("root");
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const GuiComponent = gui.GuiComponent;

var healthbarWindow: GuiWindow = undefined;
pub fn init() !void {
	healthbarWindow = GuiWindow{
		.contentSize = Vec2f{128, 16},
		.title = "Health Bar",
		.id = "cubyz:healthbar",
		.renderFn = &render,
		.updateFn = &update,
		.components = &[_]GuiComponent{},
	};
	try gui.addWindow(&healthbarWindow, true);
}

pub fn render() void {

}

pub fn update() void {

}