package io.cubyz.ui;

import org.jungle.Window;

public class GameOverlay extends MenuGUI {

	int crosshair;
	
	@Override
	public void init(long nvg) {
		crosshair = NGraphics.loadImage("assets/cubyz/textures/crosshair.png");
	}

	@Override
	public void render(long nvg, Window win) {
		NGraphics.drawImage(crosshair, win.getWidth() / 2 - 16, win.getHeight() / 2 - 16, 32, 32);
	}

	@Override
	public boolean isFullscreen() {
		return false;
	}

}
