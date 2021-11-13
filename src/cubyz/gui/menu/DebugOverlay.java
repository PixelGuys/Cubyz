package cubyz.gui.menu;

import cubyz.Constants;
import cubyz.client.ClientSettings;
import cubyz.client.Cubyz;
import cubyz.client.GameLauncher;
import cubyz.client.GameLogic;
import cubyz.gui.MenuGUI;
import cubyz.rendering.Graphics;
import cubyz.rendering.Window;
import cubyz.rendering.text.Fonts;
import cubyz.world.entity.Player;

import static cubyz.client.ClientSettings.GUI_SCALE;

/**
 * This is the F3 debug menu
 * @author zenith391
 */

public class DebugOverlay extends MenuGUI {

	String javaVersion = System.getProperty("java.version");
	
	int[] lastFps = new int[50];
	long lastFpsCount = System.currentTimeMillis();
	
	@Override
	public void render() {
		if(GameLauncher.input.clientShowDebug) {
			Graphics.setFont(Fonts.PIXEL_FONT, 8.0F * GUI_SCALE);
			Graphics.setColor(0xFFFFFF);
			Graphics.drawText(0 * GUI_SCALE, 0 * GUI_SCALE, GameLogic.getFPS() + " fps" + (Window.isVSyncEnabled() ? " (vsync)" : ""));
			//TODO: tick speed
			Graphics.drawText(0 * GUI_SCALE, 10 * GUI_SCALE, "Branded \"" + Constants.GAME_BRAND + "\", version " + Constants.GAME_VERSION);
			Graphics.drawText(0 * GUI_SCALE, 20 * GUI_SCALE, "Windowed (" + Window.getWidth() + "x" + Window.getHeight() + ")");
			Graphics.drawText(0 * GUI_SCALE, 30 * GUI_SCALE, "Java " + javaVersion);
			Graphics.drawText(0 * GUI_SCALE, 100 * GUI_SCALE, "Memory: " + (Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory())/1024/1024
					+ "/" + (Runtime.getRuntime().totalMemory()/1024/1024) + "MiB (max " + (Runtime.getRuntime().maxMemory()/1024/1024) + "MiB)");
			
			if(Cubyz.world != null) {
				Player p = Cubyz.player;
				double x = p.getPosition().x;
				double y = p.getPosition().y;
				double z = p.getPosition().z;
				
				Graphics.drawText(0 * GUI_SCALE, 40 * GUI_SCALE, "XYZ: " + x + ", " + y + ", " + z);
				Graphics.drawText(0 * GUI_SCALE, 50 * GUI_SCALE, "Loaded Chunks: " + Cubyz.world.getChunks().length);
				Graphics.drawText(0 * GUI_SCALE, 60 * GUI_SCALE, "Render Distance: " + ClientSettings.RENDER_DISTANCE);
				Graphics.drawText(0 * GUI_SCALE, 70 * GUI_SCALE, "Game Time: " + Cubyz.gameTime);
				Graphics.drawText(0 * GUI_SCALE, 80 * GUI_SCALE, "Chunk Queue Size: " + Cubyz.world.getChunkQueueSize());
				Graphics.drawText(0 * GUI_SCALE, 90 * GUI_SCALE, "Biome: " + (Cubyz.biome == null ? "null" : Cubyz.biome.getRegistryID()));
				
				if(p.getRemainingBreakTime() > 0) {
					Graphics.drawText(0 * GUI_SCALE, 100 * GUI_SCALE, "Remaining Breaking Time: " + p.getRemainingBreakTime());
				}
			}
			
			int h = Window.getHeight();
			Graphics.drawText(0 * GUI_SCALE, h - 10 * GUI_SCALE, "00 fps \\_");
			Graphics.drawText(0 * GUI_SCALE, h - 25 * GUI_SCALE, "30 fps \\_");
			Graphics.drawText(0 * GUI_SCALE, h - 40 * GUI_SCALE, "60 fps \\_");
			for(int i = 0; i < lastFps.length; i++) {
				if(lastFps[i] != 0) {
					Graphics.fillRect(i*4 * GUI_SCALE, h - lastFps[i] * GUI_SCALE / 2, 4 * GUI_SCALE, lastFps[i] * GUI_SCALE / 2);
				}
			}
			
			if(System.currentTimeMillis() > lastFpsCount + 1000) {
				lastFpsCount = System.currentTimeMillis();
				for(int i = 0; i < lastFps.length; i++) { // shift the array to left by 1
					int val = lastFps[i];
					if(i - 1 >= 0) {
						lastFps[i - 1] = val;
					}
				}
				
				lastFps[lastFps.length - 1] = GameLogic.getFPS(); // set new fps value
			}
		}
	}

	@Override
	public boolean doesPauseGame() {
		return false;
	}

	@Override
	public void init() {}

	@Override
	public void updateGUIScale() {}

}