package cubyz.gui;

import cubyz.Constants;
import cubyz.client.ClientSettings;
import cubyz.client.Cubyz;
import cubyz.client.GameLauncher;
import cubyz.client.GameLogic;
import cubyz.rendering.Graphics;
import cubyz.rendering.Window;
import cubyz.rendering.text.Fonts;
import cubyz.world.LocalSurface;
import cubyz.world.LocalWorld;
import cubyz.world.World;
import cubyz.world.entity.Player;
import cubyz.world.entity.PlayerEntity.PlayerImpl;

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
			Graphics.setFont(Fonts.PIXEL_FONT, 16.0F);
			Graphics.setColor(0xFFFFFF);
			Graphics.drawText(0, 0, GameLogic.getFPS() + " fps" + (Window.isVSyncEnabled() ? " (vsync)" : ""));
			Graphics.drawText(120, 0, GameLauncher.instance.getUPS() + " ups");
			Graphics.drawText(0, 20, "Branded \"" + Constants.GAME_BRAND + "\", version " + Constants.GAME_VERSION);
			Graphics.drawText(0, 40, "Windowed (" + Window.getWidth() + "x" + Window.getHeight() + ")");
			Graphics.drawText(0, 60, "Java " + javaVersion);
			Graphics.drawText(0, 200, "Memory: " + (Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory())/1024/1024
					+ "/" + (Runtime.getRuntime().totalMemory()/1024/1024) + "MiB (max " + (Runtime.getRuntime().maxMemory()/1024/1024) + "MiB)");
			
			if(Cubyz.world != null) {
				World world = Cubyz.world;
				Player p = Cubyz.player;
				float x = p.getPosition().x;
				float y = p.getPosition().y;
				float z = p.getPosition().z;
				
				Graphics.drawText(0, 80, "XYZ: " + x + ", " + y + ", " + z);
				Graphics.drawText(0, 100, "Loaded Chunks: " + Cubyz.surface.getChunks().length);
				Graphics.drawText(0, 120, "Render Distance: " + ClientSettings.RENDER_DISTANCE);
				Graphics.drawText(0, 140, "Game Time: " + world.getGameTime());
				if(world instanceof LocalWorld) {
					Graphics.drawText(0, 160, "Chunk Queue Size: " + ((LocalSurface) Cubyz.surface).getChunkQueueSize());
					Graphics.drawText(0, 180, "Biome: " + Cubyz.surface.getBiome((int)p.getPosition().x, (int)p.getPosition().z).getRegistryID());
				}
				
				if(p instanceof PlayerImpl) { // player on local world
					PlayerImpl pi = (PlayerImpl) p;
					if(pi.getRemainingBreakTime() > 0) {
						Graphics.drawText(0, 200, "Remaining Breaking Time: " + pi.getRemainingBreakTime());
					}
				}
			}
			
			int h = Window.getHeight();
			Graphics.drawText(0, h - 20, "00 fps \\_");
			Graphics.drawText(0, h - 50, "30 fps \\_");
			Graphics.drawText(0, h - 80, "60 fps \\_");
			for(int i = 0; i < lastFps.length; i++) {
				if(lastFps[i] != 0) {
					Graphics.fillRect(i*4, h - lastFps[i], 4, lastFps[i]);
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

}