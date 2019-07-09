package io.cubyz.ui;

import org.jungle.Window;
import org.lwjgl.nanovg.NanoVG;

import io.cubyz.ui.ToastManager.Toast;

public class GeneralOverlay extends MenuGUI {

	long toastStartTimestamp;
	Toast currentToast;
	
	@Override
	public void init(long nvg) {
		
	}

	@Override
	public void render(long nvg, Window win) {
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
	public boolean doesPauseGame() {
		return false;
	}

}
