package io.cubyz.ui;

import io.cubyz.items.Inventory;
import io.jungle.Window;

public abstract class MenuGUI {
	
	public abstract void init(long nvg);
	public abstract void render(long nvg, Window win); 
	
	public abstract boolean doesPauseGame();
	
	public boolean ungrabsMouse() {
		return false;
	}
	
	// Optional methods
	public void dispose() {}
	
	// For those guis that count on a block inventory. Others can safely ignore this.
	public MenuGUI setInventory(Inventory inv) {
		return this;
	}
	
}