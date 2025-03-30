const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const Vec2f = main.vec.Vec2f;
const TaskType = main.utils.ThreadPool.TaskType;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const GuiComponent = gui.GuiComponent;

pub fn onOpen() void {
	main.threadPool.performance.clear();
}

pub var window = GuiWindow{
	.relativePosition = .{
		.{.attachedToFrame = .{.selfAttachmentPoint = .lower, .otherAttachmentPoint = .lower}},
		.{.attachedToFrame = .{.selfAttachmentPoint = .lower, .otherAttachmentPoint = .lower}},
	},
	.contentSize = Vec2f{128, 16},
	.isHud = false,
	.showTitleBar = false,
	.hasBackground = false,
	.hideIfMouseIsGrabbed = false,
};

pub fn render() void {
	draw.setColor(0xffffffff);
	var y: f32 = 0;
	const fpsCapText = if(main.settings.fpsCap) |fpsCap| std.fmt.allocPrint(main.stackAllocator.allocator, " (limit: {d:.0} Hz)", .{fpsCap}) catch unreachable else "";
	defer main.stackAllocator.allocator.free(fpsCapText);
	const fpsLimit = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}{s}", .{
		fpsCapText,
		if(main.settings.vsync) " (vsync)" else "",
	}) catch unreachable;
	defer main.stackAllocator.allocator.free(fpsLimit);
	draw.print("fps: {d:.0} Hz{s}", .{1.0/main.lastDeltaTime.load(.monotonic), fpsLimit}, 0, y, 8, .left);
	y += 8;
	draw.print("frameTime: {d:.1} ms", .{main.lastFrameTime.load(.monotonic)*1000.0}, 0, y, 8, .left);
	y += 8;
	draw.print("window size: {}×{}", .{main.Window.width, main.Window.height}, 0, y, 8, .left);
	y += 8;
	if(main.game.world != null) {
		const player = main.game.Player;
		draw.print("Pos: {d:.1}", .{player.getPosBlocking()}, 0, y, 8, .left);
		y += 8;
		draw.print("Gamemode: {} IsFlying: {} IsGhost: {} HyperSpeed: {}", .{
			player.gamemode.load(.unordered),
			player.isFlying.load(.unordered),
			player.isGhost.load(.unordered),
			player.hyperSpeed.load(.unordered),
		}, 0, y, 8, .left);
		y += 8;
		draw.print("OnGround: {} JumpCooldown: {d:.3} JumpCoyote: {d:.3}", .{
			player.onGround,
			player.jumpCooldown,
			@max(0, player.getJumpCoyoteBlocking()),
		}, 0, y, 8, .left);
		y += 8;
		draw.print("Velocity: {d:.1}", .{player.getVelBlocking()}, 0, y, 8, .left);
		y += 8;
		draw.print("EyePos: {d:.1} EyeVelocity: {d:.1} EyeCoyote: {d:.3}", .{player.getEyePosBlocking(), player.getEyeVelBlocking(), @max(0, player.getEyeCoyoteBlocking())}, 0, y, 8, .left);
		y += 8;
		draw.print("Game Time: {}", .{main.game.world.?.gameTime.load(.monotonic)}, 0, y, 8, .left);
		y += 8;
		draw.print("Queue size: {}", .{main.threadPool.queueSize()}, 0, y, 8, .left);
		y += 8;
		const perf = main.threadPool.performance.read();
		const values = comptime std.enums.values(TaskType);
		var totalUtime: i64 = 0;
		for(values) |task|
			totalUtime += perf.utime[@intFromEnum(task)];
		for(values) |t| {
			const name = @tagName(t);
			const i = @intFromEnum(t);
			const taskTime = @divFloor(perf.utime[i], @max(1, perf.tasks[i]));
			const relativeTime = 100.0*@as(f32, @floatFromInt(perf.utime[i]))/@as(f32, @floatFromInt(totalUtime));
			draw.print("    {s}: {} µs/task ({d:.1}%)", .{name, taskTime, relativeTime}, 0, y, 8, .left);
			y += 8;
		}
		draw.print("Mesh Queue size: {}", .{main.renderer.mesh_storage.updatableList.items.len}, 0, y, 8, .left);
		y += 8;
		{
			const faceDataSize: usize = @sizeOf(main.renderer.chunk_meshing.FaceData);
			const size: usize = main.renderer.chunk_meshing.faceBuffer.capacity*faceDataSize;
			const used: usize = main.renderer.chunk_meshing.faceBuffer.used*faceDataSize;
			var largestFreeBlock: usize = 0;
			for(main.renderer.chunk_meshing.faceBuffer.freeBlocks.items) |freeBlock| {
				largestFreeBlock = @max(largestFreeBlock, freeBlock.len);
			}
			const fragmentation = size - used - largestFreeBlock*faceDataSize;
			draw.print("ChunkMesh memory: {} MiB / {} MiB (fragmentation: {} MiB)", .{used >> 20, size >> 20, fragmentation >> 20}, 0, y, 8, .left);
			y += 8;
		}
		{
			const lightDataSize: usize = @sizeOf(u32);
			const size: usize = main.renderer.chunk_meshing.lightBuffer.capacity*lightDataSize;
			const used: usize = main.renderer.chunk_meshing.lightBuffer.used*lightDataSize;
			var largestFreeBlock: usize = 0;
			for(main.renderer.chunk_meshing.lightBuffer.freeBlocks.items) |freeBlock| {
				largestFreeBlock = @max(largestFreeBlock, freeBlock.len);
			}
			const fragmentation = size - used - largestFreeBlock*lightDataSize;
			draw.print("Light memory: {} MiB / {} MiB (fragmentation: {} MiB)", .{used >> 20, size >> 20, fragmentation >> 20}, 0, y, 8, .left);
			y += 8;
		}
		{
			const biome = main.game.world.?.playerBiome.load(.monotonic);
			var tags = main.List(u8).init(main.stackAllocator);
			defer tags.deinit();
			inline for(comptime std.meta.fieldNames(main.server.terrain.biomes.Biome.GenerationProperties)) |name| {
				if(@field(biome.properties, name)) {
					if(tags.items.len != 0) tags.appendSlice(", ");
					tags.appendSlice(name);
				}
			}
			draw.print("Biome: {s}", .{biome.id}, 0, y, 8, .left);
			y += 8;
			draw.print("Biome Properties: {s}", .{tags.items}, 0, y, 8, .left);
			y += 8;
		}
		draw.print("Opaque faces: {}, Transparent faces: {}", .{main.renderer.chunk_meshing.quadsDrawn, main.renderer.chunk_meshing.transparentQuadsDrawn}, 0, y, 8, .left);
		y += 8;
	}
}
