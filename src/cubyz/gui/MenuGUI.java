package cubyz.gui;

import cubyz.api.RegistryElement;
import cubyz.api.Resource;
import cubyz.world.items.Inventory;

public abstract class MenuGUI implements RegistryElement {
	
	protected float alphaMultiplier;

	protected final Resource id;
	
	public MenuGUI() {
		this.id = Resource.EMPTY;
	}
	
	public MenuGUI(Resource id) {
		this.id = id;
	}
	
	public abstract void init();
	public abstract void updateGUIScale();
	public abstract void render();
	
	public abstract boolean doesPauseGame(); // TODO: Find a good way to use without bugs in singleplayer only.
	
	public boolean ungrabsMouse() {
		return true;
	}

	/**
	 * Is guaranteed to be called when this GUI is closed.
	 */
	public void close() {}
	// For those guis that count on a block inventory. Others can safely ignore this.
	public void setInventory(Inventory inv) {}

	@Override
	public Resource getRegistryID() {
		return id;
	}
}