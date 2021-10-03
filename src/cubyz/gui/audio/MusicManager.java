package cubyz.gui.audio;

import java.util.HashMap;

import cubyz.Logger;
import cubyz.client.Cubyz;
import cubyz.utils.ResourceManager;
import cubyz.world.ServerWorld;
import cubyz.world.cubyzgenerators.biomes.Biome;

public class MusicManager {
	
	private static SoundManager manager;
	private static SoundSource source;
	
	/**
	 * Current music buffer
	 */
	private static SoundBuffer music;
	
	private static HashMap<String, SoundBuffer> buffers = new HashMap<>();
	private static HashMap<String, Float> positions = new HashMap<>();
	
	private static String currentMusic = "None";
	private static long silenceStart = 0;

	public static void init(SoundManager manager) {
		MusicManager.manager = manager;
		if (ResourceManager.lookupPath("cubyz/sound") != null) {
			source = new SoundSource(true, true);
		} else {
			Logger.info("Missing optional sound files. Sounds are disabled.");
		}
	}
	
	public static void setMusic(String musicName) {
		if (currentMusic != "None") {
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
	
	public static void start() {
		
	}
	
	public static void stop() {
		if (source != null) {
			if (source.isPlaying()) {
				source.stop();
			}
		}
	}
	
	public static void update(ServerWorld world) {
		if (!source.isPlaying()) {
			silenceStart = System.currentTimeMillis();
			positions.put(currentMusic, 0.0f);
			currentMusic = "None";
		} else {
			long dur = System.currentTimeMillis() - silenceStart;
			float gain = dur / 5000.0f;
			if (gain < 0.0f) gain = 0.0f;
			if (gain > 1.0f) gain = 1.0f;
			source.setGain(gain * 0.3f);
		}
		
		int x = (int) Cubyz.player.getPosition().x;
		int z = (int) Cubyz.player.getPosition().z;
		Biome biome = world.getBiome(x, z);
		String targetMusic = "GymnopedieNo1";
		if (biome.preferredMusic != null) {
			targetMusic = biome.preferredMusic;
		}
		
		if (!currentMusic.equals(targetMusic)) {
			Logger.info("Change music to " + targetMusic);
			setMusic(targetMusic); // TODO: smooth transition between music
		}
	}
	
}
