package cubyz.gui;

import org.lwjgl.nanovg.NanoVG;

import cubyz.gui.ToastManager.Toast;
import cubyz.rendering.Window;

public class GeneralOverlay extends MenuGUI {

	long toastStartTimestamp;
	Toast currentToast;
	
	@Override
	public void init(long nvg) {
		
	}

	@Override
	public void render(long nvg) {
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
			NGraphics.fillRect(Window.getWidth() - 200, 0, 200, 50);
			NGraphics.setFont("Title", 24f);
			NGraphics.drawText(Window.getWidth(), 0, currentToast.title);
			NGraphics.setFont("Default", 12f);
			NGraphics.drawText(Window.getWidth(), 30, currentToast.text);
			NGraphics.setTextAlign(defaultAlign);
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
