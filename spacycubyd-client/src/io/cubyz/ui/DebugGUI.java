package io.cubyz.ui;

import org.jungle.Window;

import io.cubyz.Constants;
import io.cubyz.client.Cubyz;
import io.cubyz.world.World;

/**
 * Note: This is the F3 debug menu
 * @author zenith391
 *
 */
public class DebugGUI extends MenuGUI {

	String javaVersion = System.getProperty("java.version");
	
	@Override
	public void render(long nvg, Window win) {
		if (Cubyz.clientShowDebug) {
			NGraphics.setFont("OpenSans", 12.0F);
			NGraphics.setColor(255, 255, 255);
			NGraphics.drawText(0, 0, Cubyz.getFPS() + "/60 fps");
			NGraphics.drawText(0, win.getHeight() - 60, "Branded \"" + Constants.GAME_BRAND + "\", version " + Constants.GAME_VERSION);
			NGraphics.drawText(0, win.getHeight() - 48, "Windowed (" + win.getWidth() + "x" + win.getHeight() + ")");
			NGraphics.drawText(0, win.getHeight() - 36, "Java " + javaVersion);
			
			if (Cubyz.world == null) {
				NGraphics.drawText(0, win.getHeight() - 24, "World: (none)");
			} else {
				World world = Cubyz.world;
				float x = world.getLocalPlayer().getPosition().x();
				float y = world.getLocalPlayer().getPosition().y();
				float z = world.getLocalPlayer().getPosition().z();
				
				NGraphics.drawText(0, 12, "X: " + x);
				NGraphics.drawText(0, 24, "Y: " + y);
				NGraphics.drawText(0, 36, "Z: " + z);
			}
		}
	}

	@Override
	public boolean isFullscreen() {
		return false;
	}

	@Override
	public void init(long nvg) {}

}
