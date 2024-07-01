const std = @import("std");

const main = @import("root");
const graphics = main.graphics;
const draw = graphics.draw;
const Shader = graphics.Shader;
const Texture = graphics.Texture;
const settings = main.settings;
const vec = main.vec;
const Vec2f = vec.Vec2f;
const Vec2i = vec.Vec2i;

const gui = @import("gui.zig");
const GuiComponent = gui.GuiComponent;

const GuiWindow = @This();

pub const AttachmentPoint = enum(u8) {
	lower = 0,
	middle = 1,
	upper = 2,
};

const OrientationLine = struct {
	pos: f32,
	start: f32,
	end: f32,
};

const RelativePosition = union(enum) {
	ratio: f32,
	attachedToFrame: struct {
		selfAttachmentPoint: AttachmentPoint,
		otherAttachmentPoint: AttachmentPoint,
	},
	relativeToWindow: struct {
		reference: *GuiWindow,
		ratio: f32,
	},
	attachedToWindow: struct {
		reference: *GuiWindow,
		selfAttachmentPoint: AttachmentPoint,
		otherAttachmentPoint: AttachmentPoint,
	},
};

const snapDistance = 3;

pos: Vec2f = undefined,
size: Vec2f = undefined,
contentSize: Vec2f,
scale: f32 = 1,
spacing: f32 = 0,
relativePosition: [2]RelativePosition = .{.{.ratio = 0.5}, .{.ratio = 0.5}},
id: []const u8 = undefined,
rootComponent: ?GuiComponent = null,
showTitleBar: bool = true,
hasBackground: bool = true,
hideIfMouseIsGrabbed: bool = true, // TODO: Allow the user to change this with a button, to for example leave the inventory open while playing.
closeIfMouseIsGrabbed: bool = false,
isHud: bool = false,

// TODO: Option to disable the close button for certain windows that cannot be reopened.

/// Called every frame.
renderFn: *const fn()void = &defaultFunction,
/// Called every frame before rendering.
updateFn: *const fn()void = &defaultFunction,
/// Called every frame for the currently selected window.
updateSelectedFn: *const fn()void = &defaultFunction,
/// Called every frame for the currently hovered window.
updateHoveredFn: *const fn()void = &defaultFunction,

onOpenFn: *const fn()void = &defaultFunction,

onCloseFn: *const fn()void = &defaultFunction,

var grabbedWindow: *const GuiWindow = undefined;
var grabPosition: ?Vec2f = null;
var selfPositionWhenGrabbed: Vec2f = undefined;

var backgroundTexture: Texture = undefined;
var titleTexture: Texture = undefined;
var closeTexture: Texture = undefined;
var zoomInTexture: Texture = undefined;
var zoomOutTexture: Texture = undefined;
var shader: Shader = undefined;
var windowUniforms: struct {
	screen: c_int,
	start: c_int,
	size: c_int,
	color: c_int,
	scale: c_int,

	image: c_int,
	randomOffset: c_int,
} = undefined;
pub var borderShader: Shader = undefined;
pub var borderUniforms: struct {
	screen: c_int,
	start: c_int,
	size: c_int,
	color: c_int,
	scale: c_int,
	effectLength: c_int,
} = undefined;

pub fn __init() void {
	shader = Shader.initAndGetUniforms("assets/cubyz/shaders/ui/button.vs", "assets/cubyz/shaders/ui/button.fs", &windowUniforms);
	shader.bind();
	graphics.c.glUniform1i(windowUniforms.image, 0);
	borderShader = Shader.initAndGetUniforms("assets/cubyz/shaders/ui/window_border.vs", "assets/cubyz/shaders/ui/window_border.fs", &borderUniforms);
	borderShader.bind();

	backgroundTexture = Texture.initFromFile("assets/cubyz/ui/window_background.png");
	titleTexture = Texture.initFromFile("assets/cubyz/ui/window_title.png");
	closeTexture = Texture.initFromFile("assets/cubyz/ui/window_close.png");
	zoomInTexture = Texture.initFromFile("assets/cubyz/ui/window_zoom_in.png");
	zoomOutTexture = Texture.initFromFile("assets/cubyz/ui/window_zoom_out.png");
}

pub fn __deinit() void {
	shader.deinit();
	backgroundTexture.deinit();
	titleTexture.deinit();
}

pub fn defaultFunction() void {}

pub fn mainButtonPressed(self: *const GuiWindow, mousePosition: Vec2f) void {
	const scaledMousePos = (mousePosition - self.pos)/@as(Vec2f, @splat(self.scale));
	if(scaledMousePos[1] < 16 and (self.showTitleBar or gui.reorderWindows)) {
		grabbedWindow = self;
		grabPosition = mousePosition;
		selfPositionWhenGrabbed = self.pos;
	} else {
		if(self.rootComponent) |*component| {
			if(GuiComponent.contains(component.pos(), component.size(), scaledMousePos)) {
				component.mainButtonPressed(scaledMousePos);
			}
		}
	}
}

pub fn mainButtonReleased(self: *GuiWindow, mousePosition: Vec2f) void {
	if(grabPosition != null and @reduce(.And, grabPosition.? == mousePosition) and grabbedWindow == self) {
		if(self.showTitleBar or gui.reorderWindows) {
			if(mousePosition[0] - self.pos[0] > self.size[0] - 48*self.scale) {
				if(mousePosition[0] - self.pos[0] > self.size[0] - 32*self.scale) {
					if(mousePosition[0] - self.pos[0] > self.size[0] - 16*self.scale) {
						// Close
						gui.closeWindow(self);
						return;
					} else {
						// Zoom out
						if(self.scale > 1) {
							self.scale -= 0.5;
						} else {
							self.scale -= 0.25;
						}
						self.scale = @max(self.scale, 0.25);
						gui.updateWindowPositions();
					}
				} else {
					// Zoom in
					if(self.scale >= 1) {
						self.scale += 0.5;
					} else {
						self.scale += 0.25;
					}
					gui.updateWindowPositions();
				}
			}
		}
	}
	grabPosition = null;
	grabbedWindow = undefined;
	if(self.rootComponent) |*component| {
		component.mainButtonReleased((mousePosition - self.pos)/@as(Vec2f, @splat(self.scale)));
	}
}

fn detectCycles(self: *GuiWindow, other: *GuiWindow) bool {
	for(0..2) |xy| {
		var win: ?*GuiWindow = other;
		while(win) |_win| {
			if(win == self) return true;
			switch(_win.relativePosition[xy]) {
				.ratio => {
					win = null;
				},
				.attachedToFrame => {
					win = null;
				},
				.relativeToWindow => |relativeToWindow| {
					win = relativeToWindow.reference;
				},
				.attachedToWindow => |attachedToWindow| {
					win = attachedToWindow.reference;
				},
			}
		}
	}
	return false;
}

fn snapToOtherWindow(self: *GuiWindow) void {
	for(&self.relativePosition, 0..) |*relPos, i| {
		var minDist: f32 = snapDistance;
		var minWindow: ?*GuiWindow = null;
		var selfAttachment: AttachmentPoint = undefined;
		var otherAttachment: AttachmentPoint = undefined;
		for(gui.openWindows.items) |other| {
			// Check if they touch:
			const start = @max(self.pos[i^1], other.pos[i^1]);
			const end = @min(self.pos[i^1] + self.size[i^1], other.pos[i^1] + other.size[i^1]);
			if(start >= end) continue;
			if(detectCycles(self, other)) continue;

			const dist1 = @abs(self.pos[i] - other.pos[i] - other.size[i]);
			if(dist1 < minDist) {
				minDist = dist1;
				minWindow = other;
				selfAttachment = .lower;
				otherAttachment = .upper;
			}
			const dist2 = @abs(self.pos[i] + self.size[i] - other.pos[i]);
			if(dist2 < minDist) {
				minDist = dist2;
				minWindow = other;
				selfAttachment = .upper;
				otherAttachment = .lower;
			}
		}
		if(minWindow) |other| {
			relPos.* = .{.attachedToWindow = .{.reference = other, .selfAttachmentPoint = selfAttachment, .otherAttachmentPoint = otherAttachment}};
		}
	}
}

fn positionRelativeToFrame(self: *GuiWindow) void {
	const windowSize = main.Window.getWindowSize()/@as(Vec2f, @splat(gui.scale));
	for(&self.relativePosition, 0..) |*relPos, i| {
		// Snap to the center:
		if(@abs(self.pos[i] + self.size[i] - windowSize[i]/2) <= snapDistance) {
			relPos.* = .{.attachedToFrame = .{
				.selfAttachmentPoint = .upper,
				.otherAttachmentPoint = .middle,
			}};
		} else if(@abs(self.pos[i] + self.size[i]/2 - windowSize[i]/2) <= snapDistance) {
			relPos.* = .{.attachedToFrame = .{
				.selfAttachmentPoint = .middle,
				.otherAttachmentPoint = .middle,
			}};
		} else if(@abs(self.pos[i] - windowSize[i]/2) <= snapDistance) {
			relPos.* = .{.attachedToFrame = .{
				.selfAttachmentPoint = .lower,
				.otherAttachmentPoint = .middle,
			}};
		} else {
			var ratio: f32 = (self.pos[i] + self.size[i]/2)/windowSize[i];
			if(self.pos[i] <= 0) {
				ratio = 0;
			} else if(self.pos[i] + self.size[i] >= windowSize[i]) {
				ratio = 1;
			}
			relPos.* = .{.ratio = ratio};
		}
	}
}

fn positionRelativeToConnectedWindow(self: *GuiWindow, other: *GuiWindow, i: usize) void {
	const otherSize = other.size;
	const relPos = &self.relativePosition[i];
	// Snap to the center:
	if(@abs(self.pos[i] + self.size[i] - (other.pos[i] + otherSize[i]/2)) <= snapDistance) {
		relPos.* = .{.attachedToWindow = .{
			.reference = other,
			.selfAttachmentPoint = .upper,
			.otherAttachmentPoint = .middle,
		}};
	} else if(@abs(self.pos[i] + self.size[i]/2 - (other.pos[i] + otherSize[i]/2)) <= snapDistance) {
		relPos.* = .{.attachedToWindow = .{
			.reference = other,
			.selfAttachmentPoint = .middle,
			.otherAttachmentPoint = .middle,
		}};
	} else if(@abs(self.pos[i] - (other.pos[i] + otherSize[i]/2)) <= snapDistance) {
		relPos.* = .{.attachedToWindow = .{
			.reference = other,
			.selfAttachmentPoint = .lower,
			.otherAttachmentPoint = .middle,
		}};
	// Snap to the edges:
	} else if(@abs(self.pos[i] - other.pos[i]) <= snapDistance) {
		relPos.* = .{.attachedToWindow = .{
			.reference = other,
			.selfAttachmentPoint = .lower,
			.otherAttachmentPoint = .lower,
		}};
	} else if(@abs(self.pos[i] + self.size[i] - (other.pos[i] + otherSize[i])) <= snapDistance) {
		relPos.* = .{.attachedToWindow = .{
			.reference = other,
			.selfAttachmentPoint = .upper,
			.otherAttachmentPoint = .upper,
		}};
	} else {
		relPos.* = .{.relativeToWindow = .{
			.reference = other,
			.ratio = (self.pos[i] + self.size[i]/2 - other.pos[i])/otherSize[i]
		}};
	}
}

pub fn update(self: *GuiWindow) void {
	self.updateFn();
}

pub fn updateSelected(self: *GuiWindow, mousePosition: Vec2f) void {
	self.updateSelectedFn();
	const windowSize = main.Window.getWindowSize()/@as(Vec2f, @splat(gui.scale));
	if(self == grabbedWindow and (gui.reorderWindows or self.showTitleBar)) if(grabPosition) |_grabPosition| {
		self.relativePosition[0] = .{.ratio = undefined};
		self.relativePosition[1] = .{.ratio = undefined};
		self.pos = (mousePosition - _grabPosition) + selfPositionWhenGrabbed;
		self.snapToOtherWindow();
		if(self.relativePosition[0] == .ratio and self.relativePosition[1] == .ratio) {
			self.positionRelativeToFrame();
		} else if(self.relativePosition[0] == .ratio) {
			self.positionRelativeToConnectedWindow(self.relativePosition[1].attachedToWindow.reference, 0);
		} else if(self.relativePosition[1] == .ratio) {
			self.positionRelativeToConnectedWindow(self.relativePosition[0].attachedToWindow.reference, 1);
		}
		self.pos = @max(self.pos, Vec2f{0, 0});
		self.pos = @min(self.pos, windowSize - self.size);
		gui.updateWindowPositions();
	};
	if(self.rootComponent) |*component| {
		component.updateSelected();
	}
}

pub fn updateHovered(self: *GuiWindow, mousePosition: Vec2f) void {
	self.updateHoveredFn();
	if(self.rootComponent) |component| {
		if(GuiComponent.contains(component.pos(), component.size(), (mousePosition - self.pos)/@as(Vec2f, @splat(self.scale)))) {
			component.updateHovered((mousePosition - self.pos)/@as(Vec2f, @splat(self.scale)));
		}
	}
}

pub fn updateWindowPosition(self: *GuiWindow) void {
	self.size = self.contentSize*@as(Vec2f, @splat(self.scale));
	const windowSize = main.Window.getWindowSize()/@as(Vec2f, @splat(gui.scale));
	for(self.relativePosition, 0..) |relPos, i| {
		switch(relPos) {
			.ratio => |ratio| {
				self.pos[i] = windowSize[i]*ratio - self.size[i]/2;
			},
			.attachedToFrame => |attachedToFrame| {
				const otherPos = switch(attachedToFrame.otherAttachmentPoint) {
					.lower => 0,
					.middle => 0.5*windowSize[i],
					.upper => windowSize[i],
				};
				self.pos[i] = switch(attachedToFrame.selfAttachmentPoint) {
					.lower => otherPos,
					.middle => otherPos - 0.5*self.size[i],
					.upper => otherPos - self.size[i],
				};
			},
			.attachedToWindow => |attachedToWindow| {
				const other = attachedToWindow.reference;
				const otherPos = switch(attachedToWindow.otherAttachmentPoint) {
					.lower => other.pos[i],
					.middle => other.pos[i] + 0.5*other.size[i],
					.upper => other.pos[i] + other.size[i],
				};
				self.pos[i] = switch(attachedToWindow.selfAttachmentPoint) {
					.lower => otherPos,
					.middle => otherPos - 0.5*self.size[i],
					.upper => otherPos - self.size[i],
				};
			},
			.relativeToWindow => |relativeToWindow| {
				const other = relativeToWindow.reference;
				const otherSize = other.size[i];
				const otherPos = other.pos[i];
				self.pos[i] = otherPos + relativeToWindow.ratio*otherSize - self.size[i]/2;
			},
		}
	}
	self.pos = @floor(self.pos); // Prevent floating point inaccuracies (these can happen when resizing the window) from causing weird window positioning issues.
	self.pos[0] = @max(self.pos[0], 0);
	self.pos[1] = @min(self.pos[1], windowSize[1] - self.size[1]);
	self.pos[0] = @min(self.pos[0], windowSize[0] - self.size[0]);
	self.pos[1] = @max(self.pos[1], 0);
}

fn drawOrientationLines(self: *const GuiWindow) void {
	draw.setColor(0x80000000);
	const windowSize = main.Window.getWindowSize()/@as(Vec2f, @splat(gui.scale));
	for(self.relativePosition, 0..) |relPos, i| {
		switch(relPos) {
			.ratio, .relativeToWindow => {
				continue;
			},
			.attachedToFrame => |attachedToFrame| {
				const pos = switch(attachedToFrame.otherAttachmentPoint) {
					.lower => 0,
					.middle => 0.5*windowSize[i],
					.upper => windowSize[i],
				};
				if(i == 0) {
					draw.line(.{pos, 0}, .{pos, windowSize[i^1]});
				} else {
					draw.line(.{0, pos}, .{windowSize[i^1], pos});
				}
			},
			.attachedToWindow => |attachedToWindow| {
				const other = attachedToWindow.reference;
				const otherSize = other.size;
				const pos = switch(attachedToWindow.otherAttachmentPoint) {
					.lower => other.pos[i],
					.middle => other.pos[i] + 0.5*otherSize[i],
					.upper => other.pos[i] + otherSize[i],
				};
				const start = @min(self.pos[i^1], other.pos[i^1]);
				const end = @max(self.pos[i^1] + self.size[i^1], other.pos[i^1] + otherSize[i^1]);
				if(i == 0) {
					draw.line(.{pos, start}, .{pos, end});
				} else {
					draw.line(.{start, pos}, .{end, pos});
				}
			},
		}
	}
}

pub fn drawIcons(self: *const GuiWindow) void {
	draw.setColor(0xffffffff);
	closeTexture.render(.{self.size[0]/self.scale - 18, 0}, .{18, 18});
	zoomOutTexture.render(.{self.size[0]/self.scale - 36, 0}, .{18, 18});
	zoomInTexture.render(.{self.size[0]/self.scale - 54, 0}, .{18, 18});
}

pub fn render(self: *const GuiWindow, mousePosition: Vec2f) void {
	if(self.hideIfMouseIsGrabbed and main.Window.grabbed) return;
	const oldTranslation = draw.setTranslation(self.pos);
	const oldScale = draw.setScale(self.scale);
	if(self.hasBackground) {
		draw.setColor(0xff000000);
		shader.bind();
		backgroundTexture.bindTo(0);
		draw.customShadedRect(windowUniforms, .{0, 0}, self.size/@as(Vec2f, @splat(self.scale)));
	}
	self.renderFn();
	if(self.rootComponent) |*component| {
		component.render((mousePosition - self.pos)/@as(Vec2f, @splat(self.scale)));
	}
	if(self.showTitleBar or gui.reorderWindows) {
		shader.bind();
		titleTexture.bindTo(0);
		draw.setColor(0xff000000);
		draw.customShadedRect(windowUniforms, .{0, 0}, .{self.size[0]/self.scale, 18});
		self.drawIcons();
	}
	if(self.hasBackground or (!main.Window.grabbed and gui.reorderWindows)) {
		draw.setColor(0xff1d1d1d);
		draw.rectBorder(.{-2, -2}, self.size/@as(Vec2f, @splat(self.scale)) + Vec2f{4, 4}, 2.0);
	}
	draw.restoreTranslation(oldTranslation);
	draw.restoreScale(oldScale);
	if(self == grabbedWindow and (gui.reorderWindows or self.showTitleBar) and grabPosition != null) {
		self.drawOrientationLines();
	}
}