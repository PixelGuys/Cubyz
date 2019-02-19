package io.spacycubyd.ui;

import org.jungle.Window;

public abstract class MenuGUI {
	
	public abstract void init(long nvg);
	
	public abstract void render(long nvg, Window win); 
	
	public abstract boolean isFullscreen();
	
}