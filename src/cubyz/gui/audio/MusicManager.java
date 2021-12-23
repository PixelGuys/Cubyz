package cubyz.gui.audio;

import java.util.HashMap;

import cubyz.client.ClientSettings;
import cubyz.utils.Logger;
import cubyz.client.Cubyz;
import cubyz.utils.ResourceManager;
import cubyz.world.terrain.biomes.Biome;

public class MusicManager {
	
	private static SoundManager manager;
	private static SoundSource source;
	
	/**
	 * Current music buffer
	 */
	private static SoundBuffer music;
	
	private static HashMap<String, SoundBuffer> buffers = new HashMap<>();
	private static HashMap<String, Float> positions = new HashMap<>();
	
	private static String oldMusic = "None";
	private static String currentMusic = "None";
	private static boolean currentMusicStarted = true;
	private static long fadeOutStart = 0;
	private static long fadeInStart = 0;
	private static long silenceStart = 0;
	
	private static final boolean DEBUG = false;
	
	// Durations in milliseconds
	private static final long SILENCE_DURATION  = 5000;
	private static final long FADE_IN_DURATION  = 5000;
	private static final long FADE_OUT_DURATION = 5000;

	public static void init(SoundManager manager) {
		MusicManager.manager = manager;
		if (!manager.wasInitedCorrectly())
			return;
		
		if (ResourceManager.lookupPath("cubyz/sound") != null) {
			source = new SoundSource(true, true);
		} else {
			Logger.info("Missing optional sound files. Sounds are disabled.");
		}
	}
	
	public static void loadMusic(String musicName) {
		if (currentMusic != "None") {
			if(source!=null)
			positions.put(currentMusic, source.getPlaybackPosition());
		}
		try {
			if (!buffers.containsKey(musicName)) {
				buffers.put(musicName, new SoundBuffer(ResourceManager.lookupPath("cubyz/sound/" + musicName + ".ogg")));
			}
			music = buffers.get(musicName);
		} catch (Exception e) {
			Logger.warning(e);
		}
		silenceStart = System.currentTimeMillis();
		currentMusic = musicName;
		source.setBuffer(music.getBufferId());
		source.play();
		source.setPlaybackPosition(positions.getOrDefault(musicName, 0.0f));
	}
	
	public static void setMusic(String musicName) {
		if (DEBUG) Logger.debug("Previous music was " + oldMusic);
		if (musicName == oldMusic) {
			currentMusic = musicName;
			currentMusicStarted = true;
			fadeInStart = 0;
			return;
		}
		currentMusic = musicName;
		currentMusicStarted = false;
		fadeOutStart = System.currentTimeMillis();
		silenceStart = 0;
		if (DEBUG) Logger.debug("Start fade out");
	}
	
	public static void start() {
		
	}
	
	public static void stop() {
		if (source != null) {
			if (source.isPlaying()) {
				source.stop();
			}
		}
		oldMusic = "None";
		currentMusic = "None";
	}
	
	public static void update() {
		if (manager == null || !manager.wasInitedCorrectly() || !ClientSettings.musicOnOff)
			return;
		
		if ((source == null || !source.isPlaying()) && !currentMusic.equals("None")) {
			silenceStart = System.currentTimeMillis();
			positions.put(currentMusic, 0.0f);
			if (currentMusicStarted) {
				currentMusic = "None";
			} else {
				loadMusic(currentMusic);
			}
		} else {
			long silenceDuration = System.currentTimeMillis() - silenceStart;
			if (!currentMusicStarted && silenceStart > 0 && silenceDuration >= SILENCE_DURATION) {
				loadMusic(currentMusic);
				oldMusic = currentMusic;
				currentMusicStarted = true;
				fadeInStart = System.currentTimeMillis();
				if (DEBUG) Logger.debug("Start fade in");
			}
			long fadeIn = System.currentTimeMillis() - fadeInStart;
			float gain = fadeIn / (float) FADE_IN_DURATION;
			if (!currentMusicStarted && silenceStart != 0) {
				gain = 0.0f;
			}
			if (gain > 1.0f) gain = 1.0f;
			if (!currentMusicStarted && silenceStart == 0) {
				float fadeOut = (System.currentTimeMillis() - fadeOutStart) / (float) FADE_OUT_DURATION;
				gain = gain * (1 - fadeOut);
				if (fadeOut >= 1) {
					silenceStart = System.currentTimeMillis();
					if (DEBUG) Logger.debug("Start silence");
				}
			}
			if (source!=null)
				source.setGain(gain * 0.3f);
		}
		
		String targetMusic = "GymnopedieNo1";
		
		if (Cubyz.world != null) {
			Biome biome = Cubyz.biome;
			if (biome != null && biome.preferredMusic != null) {
				targetMusic = biome.preferredMusic;
			}
		} else {
			targetMusic = "cubyz"; // main menu music
		}
		
		if (!currentMusic.equals(targetMusic)) {
			if (DEBUG) Logger.debug("Change music to " + targetMusic + " from " + currentMusic);
			setMusic(targetMusic); // TODO: smooth transition between music
		}
	}
	
}
