package cubyz.gui.menu;

import cubyz.gui.MenuGUI;
import cubyz.gui.ToastManager;
import cubyz.gui.ToastManager.Toast;
import cubyz.rendering.Graphics;
import cubyz.rendering.Window;
import cubyz.rendering.text.Fonts;

import static cubyz.client.ClientSettings.GUI_SCALE;

public class GeneralOverlay extends MenuGUI {

	long toastStartTimestamp;
	Toast currentToast;
	
	@Override
	public void init() {
		
	}

	@Override
	public void updateGUIScale() {
		
	}

	@Override
	public void render() {
		// Toasts
		if (!ToastManager.queuedToasts.isEmpty() && currentToast == null) {
			currentToast = ToastManager.queuedToasts.pop();
			toastStartTimestamp = System.currentTimeMillis();
		}
				
		if (currentToast != null) {
			// Draw toast
			Graphics.setColor(0x000000, 127);
			Graphics.fillRect(Window.getWidth() - 200 * GUI_SCALE, 0 * GUI_SCALE, 200 * GUI_SCALE, 50 * GUI_SCALE);
			Graphics.setFont(Fonts.PIXEL_FONT, 32 * GUI_SCALE);
			Graphics.drawText(Window.getWidth(), 0, currentToast.title);
			Graphics.setFont(Fonts.PIXEL_FONT, 16 * GUI_SCALE);
			Graphics.drawText(Window.getWidth(), 30 * GUI_SCALE, currentToast.text);
			if (toastStartTimestamp < System.currentTimeMillis() - 2500) {
				currentToast = null;
			}
		}
	}

	@Override
	public boolean doesPauseGame() {
		return false;
	}

}
