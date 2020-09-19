package io.cubyz.ui;

import io.cubyz.api.RegistryElement;
import io.cubyz.api.Resource;
import io.cubyz.items.Inventory;
import io.jungle.Window;

public abstract class MenuGUI implements RegistryElement {
	
	protected float alphaMultiplier;
	
	protected final Resource id;
	
	public MenuGUI() {
		this.id = Resource.EMPTY;
	}
	
	public MenuGUI(Resource id) {
		this.id = id;
	}
	
	public abstract void init(long nvg);
	public abstract void render(long nvg, Window win); 
	
	public abstract boolean doesPauseGame();
	
	public boolean ungrabsMouse() {
		return false;
	}
	
	// Optional methods
	public void dispose() {}
	
	// For those guis that count on a block inventory. Others can safely ignore this.
	public void setInventory(Inventory inv) {}

	@Override
	public Resource getRegistryID() {
		return id;
	}
	
}