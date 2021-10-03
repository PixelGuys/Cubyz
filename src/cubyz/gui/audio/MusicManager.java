package cubyz.gui.audio;

import cubyz.Logger;
import cubyz.utils.ResourceManager;

public class MusicManager {
	
	private static SoundManager manager;
	private static SoundSource source;
	private static SoundBuffer music;

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
	
}
