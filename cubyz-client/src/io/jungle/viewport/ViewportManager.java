package io.jungle.viewport;

import io.jungle.Window;

public abstract class ViewportManager {

	public abstract int getX(Window win);
	public abstract int getY(Window win);
	
	public abstract int getWidth(Window win);
	public abstract int getHeight(Window win);
	
}
