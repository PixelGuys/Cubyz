package cubyz.gui.audio;

import java.nio.ByteBuffer;
import java.nio.IntBuffer;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.lwjgl.openal.ALC10.*;
import static org.lwjgl.system.MemoryUtil.NULL;

import org.joml.Matrix4f;
import org.lwjgl.openal.AL;
import org.lwjgl.openal.ALC;
import org.lwjgl.openal.ALCCapabilities;

// Imports here

@SuppressWarnings("unused")
public class SoundManager {

	private long device;

	private long context;

	private SoundListener listener;

	private final List<SoundBuffer> soundBufferList;
	private final Map<String, SoundSource> soundSourceMap;
	private final Matrix4f cameraMatrix;

	private boolean inited = false;

	public SoundManager() {
		soundBufferList = new ArrayList<>();
		soundSourceMap = new HashMap<>();
		cameraMatrix = new Matrix4f();
	}

	public void init() throws Exception {
		this.device = alcOpenDevice((ByteBuffer) null);
		if (device == NULL) {
			throw new IllegalStateException("Failed to open the default OpenAL device.");
		}
		ALCCapabilities deviceCaps = ALC.createCapabilities(device);
		this.context = alcCreateContext(device, (IntBuffer) null);
		if (context == NULL) {
			throw new IllegalStateException("Failed to create OpenAL context.");
		}
		alcMakeContextCurrent(context);
		AL.createCapabilities(deviceCaps);
		inited = true;
	}
	
	public void dispose() throws Exception {
		if (inited)
			alcCloseDevice(device);
	}

	public SoundListener getListener() {
		return listener;
	}

	public void setListener(SoundListener listener) {
		this.listener = listener;
	}

	public boolean wasInitedCorrectly() {
		return inited;
	}

}