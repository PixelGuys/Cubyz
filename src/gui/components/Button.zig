const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const Shader = graphics.Shader;
const TextBuffer = graphics.TextBuffer;
const Texture = graphics.Texture;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const Icon = GuiComponent.Icon;
const Label = GuiComponent.Label;

const Button = @This();

const border: f32 = 3;
const fontSize: f32 = 16;

const Textures = struct {
	texture: Texture,
	outlineTexture: Texture,
	outlineTextureSize: Vec2f,

	pub fn init(basePath: []const u8) Textures {
		var self: Textures = undefined;
		const buttonPath = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}.png", .{basePath}) catch unreachable;
		defer main.stackAllocator.free(buttonPath);
		self.texture = Texture.initFromFile(buttonPath);
		const outlinePath = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}_outline.png", .{basePath}) catch unreachable;
		defer main.stackAllocator.free(outlinePath);
		self.outlineTexture = Texture.initFromFile(outlinePath);
		self.outlineTextureSize = @floatFromInt(self.outlineTexture.size());
		return self;
	}

	pub fn deinit(self: Textures) void {
		self.texture.deinit();
		self.outlineTexture.deinit();
	}
};
var normalTextures: Textures = undefined;
var hoveredTextures: Textures = undefined;
var pressedTextures: Textures = undefined;
pub var shader: Shader = undefined;
pub var buttonUniforms: struct {
	screen: c_int,
	start: c_int,
	size: c_int,
	color: c_int,
	scale: c_int,

	image: c_int,
} = undefined;

pos: Vec2f,
size: Vec2f,
pressed: bool = false,
hovered: bool = false,
onAction: gui.Callback,
child: GuiComponent,

pub fn __init() void {
	shader = Shader.initAndGetUniforms("assets/cubyz/shaders/ui/button.vs", "assets/cubyz/shaders/ui/button.fs", "", &buttonUniforms);
	shader.bind();
	graphics.c.glUniform1i(buttonUniforms.image, 0);
	normalTextures = Textures.init("assets/cubyz/ui/button");
	hoveredTextures = Textures.init("assets/cubyz/ui/button_hovered");
	pressedTextures = Textures.init("assets/cubyz/ui/button_pressed");
}

pub fn __deinit() void {
	shader.deinit();
	normalTextures.deinit();
	hoveredTextures.deinit();
	pressedTextures.deinit();
}

fn defaultOnAction(_: usize) void {}

pub fn initText(pos: Vec2f, width: f32, text: []const u8, onAction: gui.Callback) *Button {
	const label = Label.init(undefined, width - 3*border, text, .center);
	const self = main.globalAllocator.create(Button);
	self.* = Button{
		.pos = pos,
		.size = Vec2f{width, label.size[1] + 3*border},
		.onAction = onAction,
		.child = label.toComponent(),
	};
	return self;
}

pub fn initIcon(pos: Vec2f, iconSize: Vec2f, iconTexture: Texture, hasShadow: bool, onAction: gui.Callback) *Button {
	const icon = Icon.init(undefined, iconSize, iconTexture, hasShadow);
	const self = main.globalAllocator.create(Button);
	self.* = Button{
		.pos = pos,
		.size = icon.size + @as(Vec2f, @splat(3*border)),
		.onAction = onAction,
		.child = icon.toComponent(),
	};
	return self;
}

pub fn deinit(self: *const Button) void {
	self.child.deinit();
	main.globalAllocator.destroy(self);
}

pub fn toComponent(self: *Button) GuiComponent {
	return .{.button = self};
}

pub fn updateHovered(self: *Button, _: Vec2f) void {
	self.hovered = true;
}

pub fn mainButtonPressed(self: *Button, _: Vec2f) void {
	self.pressed = true;
}

pub fn mainButtonReleased(self: *Button, mousePosition: Vec2f) void {
	if(self.pressed) {
		self.pressed = false;
		if(GuiComponent.contains(self.pos, self.size, mousePosition)) {
			self.onAction.run();
		}
	}
}

pub fn render(self: *Button, mousePosition: Vec2f) void {
	const textures = if(self.pressed)
		pressedTextures
	else if(GuiComponent.contains(self.pos, self.size, mousePosition) and self.hovered)
		hoveredTextures
	else
		normalTextures;
	draw.setColor(0xff000000);
	textures.texture.bindTo(0);
	shader.bind();
	self.hovered = false;
	draw.customShadedRect(buttonUniforms, self.pos + Vec2f{2, 2}, self.size - Vec2f{4, 4});
	{ // Draw the outline using the 9-slice texture.
		const cornerSize = (textures.outlineTextureSize - Vec2f{1, 1});
		const cornerSizeUV = (textures.outlineTextureSize - Vec2f{1, 1})/Vec2f{2, 2}/textures.outlineTextureSize;
		const lowerTexture = (textures.outlineTextureSize - Vec2f{1, 1})/Vec2f{2, 2}/textures.outlineTextureSize;
		const upperTexture = (textures.outlineTextureSize + Vec2f{1, 1})/Vec2f{2, 2}/textures.outlineTextureSize;
		textures.outlineTexture.bindTo(0);
		draw.setColor(0xffffffff);
		// Corners:
		graphics.draw.boundSubImage(self.pos + Vec2f{0, 0}, cornerSize, .{0, 0}, cornerSizeUV);
		graphics.draw.boundSubImage(self.pos + Vec2f{self.size[0], 0} - Vec2f{cornerSize[0], 0}, cornerSize, .{upperTexture[0], 0}, cornerSizeUV);
		graphics.draw.boundSubImage(self.pos + Vec2f{0, self.size[1]} - Vec2f{0, cornerSize[1]}, cornerSize, .{0, upperTexture[1]}, cornerSizeUV);
		graphics.draw.boundSubImage(self.pos + self.size - cornerSize, cornerSize, upperTexture, cornerSizeUV);
		// Edges:
		graphics.draw.boundSubImage(self.pos + Vec2f{cornerSize[0], 0}, Vec2f{self.size[0] - 2*cornerSize[0], cornerSize[1]}, .{lowerTexture[0], 0}, .{upperTexture[0] - lowerTexture[0], cornerSizeUV[1]});
		graphics.draw.boundSubImage(self.pos + Vec2f{cornerSize[0], self.size[1] - cornerSize[1]}, Vec2f{self.size[0] - 2*cornerSize[0], cornerSize[1]}, .{lowerTexture[0], upperTexture[1]}, .{upperTexture[0] - lowerTexture[0], cornerSizeUV[1]});
		graphics.draw.boundSubImage(self.pos + Vec2f{0, cornerSize[1]}, Vec2f{cornerSize[0], self.size[1] - 2*cornerSize[1]}, .{0, lowerTexture[1]}, .{cornerSizeUV[0], upperTexture[1] - lowerTexture[1]});
		graphics.draw.boundSubImage(self.pos + Vec2f{self.size[0] - cornerSize[0], cornerSize[1]}, Vec2f{cornerSize[0], self.size[1] - 2*cornerSize[1]}, .{upperTexture[0], lowerTexture[1]}, .{cornerSizeUV[0], upperTexture[1] - lowerTexture[1]});
	}
	const textPos = self.pos + self.size/@as(Vec2f, @splat(2.0)) - self.child.size()/@as(Vec2f, @splat(2.0));
	self.child.mutPos().* = textPos;
	self.child.render(mousePosition - self.pos);
}
