const std = @import("std");

const main = @import("main");
const Vec3d = main.vec.Vec3d;
const Vec3i = main.vec.Vec3i;

const Mood = main.audio.music_tracks.MusicTrack.Mood;

pub var current: Mood = undefined;
pub var target: Mood = undefined;
var darknessSanityPenalty: f32 = undefined;
var energyBoost: f32 = undefined;
var sanityBoost: f32 = undefined;

var lastPlayerChunk: Vec3i = undefined;
var visitedChunks: std.AutoHashMapUnmanaged(Vec3i, void) = undefined;

const nearbyPlayerRadius: f64 = 32;
const darknessThreshold: u8 = 3;

pub fn init() void {
	const defaultMood = Mood.loadFromZon(.null, .{});
	current = defaultMood;
	target = defaultMood;
	darknessSanityPenalty = 0;
	energyBoost = 0;
	sanityBoost = 0;
	lastPlayerChunk = .{std.math.minInt(i32), std.math.minInt(i32), std.math.minInt(i32)};
	visitedChunks = .{};
}

pub fn deinit() void {
	visitedChunks.deinit(main.globalAllocator.allocator);
}

pub fn onBiomeChanged(biome: *const main.server.terrain.biomes.Biome) void {
	target = biome.baseMood;
}

pub fn nudgeEnergy(amount: f32) void {
	energyBoost = std.math.clamp(energyBoost + amount, -1, 1);
}

pub fn nudgeSanity(amount: f32) void {
	sanityBoost = std.math.clamp(sanityBoost + amount, -1, 1);
}

pub fn onCombatEvent(intensity: f32) void {
	nudgeEnergy(intensity);
}

pub fn onDeath() void {
	current.sanity = @max(0, current.sanity - 0.5);
}

fn approach(value: f32, goal: f32, rate: f32, deltaTime: f64) f32 {
	const t = 1 - @exp(-rate*@as(f32, @floatCast(deltaTime)));
	return value + (goal - value)*t;
}

pub fn update(deltaTime: f64) void {
	updateChunkExploration();
	updateNearbyPlayers();
	updateDarkness(deltaTime);

	current.anxiety = approach(current.anxiety, target.anxiety, 0.15, deltaTime);

	const energyTarget = std.math.clamp(target.energy + energyBoost, 0, 1);
	current.energy = approach(current.energy, energyTarget, 0.2, deltaTime);
	energyBoost = approach(energyBoost, 0, 0.3, deltaTime);

	const sanityTarget = std.math.clamp(target.sanity + sanityBoost - darknessSanityPenalty, 0, 1);
	current.sanity = approach(current.sanity, sanityTarget, 0.25, deltaTime);
	sanityBoost = approach(sanityBoost, 0, 0.2, deltaTime);

	current.anxiety = std.math.clamp(current.anxiety, 0, 1);
	current.energy = std.math.clamp(current.energy, 0, 1);
	current.sanity = std.math.clamp(current.sanity, 0, 1);
}

fn updateChunkExploration() void {
	const pos = main.game.player.getPosBlocking();
	const chunkPos: Vec3i = .{
		@as(i32, @intFromFloat(@floor(pos[0]))) >> main.chunk.chunkShift,
		@as(i32, @intFromFloat(@floor(pos[1]))) >> main.chunk.chunkShift,
		@as(i32, @intFromFloat(@floor(pos[2]))) >> main.chunk.chunkShift,
	};
	if (@reduce(.And, chunkPos == lastPlayerChunk)) return;
	lastPlayerChunk = chunkPos;

	const wasAlreadyVisited = visitedChunks.contains(chunkPos);
	visitedChunks.put(main.globalAllocator.allocator, chunkPos, {}) catch unreachable;
	nudgeEnergy(if (wasAlreadyVisited) 0.05 else 0.2);
}

fn updateNearbyPlayers() void {
	const playerPos = main.game.player.getPosBlocking();
	var nearbyCount: u32 = 0;
	for (main.client.entity_manager.entities.items()) |ent| {
		if (main.entity.components.@"cubyz:player".client.get(ent.id) == null) continue;
		if (main.vec.lengthSquare(ent.pos - playerPos) <= nearbyPlayerRadius*nearbyPlayerRadius) {
			nearbyCount += 1;
		}
	}
	if (nearbyCount != 0) nudgeSanity(0.02*@as(f32, @floatFromInt(nearbyCount)));
}

fn updateDarkness(deltaTime: f64) void {
	const eyePos = main.game.player.getEyePosBlocking();
	const wx: i32 = @intFromFloat(@floor(eyePos[0]));
	const wy: i32 = @intFromFloat(@floor(eyePos[1]));
	const wz: i32 = @intFromFloat(@floor(eyePos[2]));
	const light = main.renderer.mesh_storage.getLight(wx, wy, wz) orelse {
		darknessSanityPenalty = approach(darknessSanityPenalty, 0, 0.2, deltaTime);
		return;
	};
	const maxLight = @reduce(.Max, @as(@Vector(6, u8), light));
	const targetPenalty: f32 = if (maxLight <= darknessThreshold) 0.3 else 0;
	darknessSanityPenalty = approach(darknessSanityPenalty, targetPenalty, 0.2, deltaTime);
}

pub fn onBlockMined(block: main.blocks.Block) void {
	for (main.blocks.ores.items) |ore| {
		if (ore.blockType == block.typ) {
			nudgeSanity(0.15);
			return;
		}
	}
}

pub fn onHealthChanged(delta: f32) void {
	if (delta < 0) nudgeSanity(delta*0.1);
}
