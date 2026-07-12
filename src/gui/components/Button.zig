const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
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
var disabledTextures: Textures = undefined;
pub var pipeline: graphics.Pipeline = undefined;
pub var buttonUniforms: struct {
	screen: c_int,
	start: c_int,
	size: c_int,
	color: c_int,
	scale: c_int,
} = undefined;

pos: Vec2f,
size: Vec2f,
disabled: bool = false,
pressed: bool = false,
hovered: bool = false,
hidden: bool = false,
onAction: main.callbacks.SimpleCallback,
child: GuiComponent,

pub fn globalInit() void {
	pipeline = graphics.Pipeline.init(
		"assets/cubyz/shaders/ui/button.vert",
		"assets/cubyz/shaders/ui/button.frag",
		"",
		&buttonUniforms,
		graphics.draw.SimpleVertex2D,
		&.{},
		.{.cullMode = .none},
		.{.depthTest = false, .depthWrite = false},
		.{.attachments = &.{.alphaBlending}},
	);
	normalTextures = Textures.init("assets/cubyz/ui/button");
	hoveredTextures = Textures.init("assets/cubyz/ui/button_hovered");
	pressedTextures = Textures.init("assets/cubyz/ui/button_pressed");
	disabledTextures = Textures.init("assets/cubyz/ui/button_disabled");
}

pub fn globalDeinit() void {
	pipeline.deinit();
	normalTextures.deinit();
	hoveredTextures.deinit();
	pressedTextures.deinit();
}

fn defaultOnAction(_: usize) void {}

const Options = struct {
	onAction: main.callbacks.SimpleCallback = .{},
	disabled: bool = false,
	hidden: bool = false,
};

pub fn initText(pos: Vec2f, width: f32, text: []const u8, options: Options) *Button {
	const label = Label.init(undefined, width - 3*border, text, .center);
	const self = main.globalAllocator.create(Button);
	self.* = Button{
		.pos = pos,
		.size = Vec2f{width, label.size[1] + 3*border},
		.onAction = options.onAction,
		.child = label.toComponent(),
		.disabled = options.disabled,
		.hidden = options.hidden,
	};
	return self;
}

pub fn initIcon(pos: Vec2f, iconSize: Vec2f, iconTexture: Texture, options: Options) *Button {
	const icon = Icon.init(undefined, iconSize, iconTexture);
	const self = main.globalAllocator.create(Button);
	self.* = Button{
		.pos = pos,
		.size = icon.size + @as(Vec2f, @splat(3*border)),
		.onAction = options.onAction,
		.child = icon.toComponent(),
		.disabled = options.disabled,
		.hidden = options.hidden,
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

pub fn updateHovered(self: *Button, _: Vec2f) main.callbacks.Result {
	self.hovered = true;
	return .handled;
}

pub fn mainButtonPressed(self: *Button, _: Vec2f) main.callbacks.Result {
	if (!self.disabled) self.pressed = true;
	return .handled;
}

pub fn mainButtonReleased(self: *Button, mousePosition: Vec2f) void {
	if (self.pressed) {
		self.pressed = false;
		if (GuiComponent.contains(self.pos, self.size, mousePosition)) {
			self.onAction.run();
		}
	}
}

pub fn render(self: *Button, mousePosition: Vec2f) void {
	if (!self.hidden) renderButton(self, mousePosition);

	const oldColor = draw.setColor(if (self.disabled) 0xff808080 else 0xffffffff);
	defer draw.restoreColor(oldColor);
	const textPos = self.pos + self.size/@as(Vec2f, @splat(2.0)) - self.child.size()/@as(Vec2f, @splat(2.0));
	self.child.mutPos().* = textPos;
	if (self.hidden) self.child.mutSize().* = self.size;
	self.child.render(mousePosition - self.pos);
}

pub fn renderButton(self: *Button, mousePosition: Vec2f) void {
	const textures = blk: {
		if (self.disabled) break :blk disabledTextures;
		if (self.pressed) break :blk pressedTextures;
		if (GuiComponent.contains(self.pos, self.size, mousePosition) and self.hovered) {
			break :blk hoveredTextures;
		}
		break :blk normalTextures;
	};
	{
		textures.texture.bindTo(0);
		pipeline.bind(draw.getScissor());
		self.hovered = false;
		draw.customShadedRect(buttonUniforms, self.pos + Vec2f{2, 2}, self.size - Vec2f{4, 4});
	}

	const cornerSize = (textures.outlineTextureSize - Vec2f{1, 1})/Vec2f{2, 2};

	textures.outlineTexture.bindTo(0);
	graphics.draw.bound9SliceImage(self.pos, self.size, textures.outlineTextureSize, cornerSize, 2);
}
