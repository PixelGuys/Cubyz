const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const utils = main.utils;

const c = @cImport ({
	@cInclude("portaudio.h");
	@cDefine("STB_VORBIS_HEADER_ONLY", "");
	@cInclude("stb/stb_vorbis.h");
});

fn handleError(paError: c_int) void {
	if(paError != c.paNoError) {
		std.log.err("PortAudio error: {s}", .{c.Pa_GetErrorText(paError)});
		@panic("Audio error");
	}
}

const AudioData = struct {
	musicId: []const u8,
	data: []f32 = &.{},

	fn init(musicId: []const u8) !*AudioData {
		const self = try main.globalAllocator.create(AudioData);
		self.* = .{.musicId = musicId};
		var err: c_int = 0;
		const path = try std.fmt.allocPrintZ(main.threadAllocator, "assets/cubyz/music/{s}.ogg", .{musicId});
		defer main.threadAllocator.free(path);
		const ogg_stream = c.stb_vorbis_open_filename(path.ptr, &err, null);
		defer c.stb_vorbis_close(ogg_stream);
		if(ogg_stream != null) {
			const ogg_info: c.stb_vorbis_info = c.stb_vorbis_get_info(ogg_stream);
			if(sampleRate != @as(f32, @floatFromInt(ogg_info.sample_rate))) { // TODO: Does it make sense to convert it?
				std.log.warn("Audio file {s} has unsupported sample rate {}. Only {} is supported. Expect distortions.", .{path, ogg_info.sample_rate, sampleRate});
			}
			const samples = c.stb_vorbis_stream_length_in_samples(ogg_stream);
			const channels = 2;
			self.data = try main.globalAllocator.alloc(f32, samples*channels);
			_ = c.stb_vorbis_get_samples_float_interleaved(ogg_stream, channels, self.data.ptr, @as(c_int, @intCast(samples))*ogg_info.channels);
		} else {
			std.log.err("Couldn't read audio with id {s}", .{musicId});
		}
		return self;
	}

	fn deinit(self: *const AudioData) void {
		main.globalAllocator.free(self.data);
		main.globalAllocator.destroy(self);
	}

	pub fn hashCode(self: *const AudioData) u32 {
		var result: u32 = 0;
		for(self.musicId) |char| {
			result = result + char;
		}
		return result;
	}

	pub fn equals(self: *const AudioData, _other: ?*const AudioData) bool {
		if(_other) |other| {
			return std.mem.eql(u8, self.musicId, other.musicId);
		} else return false;
	}
};

var activeTasks: std.ArrayListUnmanaged([]const u8) = .{};
var taskMutex: std.Thread.Mutex = .{};

var musicCache: utils.Cache(AudioData, 4, 4, AudioData.deinit) = .{};

fn findMusic(musicId: []const u8) !?[]f32 {
	{
		taskMutex.lock();
		defer taskMutex.unlock();
		if(musicCache.find(AudioData{.musicId = musicId})) |musicData| {
			return musicData.data;
		}
		for(activeTasks.items) |taskFileName| {
			if(std.mem.eql(u8, musicId, taskFileName)) {
				return null;
			}
		}
	}
	try MusicLoadTask.schedule(musicId);
	return null;
}

const MusicLoadTask = struct {
	musicId: []const u8,

	const vtable = utils.ThreadPool.VTable{
		.getPriority = @ptrCast(&getPriority),
		.isStillNeeded = @ptrCast(&isStillNeeded),
		.run = @ptrCast(&run),
		.clean = @ptrCast(&clean),
	};
	
	pub fn schedule(musicId: []const u8) !void {
		var task = try main.globalAllocator.create(MusicLoadTask);
		task.* = MusicLoadTask {
			.musicId = musicId,
		};
		try main.threadPool.addTask(task, &vtable);
		taskMutex.lock();
		defer taskMutex.unlock();
		try activeTasks.append(main.globalAllocator, musicId);
	}

	pub fn getPriority(_: *MusicLoadTask) f32 {
		return std.math.floatMax(f32);
	}

	pub fn isStillNeeded(_: *MusicLoadTask) bool {
		return true;
	}

	pub fn run(self: *MusicLoadTask) Allocator.Error!void {
		defer self.clean();
		const data = try AudioData.init(self.musicId);
		const hasOld = musicCache.addToCache(data, data.hashCode());
		if(hasOld) |old| {
			old.deinit();
		}
	}

	pub fn clean(self: *MusicLoadTask) void {
		taskMutex.lock();
		var index: usize = 0;
		while(index < activeTasks.items.len) : (index += 1) {
			if(activeTasks.items[index].ptr == self.musicId.ptr) break;
		}
		_ = activeTasks.swapRemove(index);
		taskMutex.unlock();
		main.globalAllocator.destroy(self);
	}
};

// TODO: Proper sound and music system

var stream: ?*c.PaStream = null;

var sampleRate: f32 = 0;

pub fn init() !void {
	handleError(c.Pa_Initialize());

	const device = c.Pa_GetDeviceInfo(c.Pa_GetDefaultOutputDevice());
	sampleRate = @floatCast(device.*.defaultSampleRate);

	handleError(c.Pa_OpenDefaultStream(
		&stream,
		0, // input channels
		2, // stereo output
		c.paFloat32,
		sampleRate,
		c.paFramesPerBufferUnspecified,
		&patestCallback,
		null
	));

	handleError(c.Pa_StartStream(stream));
	lastTime = std.time.milliTimestamp();
}

pub fn deinit() void {
	handleError(c.Pa_StopStream(stream));
	handleError(c.Pa_CloseStream(stream));
	handleError(c.Pa_Terminate());
	main.threadPool.closeAllTasksOfType(&MusicLoadTask.vtable);
	musicCache.clear();
	activeTasks.deinit(main.globalAllocator);
	activeMusicId.len = 0;
}

const currentMusic = struct {
	var buffer: []const f32 = undefined;
	var animationAmplitude: f32 = undefined;
	var animationVelocity: f32 = undefined;
	var animationDecaying: bool = undefined;
	var animationProgress: f32 = undefined;
	var interpolationPolynomial: [4]f32 = undefined;
	var pos: u32 = undefined;

	fn init(musicBuffer: []const f32) void {
		buffer = musicBuffer;
		animationAmplitude = 0;
		animationVelocity = 0;
		animationDecaying = false;
		animationProgress = 0;
		interpolationPolynomial = utils.unitIntervalSpline(f32, animationAmplitude, animationVelocity, 1, 0);
		pos = 0;
	}

	fn evaluatePolynomial() void {
		const t = animationProgress;
		const t2 = t*t;
		const t3 = t2*t;
		const a = interpolationPolynomial;
		animationAmplitude = a[0] + a[1]*t + a[2]*t2 + a[3]*t3; // value
		animationVelocity = a[1] + 2*a[2]*t + 3*a[3]*t2;
	}
};

var activeMusicId: []const u8 = &.{};
var lastTime: i64 = 0;
var partialFrame: f32 = 0;
const animationLengthInSeconds = 5.0;

var curIndex: u16 = 0;
var curEndIndex: std.atomic.Atomic(u16) = .{.value = sampleRate/60 & ~@as(u16, 1)};

fn addMusic(buffer: []f32) !void {
	const musicId = if(main.game.world) |world| world.playerBiome.preferredMusic else "cubyz";
	if(!std.mem.eql(u8, musicId, activeMusicId)) {
		if(activeMusicId.len == 0) {
			if(try findMusic(musicId)) |musicBuffer| {
				currentMusic.init(musicBuffer);
				activeMusicId = musicId;
			} else return;
		} else if(!currentMusic.animationDecaying) {
			_ = try findMusic(musicId); // Start loading the next music into the cache ahead of time.
			currentMusic.animationDecaying = true;
			currentMusic.animationProgress = 0;
			currentMusic.interpolationPolynomial = utils.unitIntervalSpline(f32, currentMusic.animationAmplitude, currentMusic.animationVelocity, 0, 0);
		}
	} else if(currentMusic.animationDecaying) { // We returned to the biome before the music faded away.
		currentMusic.animationDecaying = false;
		currentMusic.animationProgress = 0;
		currentMusic.interpolationPolynomial = utils.unitIntervalSpline(f32, currentMusic.animationAmplitude, currentMusic.animationVelocity, 1, 0);
	}

	// Copy the music to the buffer.
	var i: usize = 0;
	while(i < buffer.len) : (i += 2) {
		currentMusic.animationProgress += 1.0/(animationLengthInSeconds*sampleRate);
		var amplitude: f32 = main.settings.musicVolume;
		if(currentMusic.animationProgress > 1) {
			if(currentMusic.animationDecaying) {
				activeMusicId = &.{};
				amplitude = 0;
			}
		} else {
			currentMusic.evaluatePolynomial();
			amplitude *= currentMusic.animationAmplitude;
		}
		buffer[i] += amplitude*currentMusic.buffer[currentMusic.pos];
		buffer[i + 1] += amplitude*currentMusic.buffer[currentMusic.pos + 1];
		currentMusic.pos += 2;
		if(currentMusic.pos >= currentMusic.buffer.len) {
			currentMusic.pos = 0;
		}
	}
}

fn patestCallback(
	inputBuffer: ?*const anyopaque,
	outputBuffer: ?*anyopaque,
	framesPerBuffer: c_ulong,
	timeInfo: ?*const c.PaStreamCallbackTimeInfo,
	statusFlags: c.PaStreamCallbackFlags,
	userData: ?*anyopaque
) callconv(.C) c_int {
	// This routine will be called by the PortAudio engine when audio is needed.
	// It may called at interrupt level on some machines so don't do anything
	// that could mess up the system like calling malloc() or free().
	_ = inputBuffer;
	_ = timeInfo; // TODO: Synchronize this to the rest of the world
	_ = statusFlags;
	_ = userData;
	const valuesPerBuffer = 2*framesPerBuffer; // Stereo
	const buffer = @as([*]f32, @ptrCast(@alignCast(outputBuffer)))[0..valuesPerBuffer];
	@memset(buffer, 0);
	addMusic(buffer) catch |err| {
		std.log.err("Encountered error while adding music to the sound output buffer: {s}", .{@errorName(err)});
	};
	return 0;
}


