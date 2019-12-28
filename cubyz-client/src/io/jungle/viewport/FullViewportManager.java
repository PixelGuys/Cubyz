package io.jungle.viewport;

import io.jungle.Window;

public class FullViewportManager extends ViewportManager {

	@Override
	public int getX(Window win) {
		return 0;
	}

	@Override
	public int getY(Window win) {
		return 0;
	}

	@Override
	public int getWidth(Window win) {
		return win.getWidth();
	}

	@Override
	public int getHeight(Window win) {
		return win.getHeight();
	}

}
