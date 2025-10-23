const std = @import("std");

const main = @import("main");
const utils = main.utils;

const c = @cImport({
	@cInclude("miniaudio.h");
	@cDefine("STB_VORBIS_HEADER_ONLY", "");
	@cInclude("stb/stb_vorbis.h");
});

fn handleError(miniaudioError: c.ma_result) !void {
	if(miniaudioError != c.MA_SUCCESS) {
		std.log.err("miniaudio error: {s}", .{c.ma_result_description(miniaudioError)});
		return error.miniaudioError;
	}
}

const AudioData = struct {
	musicId: []const u8,
	data: []f32 = &.{},

	fn open_vorbis_file_by_id(id: []const u8) ?*c.stb_vorbis {
		const colonIndex = std.mem.indexOfScalar(u8, id, ':') orelse {
			std.log.err("Invalid music id: {s}. Must be addon:file_name", .{id});
			return null;
		};
		const addon = id[0..colonIndex];
		const fileName = id[colonIndex + 1 ..];
		const path1 = std.fmt.allocPrintSentinel(main.stackAllocator.allocator, "assets/{s}/music/{s}.ogg", .{addon, fileName}, 0) catch unreachable;
		defer main.stackAllocator.free(path1);
		var err: c_int = 0;
		if(c.stb_vorbis_open_filename(path1.ptr, &err, null)) |ogg_stream| return ogg_stream;
		const path2 = std.fmt.allocPrintSentinel(main.stackAllocator.allocator, "{s}/serverAssets/{s}/music/{s}.ogg", .{main.files.cubyzDirStr(), addon, fileName}, 0) catch unreachable;
		defer main.stackAllocator.free(path2);
		if(c.stb_vorbis_open_filename(path2.ptr, &err, null)) |ogg_stream| return ogg_stream;
		std.log.err("Couldn't find music with id \"{s}\". Searched path \"{s}\" and \"{s}\"", .{id, path1, path2});
		return null;
	}

	fn init(musicId: []const u8) *AudioData {
		const self = main.globalAllocator.create(AudioData);
		self.* = .{.musicId = main.globalAllocator.dupe(u8, musicId)};

		const channels = 2;
		if(open_vorbis_file_by_id(musicId)) |ogg_stream| {
			defer c.stb_vorbis_close(ogg_stream);
			const ogg_info: c.stb_vorbis_info = c.stb_vorbis_get_info(ogg_stream);
			const samples = c.stb_vorbis_stream_length_in_samples(ogg_stream);
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
			self.data = main.globalAllocator.alloc(f32, channels);
			@memset(self.data, 0);
		}
		return self;
	}

	fn deinit(self: *const AudioData) void {
		main.globalAllocator.free(self.data);
		main.globalAllocator.free(self.musicId);
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
		.getPriority = main.utils.castFunctionSelfToAnyopaque(getPriority),
		.isStillNeeded = main.utils.castFunctionSelfToAnyopaque(isStillNeeded),
		.run = main.utils.castFunctionSelfToAnyopaque(run),
		.clean = main.utils.castFunctionSelfToAnyopaque(clean),
		.taskType = .misc,
	};

	pub fn schedule(musicId: []const u8) void {
		const task = main.globalAllocator.create(MusicLoadTask);
		task.* = MusicLoadTask{
			.musicId = main.globalAllocator.dupe(u8, musicId),
		};
		main.threadPool.addTask(task, &vtable);
		taskMutex.lock();
		defer taskMutex.unlock();
		activeTasks.append(main.globalAllocator, task.musicId);
	}

	pub fn getPriority(_: *MusicLoadTask) f32 {
		return std.math.floatMax(f32);
	}

	pub fn isStillNeeded(_: *MusicLoadTask) bool {
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
		main.globalAllocator.free(self.musicId);
		main.globalAllocator.destroy(self);
	}
};

// TODO: Proper sound and music system

var device: c.ma_device = undefined;

var sampleRate: f32 = 0;

pub fn init() error{miniaudioError}!void {
	var config = c.ma_device_config_init(c.ma_device_type_playback);
	config.playback.format = c.ma_format_f32;
	config.playback.channels = 2;
	config.sampleRate = 44100;
	config.dataCallback = &miniaudioCallback;
	config.pUserData = undefined;

	try handleError(c.ma_device_init(null, &config, &device));

	try handleError(c.ma_device_start(&device));

	sampleRate = 44100;
	lastTime = std.time.milliTimestamp();
}

pub fn deinit() void {
	handleError(c.ma_device_stop(&device)) catch {};
	c.ma_device_uninit(&device);
	mutex.lock();
	defer mutex.unlock();
	main.threadPool.closeAllTasksOfType(&MusicLoadTask.vtable);
	musicCache.clear();
	activeTasks.deinit(main.globalAllocator);
	main.globalAllocator.free(preferredMusic);
	preferredMusic.len = 0;
	main.globalAllocator.free(activeMusicId);
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

var mutex: std.Thread.Mutex = .{};
var preferredMusic: []const u8 = "";

pub fn setMusic(music: []const u8) void {
	mutex.lock();
	defer mutex.unlock();
	if(std.mem.eql(u8, music, preferredMusic)) return;
	main.globalAllocator.free(preferredMusic);
	preferredMusic = main.globalAllocator.dupe(u8, music);
}

fn addMusic(buffer: []f32) void {
	mutex.lock();
	defer mutex.unlock();
	if(!std.mem.eql(u8, preferredMusic, activeMusicId)) {
		if(activeMusicId.len == 0) {
			if(findMusic(preferredMusic)) |musicBuffer| {
				currentMusic.init(musicBuffer);
				main.globalAllocator.free(activeMusicId);
				activeMusicId = main.globalAllocator.dupe(u8, preferredMusic);
			}
		} else if(!currentMusic.animationDecaying) {
			_ = findMusic(preferredMusic); // Start loading the next music into the cache ahead of time.
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
				main.globalAllocator.free(activeMusicId);
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

fn miniaudioCallback(
	maDevice: ?*anyopaque,
	output: ?*anyopaque,
	input: ?*const anyopaque,
	frameCount: u32,
) callconv(.c) void {
	_ = input;
	_ = maDevice;
	const valuesPerBuffer = 2*frameCount; // Stereo
	const buffer = @as([*]f32, @ptrCast(@alignCast(output)))[0..valuesPerBuffer];
	@memset(buffer, 0);
	addMusic(buffer);
}
