package cubyz.gui.game.inventory;

import cubyz.api.Resource;
import cubyz.client.Cubyz;
import cubyz.gui.components.Component;
import cubyz.gui.components.InventorySlot;
import cubyz.rendering.Window;
import cubyz.world.items.Inventory;
import cubyz.world.items.Item;
import cubyz.world.items.ItemStack;

import static cubyz.client.ClientSettings.GUI_SCALE;

/**
 * The GUI that appears when opening the creative menu
 */
public class CreativeGUI extends GeneralInventory {

	public CreativeGUI() {
		super(new Resource("cubyz:creative"));
	}
	
	@Override
	public void init() {
		super.init();
		inv = new InventorySlot[32 + Cubyz.world.registries.itemRegistry.size()];
	}

	@Override
	protected void positionSlots() {
		width = 180 * GUI_SCALE;
		height = 180 * GUI_SCALE;
		if (inv != null)
			setInventory(null);
	}

	@Override
	protected void mouseAction() {
		for(int i = 0; i < inv.length; i++) {
			if (inv[i].grabWithMouse(carriedStack, Window.getWidth()/2, Window.getHeight()/2+height/2)) {
				if (i >= 32) {
					Item[] items = Cubyz.world.registries.itemRegistry.registered(new Item[0]);
					inv[i].reference = new ItemStack(items[i - 32], 64);
				}
			}
		}
	}
	
	@Override
	public void setInventory(Inventory in) {
		Inventory inventory = Cubyz.player.getInventory();
		for(int i = 0; i < 8; i++) {
			inv[i] = new InventorySlot(inventory.getStack(i), (i - 4) * 20 * GUI_SCALE, 30 * GUI_SCALE, Component.ALIGN_BOTTOM);
		}
		for(int i = 0; i < 8; i++) {
			inv[i + 8] = new InventorySlot(inventory.getStack(i + 8), (i - 4) * 20 * GUI_SCALE, 80 * GUI_SCALE, Component.ALIGN_BOTTOM);
		}
		for(int i = 0; i < 8; i++) {
			inv[i + 16] = new InventorySlot(inventory.getStack(i + 16), (i - 4) * 20 * GUI_SCALE, 100 * GUI_SCALE, Component.ALIGN_BOTTOM);
		}
		for(int i = 0; i < 8; i++) {
			inv[i + 24] = new InventorySlot(inventory.getStack(i + 24), (i - 4) * 20 * GUI_SCALE, 120 * GUI_SCALE, Component.ALIGN_BOTTOM);
		}
		
		Item[] items = Cubyz.world.registries.itemRegistry.registered(new Item[0]);
		int x = -80 * GUI_SCALE;
		int y = 150 + (items.length / 8) * 20;
		height = (y + 10) * GUI_SCALE;
		y *= GUI_SCALE;
		for (int i = 0; i < items.length; i++) {
			Item item = items[i];
			inv[32 + i] = new InventorySlot(
					new ItemStack(item, 64), x, y, Component.ALIGN_BOTTOM);
			x += 20 * GUI_SCALE;
			if (x > 60 * GUI_SCALE) {
				x = -80 * GUI_SCALE;
				y -= 20 * GUI_SCALE;
			}
		}
	}
	
}