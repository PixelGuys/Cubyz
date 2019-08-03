package io.cubyz.ui;

import org.jungle.Window;

import io.cubyz.Constants;
import io.cubyz.client.Cubyz;
import io.cubyz.world.LocalWorld;
import io.cubyz.world.World;

/**
 * Note: This is the F3 debug menu
 * @author zenith391
 *
 */
public class DebugOverlay extends MenuGUI {

	String javaVersion = System.getProperty("java.version");
	
	int[] lastFps = new int[50];
	long lastFpsCount = System.currentTimeMillis();
	
	@Override
	public void render(long nvg, Window win) {
		if (Cubyz.clientShowDebug) {
			NGraphics.setFont("OpenSans Bold", 12.0F);
			NGraphics.setColor(255, 255, 255);
			NGraphics.drawText(0, 0, Cubyz.getFPS() + "/60 fps");
			NGraphics.drawText(0, 12, "Branded \"" + Constants.GAME_BRAND + "\", version " + Constants.GAME_VERSION);
			NGraphics.drawText(0, 24, "Windowed (" + win.getWidth() + "x" + win.getHeight() + ")");
			NGraphics.drawText(0, 36, "Java " + javaVersion);
			
			if (Cubyz.world != null) {
				World world = Cubyz.world;
				float x = world.getLocalPlayer().getPosition().x + world.getLocalPlayer().getPosition().relX;
				float y = world.getLocalPlayer().getPosition().y;
				float z = world.getLocalPlayer().getPosition().z + world.getLocalPlayer().getPosition().relZ;
				
				NGraphics.drawText(0, 48, "XYZ: " + x + ", " + y + ", " + z);
				NGraphics.drawText(0, 60, "Loaded Chunks: " + world.getVisibleChunks().length + "/" + world.getChunks().size());
				NGraphics.drawText(0, 72, "Render Distance: " + world.getRenderDistance());
				if (world instanceof LocalWorld) {
					NGraphics.drawText(0, 84, "Chunk Queue Size: " + ((LocalWorld) world).getChunkQueueSize());
				}
			}
			
			int h = win.getHeight();
			NGraphics.drawText(0, h - 12, "0  fps -");
			NGraphics.drawText(0, h - 42, "30 fps -");
			NGraphics.drawText(0, h - 72, "60 fps -");
			for (int i = 0; i < lastFps.length; i++) {
				if (lastFps[i] != 0) {
					NGraphics.fillRect(i*4, h - lastFps[i], 4, lastFps[i]);
				}
			}
			
			if (System.currentTimeMillis() > lastFpsCount + 1000) {
				lastFpsCount = System.currentTimeMillis();
				for (int i = 0; i < lastFps.length; i++) { // shift the array to left by 1
					int val = lastFps[i];
					if (i-1 >= 0) {
						lastFps[i-1] = val;
						//lastFps[v]
					} else {
						//lastFps[0] = 0;
					}
				}
				
				lastFps[49] = Cubyz.getFPS(); // set new fps value
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