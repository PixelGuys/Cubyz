const std = @import("std");

const main = @import("main");
const vec = main.vec;
const Vec3f = vec.Vec3f;
const utils = main.utils;
const ZonElement = @import("zon.zig").ZonElement;

const c = @import("c");

fn handleError(miniaudioError: c.ma_result) !void {
	if (miniaudioError != c.MA_SUCCESS) {
		std.log.err("miniaudio error: {s}", .{c.ma_result_description(miniaudioError)});
		return error.miniaudioError;
	}
}

fn getMaError(err: c_int) anyerror {
	return switch (err) {
		0 => error.VORBIS__no_error,
		1 => error.VORBIS_need_more_data,
		2 => error.VORBIS_invalid_api_mixing,
		3 => error.VORBIS_outofmem,
		4 => error.VORBIS_feature_not_supported,
		5 => error.VORBIS_too_many_channels,
		6 => error.VORBIS_file_open_failure,
		7 => error.VORBIS_seek_without_length,
		10 => error.VORBIS_unexpected_eof,
		11 => error.VORBIS_seek_invalid,
		20 => error.VORBIS_invalid_setup,
		21 => error.VORBIS_invalid_stream,
		30 => error.VORBIS_missing_capture_pattern,
		31 => error.VORBIS_invalid_stream_structure_version,
		32 => error.VORBIS_continued_packet_flag_invalid,
		33 => error.VORBIS_incorrect_stream_serial_number,
		34 => error.VORBIS_invalid_first_page,
		35 => error.VORBIS_bad_packet_type,
		36 => error.VORBIS_cant_find_last_page,
		37 => error.VORBIS_seek_failed,
		38 => error.VORBIS_ogg_skeleton_not_supported,
		else => unreachable,
	};
}

const AudioData = struct {
	audioId: []const u8,
	data: []f32 = &.{},
	isMono: bool = false,

	volume: f32 = 1,

	fn open_vorbis_file_by_id(id: []const u8, subPath: []const u8) ?*c.stb_vorbis {
		const colonIndex = std.mem.indexOfScalar(u8, id, ':') orelse {
			std.log.err("Invalid music id: {s}. Must be addon:file_name", .{id});
			return null;
		};
		const addon = id[0..colonIndex];
		const fileName = id[colonIndex + 1 ..];
		// FIXME: IF THERE IS SOME PROBLEM WITH THE FILE ITSELF IT JUST SAYS THAT IT COULD NOT FIND THE FILE RATHER THAN THE ACTUAL ISSUE
		const path1 = std.fmt.allocPrintSentinel(main.stackAllocator.allocator, "assets/{s}/{s}/{s}.ogg", .{addon, subPath, fileName}, 0) catch unreachable;
		defer main.stackAllocator.free(path1);
		var err: c_int = 0;
		if (c.stb_vorbis_open_filename(path1.ptr, &err, null)) |ogg_stream| return ogg_stream;
		const path2 = std.fmt.allocPrintSentinel(main.stackAllocator.allocator, "{s}/serverAssets/{s}/{s}/{s}.ogg", .{main.files.cubyzDirStr(), addon, subPath, fileName}, 0) catch unreachable;
		defer main.stackAllocator.free(path2);
		if (c.stb_vorbis_open_filename(path2.ptr, &err, null)) |ogg_stream| return ogg_stream;
		std.log.err("Couldn't handle audio file. Error: {s}. ID: \"{s}\". Searched path: \"{s}\" and \"{s}\"", .{@errorName(getMaError(err)), id, path1, path2});
		return null;
	}

	fn init(musicId: []const u8, subPath: []const u8) *AudioData {
		const self = main.globalAllocator.create(AudioData);
		self.* = .{.audioId = main.globalAllocator.dupe(u8, musicId)};

		const channels = 2;
		if (open_vorbis_file_by_id(musicId, subPath)) |ogg_stream| {
			defer c.stb_vorbis_close(ogg_stream);
			const ogg_info: c.stb_vorbis_info = c.stb_vorbis_get_info(ogg_stream);
			const samples = c.stb_vorbis_stream_length_in_samples(ogg_stream);
			if (sampleRate != @as(f32, @floatFromInt(ogg_info.sample_rate))) {
				const tempData = main.stackAllocator.alloc(f32, samples*channels);
				defer main.stackAllocator.free(tempData);
				self.isMono = ogg_info.channels == 1;
				_ = c.stb_vorbis_get_samples_float_interleaved(ogg_stream, channels, tempData.ptr, @as(c_int, @intCast(samples))*ogg_info.channels);
				var stepWidth = @as(f32, @floatFromInt(ogg_info.sample_rate))/sampleRate;
				const newSamples: usize = @trunc(@as(f32, @floatFromInt(tempData.len/2))/stepWidth);
				stepWidth = @as(f32, @floatFromInt(samples))/@as(f32, @floatFromInt(newSamples));
				self.data = main.globalAllocator.alloc(f32, newSamples*channels);
				for (0..newSamples) |s| {
					const samplePosition = @as(f32, @floatFromInt(s))*stepWidth;
					const firstSample: usize = @floor(samplePosition);
					const interpolation = samplePosition - @floor(samplePosition);
					for (0..channels) |ch| {
						if (firstSample >= samples - 1) {
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
		main.globalAllocator.free(self.audioId);
		main.globalAllocator.destroy(self);
	}

	pub fn hashCode(self: *const AudioData) u32 {
		var result: u32 = 0;
		for (self.audioId) |char| {
			result = result + char;
		}
		return result;
	}

	pub fn equals(self: *const AudioData, _other: ?*const AudioData) bool {
		if (_other) |other| {
			return std.mem.eql(u8, self.audioId, other.audioId);
		} else return false;
	}
};

var activeTasks: main.List([]const u8) = .empty; // MARK: MUSIC
var taskMutex: main.utils.Mutex = .{};

var musicCache: utils.Cache(AudioData, 4, 4, AudioData.deinit) = .{};

fn findMusic(musicId: []const u8) ?[]f32 {
	{
		taskMutex.lock();
		defer taskMutex.unlock();
		if (musicCache.find(AudioData{.audioId = musicId}, null)) |musicData| {
			return musicData.data;
		}
		for (activeTasks.items) |taskFileName| {
			if (std.mem.eql(u8, musicId, taskFileName)) {
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
		.getPriority = main.meta.castFunctionSelfToAnyopaque(getPriority),
		.isStillNeeded = main.meta.castFunctionSelfToAnyopaque(isStillNeeded),
		.run = main.meta.castFunctionSelfToAnyopaque(run),
		.clean = main.meta.castFunctionSelfToAnyopaque(clean),
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
		const data = AudioData.init(self.musicId, "music");
		const hasOld = musicCache.addToCache(data, data.hashCode());
		if (hasOld) |old| {
			old.deinit();
		}
	}

	pub fn clean(self: *MusicLoadTask) void {
		taskMutex.lock();
		var index: usize = 0;
		while (index < activeTasks.items.len) : (index += 1) {
			if (activeTasks.items[index].ptr == self.musicId.ptr) break;
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

	audioIdMap.deinit(main.globalAllocator.allocator);
	audios.deinit(main.globalAllocator);
	soundDataIdMap.deinit(main.globalAllocator.allocator);
	soundDatas.deinit(main.globalAllocator);
	activeSounds.deinit(main.globalAllocator);
}

pub fn reset() void {
	audioIdMap.clearRetainingCapacity();
	for (audios.items) |s| {
		s.deinit();
	}
	audios.clearRetainingCapacity();
	activeSounds.clearRetainingCapacity();
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
var partialFrame: f32 = 0;
const animationLengthInSeconds = 5.0;

var curIndex: u16 = 0;
var curEndIndex: std.atomic.Value(u16) = .{.value = sampleRate/60 & ~@as(u16, 1)};

var mutex: main.utils.Mutex = .{};
var preferredMusic: []const u8 = "";

pub fn setMusic(music: []const u8) void {
	mutex.lock();
	defer mutex.unlock();
	if (std.mem.eql(u8, music, preferredMusic)) return;
	main.globalAllocator.free(preferredMusic);
	preferredMusic = main.globalAllocator.dupe(u8, music);
}

const SoundData = struct { // MARK: SOUNDS
	audioIndex: u32,
	volume: f32 = 1,
};

const PlayingSound = struct {
	pos: Vec3f = @splat(0),
	audioIndex: u32,
	bufPos: u32 = 0,

	volume: f32 = 1,
	maxDistance: f32 = 10,
	isSpatial: bool = false,
};

var audioIdMap: std.StringHashMapUnmanaged(u32) = .{};
var audios: main.List(*AudioData) = .empty;
var soundDataIdMap: std.StringHashMapUnmanaged(u32) = .{};
var soundDatas: main.List(SoundData) = .empty;
var activeSounds: main.List(PlayingSound) = .empty;

pub fn getActiveSoundCount() u32 {
	return @intCast(activeSounds.items.len);
}

pub fn registerAudioData(_: []const u8, id: []const u8) void {
	const audio = AudioData.init(id, "sounds/audio");
	audioIdMap.put(main.globalAllocator.allocator, id, @intCast(audios.items.len)) catch unreachable;
	audios.append(main.globalAllocator, audio);
	std.log.debug("Registered sound audio: {s}", .{id});
}

pub fn registerSound(assetsFolder: []const u8, id: []const u8, zon: ZonElement) void {
	const audioId = zon.get([]const u8, "audio") orelse {
		std.log.err("Sound Data audio was not specified: {s} ({s})", .{id, assetsFolder});
		return;
	};
	
	soundDataIdMap.put(main.globalAllocator.allocator, id, @intCast(soundDatas.items.len)) catch unreachable;
	soundDatas.append(main.globalAllocator, SoundData{
		.audioIndex = audioIdMap.get(audioId) orelse {
			std.log.err("Sound Data audio could not be found: {s} ({s}) audio ID: {s}", .{id, assetsFolder, audioId});
			return;
		},
		.volume = zon.get(f32, "volume") orelse 1.0,
	});

	std.log.debug("Registered sound data: {s}", .{id});
}

fn addSound(id: []const u8, pos: Vec3f, maxDistance: f32, isSpatial: bool) void {
	const idx = soundDataIdMap.get(id) orelse return;
	const soundData = soundDatas.items[idx];
	activeSounds.append(main.globalAllocator, PlayingSound{
		.audioIndex = soundData.audioIndex,
		.volume = soundData.volume,
		.pos = pos,
		.isSpatial = isSpatial,
		.maxDistance = maxDistance,
	});
}

pub fn playSound(id: []const u8) void {
	addSound(id, @splat(0), 0, false);
}

pub fn playSpatialSound(id: []const u8, pos: Vec3f, maxDistance: f32) void {
	addSound(id, pos, maxDistance, true);
}

fn mixMusic(buffer: []f32) void {
	mutex.lock();
	defer mutex.unlock();
	if (!std.mem.eql(u8, preferredMusic, activeMusicId)) {
		if (activeMusicId.len == 0) {
			if (findMusic(preferredMusic)) |musicBuffer| {
				currentMusic.init(musicBuffer);
				main.globalAllocator.free(activeMusicId);
				activeMusicId = main.globalAllocator.dupe(u8, preferredMusic);
			}
		} else if (!currentMusic.animationDecaying) {
			_ = findMusic(preferredMusic); // Start loading the next music into the cache ahead of time.
			currentMusic.animationDecaying = true;
			currentMusic.animationProgress = 0;
			currentMusic.interpolationPolynomial = utils.unitIntervalSpline(f32, currentMusic.animationAmplitude, currentMusic.animationVelocity, 0, 0);
		}
	} else if (currentMusic.animationDecaying) { // We returned to the biome before the music faded away.
		currentMusic.animationDecaying = false;
		currentMusic.animationProgress = 0;
		currentMusic.interpolationPolynomial = utils.unitIntervalSpline(f32, currentMusic.animationAmplitude, currentMusic.animationVelocity, 1, 0);
	}
	if (activeMusicId.len == 0) return;

	// Copy the music to the buffer.
	var i: usize = 0;
	while (i < buffer.len) : (i += 2) {
		currentMusic.animationProgress += 1.0/(animationLengthInSeconds*sampleRate);
		var amplitude: f32 = main.settings.musicVolume;
		if (currentMusic.animationProgress > 1) {
			if (currentMusic.animationDecaying) {
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
		if (currentMusic.pos >= currentMusic.buffer.len) {
			currentMusic.pos = 0;
		}
	}
}

fn mixSound(buffer: []f32) void {
	mutex.lock();
	defer mutex.unlock();

	if (activeSounds.items.len == 0) return;

	const playerPos: Vec3f = @floatCast(main.game.Player.getPosBlocking());
	const playerForward = main.game.camera.direction;
	const playerRight = vec.normalize(vec.cross(playerForward, Vec3f{0, 0, 1}));

	var i: u32 = 0;
	var soundCount = activeSounds.items.len;
	main: while (i < soundCount) {
		var sound = activeSounds.items[i];
		const soundData = audios.items[sound.audioIndex];
		const soundBuffer = soundData.data;

		const notMonoInt: u32 = @intFromBool(!soundData.isMono);
		const bufferStep: u32 = 1 + notMonoInt;

		var leftVol: f32 = 1;
		var rightVol: f32 = 1;

		if (sound.isSpatial) {
			const toSound = sound.pos - playerPos;
			const distance: f32 = vec.length(toSound);

			if (distance > sound.maxDistance) {
				sound.bufPos += @intCast(if (soundData.isMono) @divFloor(buffer.len, 2) else buffer.len);
				if (sound.bufPos >= soundBuffer.len) {
					soundCount -= 1;
					activeSounds.items[i] = activeSounds.items[soundCount];
					continue :main;
				}
			}

			const pan: f32 = vec.dot(toSound/@as(Vec3f, @splat(distance)), playerRight);

			const angle = (pan + 1)*0.25*std.math.pi;
			leftVol = @cos(angle);
			rightVol = @sin(angle);

			var volume: f32 = 1 - distance/sound.maxDistance;

			volume = if (volume < 0) 0 else volume;
			leftVol *= volume;
			rightVol *= volume;
		}

		var j: usize = 0;
		while (j < buffer.len) : (j += 2) {
			const amplitude: f32 = main.settings.soundVolume;

			buffer[j] += soundBuffer[sound.bufPos]*amplitude*soundData.volume*leftVol;
			buffer[j + 1] += soundBuffer[sound.bufPos + notMonoInt]*amplitude*soundData.volume*rightVol;
			sound.bufPos += bufferStep;

			if (sound.bufPos >= soundBuffer.len) {
				soundCount -= 1;
				activeSounds.items[i] = activeSounds.items[soundCount];
				continue :main;
			}
		}
		activeSounds.items[i] = sound;
		i += 1;
	}

	activeSounds.items.len = soundCount;
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
	mixMusic(buffer);
	mixSound(buffer);
}
