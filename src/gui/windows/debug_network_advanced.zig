const std = @import("std");

const main = @import("root");
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const network = main.network;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const GuiComponent = gui.GuiComponent;

pub var window = GuiWindow {
	.relativePosition = .{
		.{ .attachedToFrame = .{.selfAttachmentPoint = .middle, .otherAttachmentPoint = .middle} },
		.{ .attachedToFrame = .{.selfAttachmentPoint = .upper, .otherAttachmentPoint = .upper} },
	},
	.contentSize = Vec2f{192, 128},
	.isHud = false,
	.showTitleBar = false,
	.hasBackground = false,
	.hideIfMouseIsGrabbed = false,
};

fn renderConnectionData(conn: *main.network.Connection, y: *f32) void {
	conn.mutex.lock();
	defer conn.mutex.unlock();
	var unconfirmed: usize = 0;
	for(conn.unconfirmedPackets.items) |packet| {
		unconfirmed += packet.data.len;
	}
	var waiting: usize = 0;
	{
		var i = conn.packetQueue.startIndex;
		while(i != conn.packetQueue.endIndex) : (i = (i + 1) & conn.packetQueue.mask) {
			const packet = conn.packetQueue.mem[i];
			waiting += packet.data.len;
		}
	}
	draw.print("Bandwidth: {d:.0} kiB/s", .{1.0e9/conn.congestionControl_inversebandWidth/1024.0}, 0, y.*, 8, .left);
	y.* += 8;
	draw.print("Waiting in queue: {} kiB", .{waiting >> 10}, 0, y.*, 8, .left);
	y.* += 8;
	draw.print("Sent but not confirmed: {} kiB", .{unconfirmed >> 10}, 0, y.*, 8, .left);
	y.* += 8;
}

pub fn render() void {
	draw.setColor(0xffffffff);
	var y: f32 = 0;
	if(main.game.world != null) {
		draw.print("Client", .{}, 0, y, 8, .left);
		y += 8;
		renderConnectionData(main.game.world.?.conn, &y);
	}
	if(main.server.world != null) {
		const userList = main.server.getUserListAndIncreaseRefCount(main.stackAllocator);
		defer main.server.freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
		for(userList) |user| {
			draw.print("{s}", .{user.name}, 0, y, 8, .left);
			y += 8;
			renderConnectionData(user.conn, &y);
		}
	}
	if(window.size[1] != y) {
		window.size[1] = y;
		window.updateWindowPosition();
	}
}