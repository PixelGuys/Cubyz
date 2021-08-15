package cubyz.gui;

import cubyz.Constants;
import cubyz.client.ClientSettings;
import cubyz.client.Cubyz;
import cubyz.client.GameLauncher;
import cubyz.client.GameLogic;
import cubyz.client.rendering.Window;
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
	public void render(long nvg, Window win) {
		if(GameLauncher.input.clientShowDebug) {
			NGraphics.setFont("Default", 12.0F);
			NGraphics.setColor(255, 255, 255);
			NGraphics.drawText(0, 0, GameLogic.getFPS() + " fps" + (win.isVSyncEnabled() ? " (vsync)" : ""));
			NGraphics.drawText(100, 0, GameLauncher.instance.getUPS() + " ups");
			NGraphics.drawText(0, 12, "Branded \"" + Constants.GAME_BRAND + "\", version " + Constants.GAME_VERSION);
			NGraphics.drawText(0, 24, "Windowed (" + win.getWidth() + "x" + win.getHeight() + ")");
			NGraphics.drawText(0, 36, "Java " + javaVersion);
			NGraphics.drawText(0, 108, "Memory: " + (Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory())/1024/1024
					+ "/" + (Runtime.getRuntime().totalMemory()/1024/1024) + "MiB (max " + (Runtime.getRuntime().maxMemory()/1024/1024) + "MiB)");
			
			if(Cubyz.world != null) {
				World world = Cubyz.world;
				Player p = Cubyz.player;
				float x = p.getPosition().x;
				float y = p.getPosition().y;
				float z = p.getPosition().z;
				
				NGraphics.drawText(0, 48, "XYZ: " + x + ", " + y + ", " + z);
				NGraphics.drawText(0, 60, "Loaded Chunks: " + Cubyz.surface.getChunks().length);
				NGraphics.drawText(0, 72, "Render Distance: " + ClientSettings.RENDER_DISTANCE);
				NGraphics.drawText(0, 84, "Game Time: " + world.getGameTime());
				if(world instanceof LocalWorld) {
					NGraphics.drawText(0, 96, "Chunk Queue Size: " + ((LocalSurface) Cubyz.surface).getChunkQueueSize());
					NGraphics.drawText(0, 118, "Biome: " + Cubyz.surface.getBiome((int)p.getPosition().x, (int)p.getPosition().z).getRegistryID());
				}
				
				if(p instanceof PlayerImpl) { // player on local world
					PlayerImpl pi = (PlayerImpl) p;
					if(pi.getRemainingBreakTime() > 0) {
						NGraphics.drawText(0, 132, "Remaining Breaking Time: " + pi.getRemainingBreakTime());
					}
				}
			}
			
			int h = win.getHeight();
			NGraphics.drawText(0, h - 12, "0  fps -");
			NGraphics.drawText(0, h - 42, "30 fps -");
			NGraphics.drawText(0, h - 72, "60 fps -");
			for(int i = 0; i < lastFps.length; i++) {
				if(lastFps[i] != 0) {
					NGraphics.fillRect(i*4, h - lastFps[i], 4, lastFps[i]);
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
	public void init(long nvg) {}

}