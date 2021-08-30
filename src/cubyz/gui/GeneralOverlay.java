package cubyz.gui;

import cubyz.gui.ToastManager.Toast;
import cubyz.rendering.Graphics;
import cubyz.rendering.Window;
import cubyz.rendering.text.Fonts;

public class GeneralOverlay extends MenuGUI {

	long toastStartTimestamp;
	Toast currentToast;
	
	@Override
	public void init() {
		
	}

	@Override
	public void render() {
		// Toasts
		if(!ToastManager.queuedToasts.isEmpty() && currentToast == null) {
			currentToast = ToastManager.queuedToasts.pop();
			toastStartTimestamp = System.currentTimeMillis();
		}
				
		if(currentToast != null) {
			// Draw toast
			Graphics.setColor(0x000000, 127);
			Graphics.fillRect(Window.getWidth() - 200, 0, 200, 50);
			Graphics.setFont(Fonts.PIXEL_FONT, 32);
			Graphics.drawText(Window.getWidth(), 0, currentToast.title);
			Graphics.setFont(Fonts.PIXEL_FONT, 16);
			Graphics.drawText(Window.getWidth(), 30, currentToast.text);
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
