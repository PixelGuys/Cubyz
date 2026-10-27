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

pub fn render(currentFrame: *graphics.vulkan.Frame) void {
	var y: f32 = 0;
	const fpsCapText = if (main.settings.fpsCap) |fpsCap| main.stackAllocator.print(" (limit: {d:.0} Hz)", .{fpsCap}) else "";
	defer main.stackAllocator.allocator.free(fpsCapText);
	const fpsLimit = main.stackAllocator.print("{s}{s}", .{
		fpsCapText,
		if (main.settings.vsync) " (vsync)" else "",
	});
	defer main.stackAllocator.allocator.free(fpsLimit);
	draw.print(currentFrame, "fps: {d:.0} Hz{s}", .{1.0/main.lastDeltaTime.load(.monotonic), fpsLimit}, 0, y, 8);
	y += 8;
	draw.print(currentFrame, "frameTime: {d:.1} ms", .{main.lastFrameTime.load(.monotonic)*1000.0}, 0, y, 8);
	y += 8;
	draw.print(currentFrame, "window size: {}×{}", .{main.Window.width, main.Window.height}, 0, y, 8);
	y += 8;
	if (main.game.world != null) {
		const player = main.game.player;
		draw.print(currentFrame, "Pos: {d:.1}", .{player.getPosBlocking()}, 0, y, 8);
		y += 8;
		draw.print(currentFrame, "Gamemode: {} IsFlying: {} IsGhost: {} HyperSpeed: {}", .{
			player.gamemode.load(.monotonic),
			player.isFlying.load(.monotonic),
			player.isGhost.load(.monotonic),
			player.hyperSpeed.load(.monotonic),
		}, 0, y, 8);
		y += 8;
		draw.print(currentFrame, "OnGround: {} JumpCooldown: {d:.3} JumpCoyote: {d:.3}", .{
			player.onGround,
			player.jumpCooldown,
			@max(0, player.getJumpCoyoteBlocking()),
		}, 0, y, 8);
		y += 8;
		draw.print(currentFrame, "Velocity: {d:.1}", .{player.getVelBlocking()}, 0, y, 8);
		y += 8;
		draw.print(currentFrame, "EyePos: {d:.1} EyeVelocity: {d:.1} EyeCoyote: {d:.3}", .{player.getEyePosBlocking(), player.getEyeVelBlocking(), @max(0, player.getEyeCoyoteBlocking())}, 0, y, 8);
		y += 8;
		draw.print(currentFrame, "Game Time: {} Day Phase: {}", .{main.game.world.?.gameTime.load(.monotonic), main.game.world.?.dayTime.dayPhase}, 0, y, 8);
		y += 8;
		draw.print(currentFrame, "Queue size: {}", .{main.threadPool.queueSize()}, 0, y, 8);
		y += 8;
		const perf = main.threadPool.performance.read();
		const values = comptime std.enums.values(TaskType);
		var totalUtime: i64 = 0;
		for (values) |task| {
			totalUtime += perf.utime[@backingInt(task)];
		}
		for (values) |t| {
			const name = @tagName(t);
			const i = @backingInt(t);
			const taskTime = @divFloor(perf.utime[i], @max(1, perf.tasks[i]));
			const relativeTime = 100.0*@as(f32, @floatFromInt(perf.utime[i]))/@as(f32, @floatFromInt(totalUtime));
			draw.print(currentFrame, "    {s}: {} µs/task ({d:.1}%)", .{name, taskTime, relativeTime}, 0, y, 8);
			y += 8;
		}
		draw.print(currentFrame, "Mesh Queue size: {}", .{main.renderer.mesh_storage.updatableList.items.len}, 0, y, 8);
		y += 8;
		for (0..main.settings.highestLod + 1) |lod| {
			const faceDataSize: usize = @sizeOf(main.renderer.chunk_meshing.FaceData);
			const size: usize = main.renderer.chunk_meshing.faceBuffers[lod].capacity*faceDataSize;
			const used: usize = main.renderer.chunk_meshing.faceBuffers[lod].used*faceDataSize;
			draw.print(currentFrame, "ChunkMesh memory LOD{}: {} MiB / {} MiB", .{lod, used >> 20, size >> 20}, 0, y, 8);
			y += 8;
		}
		for (0..main.settings.highestLod + 1) |lod| {
			const lightDataSize: usize = @sizeOf(u32);
			const size: usize = main.renderer.chunk_meshing.lightBuffers[lod].capacity*lightDataSize;
			const used: usize = main.renderer.chunk_meshing.lightBuffers[lod].used*lightDataSize;
			draw.print(currentFrame, "Light memory LOD{}: {} MiB / {} MiB", .{lod, used >> 20, size >> 20}, 0, y, 8);
			y += 8;
		}
		{
			const biome = main.game.world.?.playerBiome.load(.monotonic);
			var tags = main.ListManaged(u8).init(main.stackAllocator);
			defer tags.deinit();
			inline for (@typeInfo(main.server.terrain.biomes.Biome.ClimateProperties).@"struct".field_names) |name| {
				if (@field(biome.climate, name)) {
					if (tags.items.len != 0) tags.appendSlice(", ");
					tags.appendSlice(name);
				}
			}
			draw.print(currentFrame, "Biome: {s}", .{biome.id}, 0, y, 8);
			y += 8;
			draw.print(currentFrame, "Biome Climate: {s}", .{tags.items}, 0, y, 8);
			y += 8;
		}
		draw.print(currentFrame, "Opaque faces: {}, Transparent faces: {}", .{main.renderer.chunk_meshing.quadsDrawn, main.renderer.chunk_meshing.transparentQuadsDrawn}, 0, y, 8);
		y += 8;
		draw.print(currentFrame, "Particle count: {}/{}", .{main.particles.particle_system.getParticleCount(), main.particles.particle_system.maxCapacity}, 0, y, 8);
		y += 8;
		draw.print(currentFrame, "items: {} entities: {}", .{main.game.world.?.itemDrops.super.size, main.client.entity_manager.entities.len}, 0, y, 8);
		y += 8;
	}
}
