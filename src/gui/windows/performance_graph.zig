const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const GuiComponent = gui.GuiComponent;

const chat = @import("chat.zig");

pub var window = GuiWindow {
	.contentSize = Vec2f{128, 64},
	.relativePosition = .{
		.{ .attachedToFrame = .{.selfAttachmentPoint = .lower, .otherAttachmentPoint = .lower} },
		.{ .attachedToWindow = .{.reference = &chat.window, .selfAttachmentPoint = .upper, .otherAttachmentPoint = .lower} },
	},
	.id = "performance_graph",
	.isHud = false,
	.showTitleBar = false,
	.hasBackground = false,
	.hideIfMouseIsGrabbed = false,
};

var lastFrameTime: [2048]f32 = undefined;
var index: u31 = 0;
var ssbo: graphics.SSBO = undefined;
var shader: graphics.Shader = undefined;
const border: f32 = 8;

var uniforms: struct {
	start: c_int,
	dimension: c_int,
	screen: c_int,
	points: c_int,
	offset: c_int,
	lineColor: c_int,
} = undefined;

pub fn init() !void {
	ssbo = graphics.SSBO.init();
	shader = try graphics.Shader.initAndGetUniforms("assets/cubyz/shaders/graphics/graph.vs", "assets/cubyz/shaders/graphics/graph.fs", &uniforms);
}

pub fn deinit() void {
	ssbo.deinit();
}

fn flawedRender() !void {
	lastFrameTime[index] = @floatCast(main.lastFrameTime.load(.Monotonic)*1000.0);
	index = (index + 1)%@as(u31, @intCast(lastFrameTime.len));
	draw.setColor(0xffffffff);
	try draw.text("32 ms", 0, 16, 8, .left);
	try draw.text("16 ms", 0, 32, 8, .left);
	try draw.text("00 ms", 0, 48, 8, .left);
	draw.setColor(0x80ffffff);
	draw.line(.{border, 24}, .{window.contentSize[0] - border, 24});
	draw.line(.{border, 40}, .{window.contentSize[0] - border, 40});
	draw.line(.{border, 56}, .{window.contentSize[0] - border, 56});
	draw.setColor(0xffffffff);
	shader.bind();
	graphics.c.glUniform1i(uniforms.points, lastFrameTime.len);
	graphics.c.glUniform1i(uniforms.offset, index);
	graphics.c.glUniform3f(uniforms.lineColor, 1, 1, 1);
	var pos = Vec2f{border, border};
	var dim = window.contentSize - @as(Vec2f, @splat(2*border));
	pos *= @splat(draw.setScale(1));
	pos += draw.setTranslation(.{0, 0});
	dim *= @splat(draw.setScale(1));
	pos = @floor(pos);
	dim = @ceil(dim);
	pos[1] += dim[1];

	graphics.c.glUniform2f(uniforms.screen, @floatFromInt(main.Window.width), @floatFromInt(main.Window.height));
	graphics.c.glUniform2f(uniforms.start, pos[0], pos[1]);
	graphics.c.glUniform2f(uniforms.dimension, dim[0], draw.setScale(1));
	ssbo.bufferData(f32, &lastFrameTime);
	ssbo.bind(5);
	graphics.c.glDrawArrays(graphics.c.GL_LINE_STRIP, 0, lastFrameTime.len);
}

pub fn render() Allocator.Error!void {
	flawedRender() catch |err| {
		std.log.err("Encountered error while drawing debug window: {s}", .{@errorName(err)});
	};
}