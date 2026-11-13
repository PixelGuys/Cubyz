const std = @import("std");

const main = @import("main");
const Vec3d = main.vec.Vec3d;

const Mood = main.audio.music_tracks.MusicTrack.Mood;
const Biome = main.server.terrain.biomes.Biome;

pub var current: Mood = undefined;
pub var target: Mood = undefined;
var baseMood: Mood = undefined;
var energyPulse: f32 = undefined;
var sanityPulse: f32 = undefined;

var lastBiome: ?*const Biome = undefined;
var lastHealth: ?f32 = undefined;

var checkpoint: ?Vec3d = undefined;

const nearbyPlayerRadius: f64 = 32;
const sanityPerNearbyPlayer: f32 = 0.05;
const maxNearbyPlayerSanity: f32 = 0.2;
const darknessThreshold: f32 = 0.1;
const darknessSanityPenalty: f32 = 0.3;
const walkingSpeed: f64 = 4.5;
const maxSpeedEnergy: f32 = 0.5;

const checkpointDistance: f64 = 100;
const checkpointEnergy: f32 = 0.2;
const sanityPerHealthLost: f32 = 0.1;

pub fn init() void {
	const defaultMood = Mood.loadFromZon(.null, .{});
	current = defaultMood;
	target = defaultMood;
	baseMood = defaultMood;
	energyPulse = 0;
	sanityPulse = 0;
	lastBiome = null;
	lastHealth = null;
	checkpoint = null;
}

fn approach(value: f32, goal: f32, rate: f32, deltaTime: f64) f32 {
	const t = 1 - @exp(-rate*@as(f32, @floatCast(deltaTime)));
	return value + (goal - value)*t;
}

pub fn update(deltaTime: f64) void {
	updateBiome();
	updateHealth();
	updateCheckpoint();

	target = baseMood;
	target.energy += energyPulse + speedEnergy();
	target.sanity += sanityPulse + nearbyPlayersSanity() - darknessSanity();
	target.anxiety = std.math.clamp(target.anxiety, 0, 1);
	target.energy = std.math.clamp(target.energy, 0, 1);
	target.sanity = std.math.clamp(target.sanity, 0, 1);

	current.anxiety = approach(current.anxiety, target.anxiety, 0.15, deltaTime);
	current.energy = approach(current.energy, target.energy, 0.2, deltaTime);
	current.sanity = approach(current.sanity, target.sanity, 0.25, deltaTime);

	energyPulse = approach(energyPulse, 0, 0.3, deltaTime);
	sanityPulse = approach(sanityPulse, 0, 0.2, deltaTime);
}

fn updateBiome() void {
	const biome = main.game.world.?.playerBiome.load(.monotonic);
	if (biome == lastBiome) return;
	lastBiome = biome;
	baseMood = biome.baseMood;
}

fn updateHealth() void {
	const health = main.game.player.super.health;
	if (lastHealth) |last| {
		if (health < last) sanityPulse += (health - last)*sanityPerHealthLost;
	}
	lastHealth = health;
}

fn updateCheckpoint() void {
	const pos = main.game.player.getPosBlocking();
	const last = checkpoint orelse {
		checkpoint = pos;
		return;
	};
	if (main.vec.lengthSquare(pos - last) >= checkpointDistance*checkpointDistance) {
		checkpoint = pos;
		energyPulse += checkpointEnergy;
	}
}

fn speedEnergy() f32 {
	const speed = main.vec.length(main.game.player.getVelBlocking());
	const intensity: f32 = @floatCast(std.math.clamp((speed - walkingSpeed)/walkingSpeed, 0, 1));
	return maxSpeedEnergy*intensity;
}

fn nearbyPlayersSanity() f32 {
	const playerPos = main.game.player.getPosBlocking();
	var nearbyCount: u32 = 0;
	for (main.client.entity_manager.entities.items()) |ent| {
		if (main.entity.components.@"cubyz:player".client.get(ent.id) == null) continue;
		if (main.vec.lengthSquare(ent.pos - playerPos) <= nearbyPlayerRadius*nearbyPlayerRadius) {
			nearbyCount += 1;
		}
	}
	return @min(sanityPerNearbyPlayer*@as(f32, @floatFromInt(nearbyCount)), maxNearbyPlayerSanity);
}

fn darknessSanity() f32 {
	const eyePos = main.game.player.getEyePosBlocking();
	const wx: i32 = @intFromFloat(@floor(eyePos[0]));
	const wy: i32 = @intFromFloat(@floor(eyePos[1]));
	const wz: i32 = @intFromFloat(@floor(eyePos[2]));
	const light = main.renderer.mesh_storage.getLight(wx, wy, wz) orelse return 0;
	const maxLight = @reduce(.Max, @as(@Vector(6, u8), light));
	return if (@as(f32, @floatFromInt(maxLight))/256 <= darknessThreshold) darknessSanityPenalty else 0;
}
