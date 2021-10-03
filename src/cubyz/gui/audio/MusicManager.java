package cubyz.gui.audio;

import cubyz.Logger;
import cubyz.client.Cubyz;
import cubyz.utils.ResourceManager;
import cubyz.world.ServerWorld;
import cubyz.world.cubyzgenerators.biomes.Biome;

public class MusicManager {
	
	private static SoundManager manager;
	private static SoundSource source;
	private static SoundBuffer music;
	
	private static String currentMusic;

	public static void init(SoundManager manager) {
		MusicManager.manager = manager;
		if (ResourceManager.lookupPath("cubyz/sound") != null) {
			source = new SoundSource(true, true);
			source.setGain(0.3f);
		} else {
			Logger.info("Missing optional sound files. Sounds are disabled.");
		}
	}
	
	public static void setMusic(String musicName) {
		try {
			music = new SoundBuffer(ResourceManager.lookupPath("cubyz/sound/" + musicName + ".ogg"));
		} catch (Exception e) {
			Logger.warning(e);
		}
		currentMusic = musicName;
		source.setBuffer(music.getBufferId());
	}
	
	public static void start() {
		setMusic("Sincerely");
		source.play();
	}
	
	public static void stop() {
		if (source != null) {
			if (source.isPlaying()) {
				source.stop();
			}
		}
	}
	
	public static void update(ServerWorld world) {
		int x = (int) Cubyz.player.getPosition().x;
		int z = (int) Cubyz.player.getPosition().z;
		Biome biome = world.getBiome(x, z);
		String targetMusic = "Sincerely";
		if (biome.preferredMusic != null) {
			targetMusic = biome.preferredMusic;
		}
		
		if (!currentMusic.equals(targetMusic)) {
			source.stop();
			setMusic(targetMusic); // TODO: smooth transition between music
			source.play();
		}
	}
	
}
