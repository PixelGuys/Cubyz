package io.cubyz.ui;

import org.jungle.Window;
import org.lwjgl.nanovg.NanoVG;

import io.cubyz.Constants;
import io.cubyz.client.Cubyz;
import io.cubyz.ui.ToastManager.Toast;
import io.cubyz.world.World;

/**
 * Note: This is the F3 debug menu
 * @author zenith391
 *
 */
public class DebugGUI extends MenuGUI {

	String javaVersion = System.getProperty("java.version");
	
	long toastStartTimestamp;
	Toast currentToast;
	
	@Override
	public void render(long nvg, Window win) {
		if (Cubyz.clientShowDebug) {
			NGraphics.setFont("OpenSans Bold", 12.0F);
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
		
		// Toasts
		if (!ToastManager.queuedToasts.isEmpty() && currentToast == null) {
			currentToast = ToastManager.queuedToasts.pop();
			toastStartTimestamp = System.currentTimeMillis();
		}
		
		if (currentToast != null) {
			// Draw toast
			int defaultAlign = NGraphics.getTextAlign();
			NGraphics.setTextAlign(NanoVG.NVG_ALIGN_RIGHT | NanoVG.NVG_ALIGN_TOP);
			NGraphics.setColor(0, 0, 0, 127);
			NGraphics.fillRect(win.getWidth() - 200, 0, 200, 50);
			NGraphics.setFont("OpenSans Bold", 24f);
			NGraphics.drawText(win.getWidth(), 0, currentToast.title);
			NGraphics.setFont("OpenSans Bold", 12f);
			NGraphics.drawText(win.getWidth(), 30, currentToast.text);
			NGraphics.setTextAlign(defaultAlign);
			if (toastStartTimestamp < System.currentTimeMillis() - 2500) {
				currentToast = null;
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