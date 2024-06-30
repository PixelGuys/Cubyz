const std = @import("std");

const main = @import("root");
const utils = main.utils;

const c = @cImport ({
	@cInclude("portaudio.h");
	@cDefine("STB_VORBIS_HEADER_ONLY", "");
	@cInclude("stb/stb_vorbis.h");
});

fn handleError(paError: c_int) !void {
	if(paError != c.paNoError) {
		std.log.err("PortAudio error: {s}", .{c.Pa_GetErrorText(paError)});
		return error.paError;
	}
}

const AudioData = struct {
	musicId: []const u8,
	data: []f32 = &.{},

	fn init(musicId: []const u8) *AudioData {
		const self = main.globalAllocator.create(AudioData);
		self.* = .{.musicId = musicId};
		var err: c_int = 0;
		const path = std.fmt.allocPrintZ(main.stackAllocator.allocator, "assets/cubyz/music/{s}.ogg", .{musicId}) catch unreachable;
		defer main.stackAllocator.free(path);
		const ogg_stream = c.stb_vorbis_open_filename(path.ptr, &err, null);
		defer c.stb_vorbis_close(ogg_stream);
		if(ogg_stream != null) {
			const ogg_info: c.stb_vorbis_info = c.stb_vorbis_get_info(ogg_stream);
			const samples = c.stb_vorbis_stream_length_in_samples(ogg_stream);
			const channels = 2;
			if(sampleRate != @as(f32, @floatFromInt(ogg_info.sample_rate))) {
				const tempData = main.stackAllocator.alloc(f32, samples*channels);
				defer main.stackAllocator.free(tempData);
				_ = c.stb_vorbis_get_samples_float_interleaved(ogg_stream, channels, tempData.ptr, @as(c_int, @intCast(samples))*ogg_info.channels);
				var stepWidth = @as(f32, @floatFromInt(ogg_info.sample_rate))/sampleRate;
				const newSamples: usize = @intFromFloat(@as(f32, @floatFromInt(tempData.len/2))/stepWidth);
				stepWidth = @as(f32, @floatFromInt(samples))/@as(f32, @floatFromInt(newSamples));
				self.data = main.globalAllocator.alloc(f32, newSamples*channels);
				for(0..newSamples) |s| {
					const samplePosition = @as(f32, @floatFromInt(s))*stepWidth;
					const firstSample: usize = @intFromFloat(@floor(samplePosition));
					const interpolation = samplePosition - @floor(samplePosition);
					for(0..channels) |ch| {
						if(firstSample >= samples - 1) {
							self.data[s*channels + ch] = tempData[(samples - 1)*channels + ch];
						} else {
							self.data[s*channels + ch] = tempData[firstSample*channels + ch]*(1 - interpolation) + tempData[(firstSample + 1)*channels + ch]*interpolation;
						}
					}
				}
			} else {
				self.data = main.globalAllocator.alloc(f32, samples*channels);
				_ = c.stb_vorbis_get_samples_float_interleaved(ogg_stream, channels, self.data.ptr, @as(c_int, @intCast(samples))*ogg_info.channels);
			}
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

var activeTasks: main.ListUnmanaged([]const u8) = .{};
var taskMutex: std.Thread.Mutex = .{};

var musicCache: utils.Cache(AudioData, 4, 4, AudioData.deinit) = .{};

fn findMusic(musicId: []const u8) ?[]f32 {
	{
		taskMutex.lock();
		defer taskMutex.unlock();
		if(musicCache.find(AudioData{.musicId = musicId}, null)) |musicData| {
			return musicData.data;
		}
		for(activeTasks.items) |taskFileName| {
			if(std.mem.eql(u8, musicId, taskFileName)) {
				return null;
			}
		}
	}
	MusicLoadTask.schedule(musicId);
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
	
	pub fn schedule(musicId: []const u8) void {
		const task = main.globalAllocator.create(MusicLoadTask);
		task.* = MusicLoadTask {
			.musicId = musicId,
		};
		main.threadPool.addTask(task, &vtable);
		taskMutex.lock();
		defer taskMutex.unlock();
		activeTasks.append(main.globalAllocator, musicId);
	}

	pub fn getPriority(_: *MusicLoadTask) f32 {
		return std.math.floatMax(f32);
	}

	pub fn isStillNeeded(_: *MusicLoadTask, _: i64) bool {
		return true;
	}

	pub fn run(self: *MusicLoadTask) void {
		defer self.clean();
		const data = AudioData.init(self.musicId);
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

pub fn init() error{paError}!void {
	try handleError(c.Pa_Initialize());
	errdefer handleError(c.Pa_Terminate()) catch {};

	const device = c.Pa_GetDeviceInfo(c.Pa_GetDefaultOutputDevice());
	sampleRate = @floatCast(device.*.defaultSampleRate);

	try handleError(c.Pa_OpenDefaultStream(
		&stream,
		0, // input channels
		2, // stereo output
		c.paFloat32,
		sampleRate,
		c.paFramesPerBufferUnspecified,
		&patestCallback,
		null
	));
	errdefer handleError(c.Pa_CloseStream(stream)) catch {};

	try handleError(c.Pa_StartStream(stream));
	lastTime = std.time.milliTimestamp();
}

pub fn deinit() void {
	handleError(c.Pa_StopStream(stream)) catch {};
	handleError(c.Pa_CloseStream(stream)) catch {};
	handleError(c.Pa_Terminate()) catch {};
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
var curEndIndex: std.atomic.Value(u16) = .{.value = sampleRate/60 & ~@as(u16, 1)};

fn addMusic(buffer: []f32) void {
	const musicId = if(main.game.world) |world| world.playerBiome.load(.monotonic).preferredMusic else "cubyz";
	if(!std.mem.eql(u8, musicId, activeMusicId)) {
		if(activeMusicId.len == 0) {
			if(findMusic(musicId)) |musicBuffer| {
				currentMusic.init(musicBuffer);
				activeMusicId = musicId;
			}
		} else if(!currentMusic.animationDecaying) {
			_ = findMusic(musicId); // Start loading the next music into the cache ahead of time.
			currentMusic.animationDecaying = true;
			currentMusic.animationProgress = 0;
			currentMusic.interpolationPolynomial = utils.unitIntervalSpline(f32, currentMusic.animationAmplitude, currentMusic.animationVelocity, 0, 0);
		}
	} else if(currentMusic.animationDecaying) { // We returned to the biome before the music faded away.
		currentMusic.animationDecaying = false;
		currentMusic.animationProgress = 0;
		currentMusic.interpolationPolynomial = utils.unitIntervalSpline(f32, currentMusic.animationAmplitude, currentMusic.animationVelocity, 1, 0);
	}
	if(activeMusicId.len == 0) return;

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
	addMusic(buffer);
	return 0;
}


