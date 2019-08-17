package io.cubyz.base;

import org.jungle.Window;

import io.cubyz.ui.MenuGUI;

// TODO
public class WorkbenchGUI extends MenuGUI {

	@Override
	public void init(long nvg) {
		
	}

	@Override
	public void render(long nvg, Window win) {
		
	}

	// Will not pause the game
	@Override
	public boolean doesPauseGame() {
		return false;
	}
	
	@Override
	public boolean ungrabsMouse() {
		return true;
	}

}
