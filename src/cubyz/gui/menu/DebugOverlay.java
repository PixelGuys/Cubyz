package cubyz.gui.menu;

import cubyz.Constants;
import cubyz.client.ClientSettings;
import cubyz.client.Cubyz;
import cubyz.client.GameLauncher;
import cubyz.client.GameLogic;
import cubyz.gui.MenuGUI;
import cubyz.multiplayer.Protocols;
import cubyz.rendering.Graphics;
import cubyz.rendering.Window;
import cubyz.rendering.text.Fonts;
import cubyz.utils.ThreadPool;
import cubyz.world.entity.Player;

import static cubyz.client.ClientSettings.GUI_SCALE;

/**
 * This is the F3 debug menu
 * @author zenith391
 */

public class DebugOverlay extends MenuGUI {

	String javaVersion = System.getProperty("java.version");
	
	private static float[] lastFrameTime = new float[2048];
	private static int index = 0;
	
	public static void addFrameTime(float deltaTime) {
		lastFrameTime[index] = deltaTime;
		index = (index + 1)%lastFrameTime.length;
	}
	
	@Override
	public void render() {
		if (GameLauncher.input.clientShowDebug) {
			Graphics.setFont(Fonts.PIXEL_FONT, 8.0F * GUI_SCALE);
			Graphics.setColor(0xFFFFFF);
			Graphics.drawText(0 * GUI_SCALE, 0 * GUI_SCALE, GameLogic.getFPS() + " fps" + (Window.isVSyncEnabled() ? " (vsync)" : ""));
			//TODO: tick speed
			Graphics.drawText(0 * GUI_SCALE, 10 * GUI_SCALE, "Branded \"" + Constants.GAME_BRAND + "\", version " + Constants.GAME_VERSION);
			Graphics.drawText(0 * GUI_SCALE, 20 * GUI_SCALE, "Windowed (" + Window.getWidth() + "x" + Window.getHeight() + ")");
			Graphics.drawText(0 * GUI_SCALE, 30 * GUI_SCALE, "Java " + javaVersion);
			long totalMemory = Runtime.getRuntime().totalMemory()/1024/1024;
			long freeMemory = Runtime.getRuntime().freeMemory()/1024/1024;
			long maxMemory = Runtime.getRuntime().maxMemory()/1024/1024;
			Graphics.drawText(0 * GUI_SCALE, 90 * GUI_SCALE, "Memory: " + (totalMemory - freeMemory) + "/" + totalMemory + "MiB (max " + maxMemory + "MiB)");
			
			if (Cubyz.world != null) {
				Player p = Cubyz.player;
				double x = p.getPosition().x;
				double y = p.getPosition().y;
				double z = p.getPosition().z;
				
				Graphics.drawText(0 * GUI_SCALE, 40 * GUI_SCALE, "XYZ: " + x + ", " + y + ", " + z);
				Graphics.drawText(0 * GUI_SCALE, 50 * GUI_SCALE, "Render Distance: " + ClientSettings.RENDER_DISTANCE);
				Graphics.drawText(0 * GUI_SCALE, 60 * GUI_SCALE, "Game Time: " + Cubyz.world.gameTime);
				Graphics.drawText(0*GUI_SCALE, 70*GUI_SCALE, "Queue Size: " + ThreadPool.getQueueSize());
				Graphics.drawText(0 * GUI_SCALE, 80 * GUI_SCALE, "Biome: " + (Cubyz.world.playerBiome == null ? "null" : Cubyz.world.playerBiome.getRegistryID()));
				
				int yText = 100;
				for(int i = 0; i < Protocols.bytesReceived.length; i++) {
					if(Protocols.list[i] != null) {
						Graphics.drawText(0*GUI_SCALE, yText*GUI_SCALE, Protocols.list[i].getClass().getSimpleName() + ": " + (Protocols.bytesReceived[i] >> 10) + "kiB");
						yText += 10;
					}
				}
			}
			
			int h = Window.getHeight();
			Graphics.drawText(0 * GUI_SCALE, h - 10 * GUI_SCALE, "00 ms \\_");
			Graphics.drawText(0 * GUI_SCALE, h - 26 * GUI_SCALE, "16 ms \\_");
			Graphics.drawText(0 * GUI_SCALE, h - 42 * GUI_SCALE, "32 ms \\_");
			for(int i = 1; i < lastFrameTime.length; i++) {
				float deltaTime = lastFrameTime[(i - 1 + index)%lastFrameTime.length];
				float deltaTimeNext = lastFrameTime[(i + index)%lastFrameTime.length];
				Graphics.drawLine((i - 1)*GUI_SCALE/8, h - 10 - deltaTime*GUI_SCALE, i*GUI_SCALE/8, h - 10 - deltaTimeNext*GUI_SCALE);
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