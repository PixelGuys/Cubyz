package io.cubyz.ui;

import org.jungle.Window;

public abstract class MenuGUI {
	
	public abstract void init(long nvg);
	public abstract void render(long nvg, Window win); 
	
	public abstract boolean doesPauseGame();
	
	public boolean grabsMouse() {
		return false;
	}
	
	// Optional methods
	public void dispose() {}
	
}