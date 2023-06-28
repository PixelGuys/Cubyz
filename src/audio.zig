const std = @import("std");

const main = @import("root");

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

// TODO: Proper sound and music system
// TODO: volume control

var stream: ?*c.PaStream = null;

var musicData: []f32 = undefined; // TODO: Add a caching system for music data.

const sampleRate = 44100;

pub fn init() !void {
	handleError(c.Pa_Initialize());

	handleError(c.Pa_OpenDefaultStream(
		&stream,
		0, // input channels
		2, // stereo output
		c.paFloat32,
		sampleRate, // TODO: There must be some target dependant value to put here.
		c.paFramesPerBufferUnspecified,
		&patestCallback,
		null
	));

	var err: c_int = 0;
	const ogg_stream = c.stb_vorbis_open_filename("assets/cubyz/music/cubyz.ogg", &err, null);
	defer c.stb_vorbis_close(ogg_stream);
	if(ogg_stream != null) {
		const ogg_info: c.stb_vorbis_info = c.stb_vorbis_get_info(ogg_stream);
		std.debug.assert(sampleRate == ogg_info.sample_rate); // TODO: Handle this case
		std.debug.assert(2 == ogg_info.channels); // TODO: Handle this case
		const samples = c.stb_vorbis_stream_length_in_samples(ogg_stream);
		musicData = try main.globalAllocator.alloc(f32, samples*@as(usize, @intCast(ogg_info.channels)));
		_ = c.stb_vorbis_get_samples_float_interleaved(ogg_stream, ogg_info.channels, musicData.ptr, @as(c_int, @intCast(samples))*ogg_info.channels);
	} else {
		std.log.err("Error reading file TODO", .{});
	}

	handleError(c.Pa_StartStream(stream));
}

pub fn deinit() void {
	handleError(c.Pa_StopStream(stream));
	handleError(c.Pa_CloseStream(stream));
	handleError(c.Pa_Terminate());
	main.globalAllocator.free(musicData);
}

var curIndex: usize = 0;

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
	const out: [*]f32 = @ptrCast(@alignCast(outputBuffer));
	for(0..framesPerBuffer) |i| {
		out[2*i] = musicData[curIndex];
		out[2*i+1] = musicData[curIndex+1];
		curIndex = (curIndex + 2)%musicData.len;
	}
	return 0;
}


