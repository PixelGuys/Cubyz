package cubyz.gui;

import cubyz.Logger;
import cubyz.api.CubyzRegistries;
import cubyz.api.Registry;
import cubyz.api.Resource;
import cubyz.client.Cubyz;
import cubyz.gui.components.InventorySlot;
import cubyz.rendering.Window;
import cubyz.world.items.Inventory;
import cubyz.world.items.Item;
import cubyz.world.items.ItemStack;

/**
 * The GUI that appears when opening the creative menu
 */
public class CreativeGUI extends GeneralInventory {

	public CreativeGUI() {
		super(new Resource("cubyz:creative"));
		inv = new InventorySlot[32 + CubyzRegistries.ITEM_REGISTRY.size()];
	}

	@Override
	protected void positionSlots() {
		width = 576;
		height = 576;
	}

	@Override
	protected void mouseAction() {
		for(int i = 0; i < inv.length; i++) {
			if(inv[i].grabWithMouse(carried, Window.getWidth()/2, Window.getHeight())) {
				if (i >= 32) {
					Item[] items = CubyzRegistries.ITEM_REGISTRY.registered(new Item[0]);
					inv[i].reference = new ItemStack(items[i - 32], 64);
				}
			}
		}
	}
	
	@Override
	public void setInventory(Inventory in) {
		Inventory inventory = Cubyz.player.getInventory();
		for(int i = 0; i < 8; i++) {
			inv[i] = new InventorySlot(inventory.getStack(i), i*64 - 256, 64, Component.ALIGN_BOTTOM);
		}
		for(int i = 0; i < 8; i++) {
			inv[i + 8] = new InventorySlot(inventory.getStack(i + 8), i*64 - 256, 192, Component.ALIGN_BOTTOM);
		}
		for(int i = 0; i < 8; i++) {
			inv[i + 16] = new InventorySlot(inventory.getStack(i + 16), i*64 - 256, 256, Component.ALIGN_BOTTOM);
		}
		for(int i = 0; i < 8; i++) {
			inv[i + 24] = new InventorySlot(inventory.getStack(i + 24), i*64 - 256, 320, Component.ALIGN_BOTTOM);
		}
		
		Item[] items = CubyzRegistries.ITEM_REGISTRY.registered(new Item[0]);
		int x = -256;
		int y = 408 + (items.length / 8) * 64;
		for (int i = 0; i < items.length; i++) {
			Item item = items[i];
			inv[32 + i] = new InventorySlot(
					new ItemStack(item, 64), x, y, Component.ALIGN_BOTTOM);
			x += 64;
			if (x > 192) {
				x = -256;
				y -= 64;
			}
		}
	}
	
}