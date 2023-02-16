const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const graphics = main.graphics;
const draw = graphics.draw;
const settings = main.settings;
const vec = main.vec;
const Vec2f = vec.Vec2f;
const Vec2i = vec.Vec2i;

const gui = @import("gui.zig");
const GuiComponent = gui.GuiComponent;

const GuiWindow = @This();

const AttachmentPoint = enum {
	lower,
	middle,
	upper,
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

pos: Vec2f = undefined,
size: Vec2f = undefined,
contentSize: Vec2f,
scale: f32 = 1,
spacing: f32 = 0,
relativePosition: [2]RelativePosition = .{.{.ratio = 0.5}, .{.ratio = 0.5}},
showTitleBar: bool = true,
title: []const u8,
id: []const u8,
components: []GuiComponent,

/// Called every frame.
renderFn: *const fn()void,
/// Called every frame for the currently selected window.
updateFn: *const fn()void = &defaultFunction,

onOpenFn: *const fn()Allocator.Error!void = &defaultErrorFunction,

onCloseFn: *const fn()void = &defaultFunction,

var grabPosition: ?Vec2f = null;
var selfPositionWhenGrabbed: Vec2f = undefined;

pub fn defaultFunction() void {}
pub fn defaultErrorFunction() Allocator.Error!void {}

pub fn mainButtonPressed(self: *const GuiWindow) void {
	const scale = @floor(settings.guiScale*self.scale); // TODO
	var mousePosition = main.Window.getMousePosition();
	mousePosition -= self.pos;
	mousePosition /= @splat(2, scale);
	if(mousePosition[1] < 16) {
		grabPosition = main.Window.getMousePosition();
		selfPositionWhenGrabbed = self.pos;
	} else {
		var selectedComponent: ?*GuiComponent = null;
		for(self.components) |*component| {
			if(component.contains(mousePosition)) {
				selectedComponent = component;
			}
		}
		if(selectedComponent) |component| {
			component.mainButtonPressed();
		}
	}
}

pub fn mainButtonReleased(self: *const GuiWindow) void {
	grabPosition = null;
	const scale = @floor(settings.guiScale*self.scale); // TODO
	var mousePosition = main.Window.getMousePosition();
	mousePosition -= self.pos;
	mousePosition /= @splat(2, scale);
	for(self.components) |*component| {
		component.mainButtonReleased(mousePosition);
	}
}

fn snapToOtherWindow(self: *GuiWindow) void {
	const scale = @floor(settings.guiScale*self.scale); // TODO
	for(self.relativePosition) |*relPos, i| {
		var minDist: f32 = settings.guiScale*2;
		var minWindow: ?*GuiWindow = null;
		var selfAttachment: AttachmentPoint = undefined;
		var otherAttachment: AttachmentPoint = undefined;
		outer: for(gui.openWindows.items) |other| {
			// Check if they touch:
			const start = @max(self.pos[i^1], other.pos[i^1]);
			const end = @min(self.pos[i^1] + self.size[i^1]*scale, other.pos[i^1] + other.size[i^1]*@floor(settings.guiScale*other.scale));
			if(start >= end) continue;
			// Detect cycles:
			var win: ?*GuiWindow = other;
			while(win) |_win| {
				if(win == self) continue :outer;
				switch(_win.relativePosition[i]) {
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

			const dist1 = @fabs(self.pos[i] - other.pos[i] - other.size[i]*@floor(settings.guiScale*other.scale)); // TODO: scale
			if(dist1 < minDist) {
				minDist = dist1;
				minWindow = other;
				selfAttachment = .lower;
				otherAttachment = .upper;
			}
			const dist2 = @fabs(self.pos[i] + self.size[i]*scale - other.pos[i]);
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
	const scale = @floor(settings.guiScale*self.scale); // TODO
	const windowSize = main.Window.getWindowSize();
	for(self.relativePosition) |*relPos, i| {
		// Snap to the center:
		if(@fabs(self.pos[i] + self.size[i]*scale - windowSize[i]/2) <= settings.guiScale*2) {
			relPos.* = .{.attachedToFrame = .{
				.selfAttachmentPoint = .upper,
				.otherAttachmentPoint = .middle,
			}};
		} else if(@fabs(self.pos[i] + self.size[i]*scale/2 - windowSize[i]/2) <= settings.guiScale*2) {
			relPos.* = .{.attachedToFrame = .{
				.selfAttachmentPoint = .middle,
				.otherAttachmentPoint = .middle,
			}};
		} else if(@fabs(self.pos[i] - windowSize[i]/2) <= settings.guiScale*2) {
			relPos.* = .{.attachedToFrame = .{
				.selfAttachmentPoint = .lower,
				.otherAttachmentPoint = .middle,
			}};
		} else {
			var ratio: f32 = (self.pos[i] + self.size[i]*scale/2)/windowSize[i];
			if(self.pos[i] <= 0) {
				ratio = 0;
			} else if(self.pos[i] + self.size[i]*scale >= windowSize[i]) {
				ratio = 1;
			}
			relPos.* = .{.ratio = ratio};
		}
	}
}

fn positionRelativeToConnectedWindow(self: *GuiWindow, other: *GuiWindow, i: usize) void {
	const scale = @floor(settings.guiScale*self.scale); // TODO
	const otherSize = other.size*@splat(2, @floor(settings.guiScale*other.scale)); // TODO: scale
	const relPos = &self.relativePosition[i];
	// Snap to the center:
	if(@fabs(self.pos[i] + self.size[i]*scale - (other.pos[i] + otherSize[i]/2)) <= settings.guiScale*2) {
		relPos.* = .{.attachedToWindow = .{
			.reference = other,
			.selfAttachmentPoint = .upper,
			.otherAttachmentPoint = .middle,
		}};
	} else if(@fabs(self.pos[i] + self.size[i]*scale/2 - (other.pos[i] + otherSize[i]/2)) <= settings.guiScale*2) {
		relPos.* = .{.attachedToWindow = .{
			.reference = other,
			.selfAttachmentPoint = .middle,
			.otherAttachmentPoint = .middle,
		}};
	} else if(@fabs(self.pos[i] - (other.pos[i] + otherSize[i]/2)) <= settings.guiScale*2) {
		relPos.* = .{.attachedToWindow = .{
			.reference = other,
			.selfAttachmentPoint = .lower,
			.otherAttachmentPoint = .middle,
		}};
	// Snap to the edges:
	} else if(@fabs(self.pos[i] - other.pos[i]) <= settings.guiScale*2) {
		relPos.* = .{.attachedToWindow = .{
			.reference = other,
			.selfAttachmentPoint = .lower,
			.otherAttachmentPoint = .lower,
		}};
	} else if(@fabs(self.pos[i] + self.size[i]*scale - (other.pos[i] + otherSize[i])) <= settings.guiScale*2) {
		relPos.* = .{.attachedToWindow = .{
			.reference = other,
			.selfAttachmentPoint = .upper,
			.otherAttachmentPoint = .upper,
		}};
	} else {
		self.relativePosition[i] = .{.relativeToWindow = .{
			.reference = other,
			.ratio = (self.pos[i] + self.size[i]*scale/2 - other.pos[i])/otherSize[i]
		}};
	}
}

pub fn update(self: *GuiWindow) !void {
	const scale = @floor(settings.guiScale*self.scale); // TODO
	const mousePosition = main.Window.getMousePosition();
	const windowSize = main.Window.getWindowSize();
	if(grabPosition) |_grabPosition| {
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
		self.pos = @min(self.pos, windowSize - self.size*@splat(2, scale));
		gui.updateWindowPositions();
	}
	for(self.components) |*component| {
		component.update();
	}
}

pub fn updateWindowPosition(self: *GuiWindow) void {
	const scale = @floor(settings.guiScale*self.scale); // TODO
	const windowSize = main.Window.getWindowSize();
	for(self.relativePosition) |relPos, i| {
		switch(relPos) {
			.ratio => |ratio| {
				self.pos[i] = windowSize[i]*ratio - self.size[i]*scale/2;
				self.pos[i] = @max(self.pos[i], 0);
				self.pos[i] = @min(self.pos[i], windowSize[i] - self.size[i]*scale);
			},
			.attachedToFrame => |attachedToFrame| {
				const otherPos = switch(attachedToFrame.otherAttachmentPoint) {
					.lower => 0,
					.middle => 0.5*windowSize[i],
					.upper => windowSize[i],
				};
				self.pos[i] = switch(attachedToFrame.selfAttachmentPoint) {
					.lower => otherPos,
					.middle => otherPos - 0.5*self.size[i]*scale,
					.upper => otherPos - self.size[i]*scale,
				};
			},
			.attachedToWindow => |attachedToWindow| {
				const other = attachedToWindow.reference;
				const otherPos = switch(attachedToWindow.otherAttachmentPoint) {
					.lower => other.pos[i],
					.middle => other.pos[i] + 0.5*other.size[i]*@floor(settings.guiScale*other.scale), // TODO: scale
					.upper => other.pos[i] + other.size[i]*@floor(settings.guiScale*other.scale), // TODO: scale
				};
				self.pos[i] = switch(attachedToWindow.selfAttachmentPoint) {
					.lower => otherPos,
					.middle => otherPos - 0.5*self.size[i]*scale,
					.upper => otherPos - self.size[i]*scale,
				};
			},
			.relativeToWindow => |relativeToWindow| {
				const other = relativeToWindow.reference;
				const otherSize = other.size[i]*@floor(settings.guiScale*other.scale); // TODO: scale
				const otherPos = other.pos[i];
				self.pos[i] = otherPos + relativeToWindow.ratio*otherSize - self.size[i]*scale/2;
			},
		}
	}
}

fn drawOrientationLines(self: *const GuiWindow) void {
	const scale = @floor(settings.guiScale*self.scale); // TODO
	draw.setColor(0x80000000);
	const windowSize = main.Window.getWindowSize();
	for(self.relativePosition) |relPos, i| {
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
				const otherSize = other.size*@splat(2, @floor(settings.guiScale*other.scale)); // TODO: scale
				const pos = switch(attachedToWindow.otherAttachmentPoint) {
					.lower => other.pos[i],
					.middle => other.pos[i] + 0.5*otherSize[i],
					.upper => other.pos[i] + otherSize[i],
				};
				const start = @min(self.pos[i^1], other.pos[i^1]);
				const end = @max(self.pos[i^1] + self.size[i^1]*scale, other.pos[i^1] + otherSize[i^1]);
				if(i == 0) {
					draw.line(.{pos, start}, .{pos, end});
				} else {
					draw.line(.{start, pos}, .{end, pos});
				}
			},
		}
	}
}

pub fn render(self: *const GuiWindow) !void {
	const scale = @floor(settings.guiScale*self.scale); // TODO
	draw.setColor(0xff808080);
	draw.rect(self.pos, self.size*@splat(2, scale));
	if(self.showTitleBar) {
		var text = try graphics.TextBuffer.init(main.threadAllocator, self.title, .{}, false);
		defer text.deinit();
		const titleDimension = try text.calculateLineBreaks(16*scale, self.size[0]*scale);
		if(self == gui.selectedWindow) {
			draw.setColor(0xff80b080);
		} else {
			draw.setColor(0xffb08080);
		}
		draw.rect(self.pos, Vec2f{self.size[0]*scale, titleDimension[1]});
		try text.render(self.pos[0] + self.size[0]*scale/2 - titleDimension[0]/2, self.pos[1], 16*scale);

	}
	var mousePosition = main.Window.getMousePosition();
	mousePosition -= self.pos;
	mousePosition /= @splat(2, scale);
	const oldTranslation = draw.setTranslation(self.pos);
	const oldScale = draw.setScale(scale);
	for(self.components) |*component| {
		try component.render(mousePosition);
	}
	draw.restoreTranslation(oldTranslation);
	draw.restoreScale(oldScale);
	if(self == gui.selectedWindow and grabPosition != null) {
		self.drawOrientationLines();
	}
}