package org.jungle.audio;

// ... Some imports here
import static org.lwjgl.openal.AL10.*;

import java.nio.IntBuffer;
import java.nio.ShortBuffer;

import org.lwjgl.stb.STBVorbis;
import org.lwjgl.stb.STBVorbisAlloc;
import org.lwjgl.stb.STBVorbisInfo;
import org.lwjgl.system.MemoryUtil;

public class SoundBuffer {

	private final int bufferId;
	private ShortBuffer pcm;

	public SoundBuffer(String file) throws Exception {
		this.bufferId = alGenBuffers();
		try (STBVorbisInfo info = STBVorbisInfo.malloc()) {
			pcm = readVorbis(file, info);

			// Copy to buffer
			alBufferData(bufferId, info.channels() == 1 ? AL_FORMAT_MONO16 : AL_FORMAT_STEREO16, pcm, info.sample_rate());
		}
	}

	public int getBufferId() {
		return this.bufferId;
	}

	public void cleanup() {
		alDeleteBuffers(this.bufferId);
		MemoryUtil.memFree(pcm);
		pcm = null;
	}

	public ShortBuffer readVorbis(String file, STBVorbisInfo info) {
		STBVorbisAlloc alloc = STBVorbisAlloc.malloc();
		int[] error = new int[1];
		long handle = STBVorbis.stb_vorbis_open_filename(file, error, alloc);
		if (error[0] != 0) {
			System.err.println("Error opening STB Vorbis: " + error[0]);
			System.exit(1);
			return null;
		}
		STBVorbis.stb_vorbis_get_info(handle, info);
		STBVorbis.stb_vorbis_close(handle);
		
		return STBVorbis.stb_vorbis_decode_filename(file, IntBuffer.wrap(new int[] {info.channels()}), IntBuffer.wrap(new int[] {info.sample_rate()}));
	}
	
}