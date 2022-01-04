package cubyz.gui.game.inventory;

import cubyz.api.Resource;
import cubyz.client.Cubyz;
import cubyz.gui.components.Component;
import cubyz.gui.components.InventorySlot;
import cubyz.rendering.Window;
import cubyz.world.items.Inventory;
import cubyz.world.items.Item;
import cubyz.world.items.tools.Tool;

import static cubyz.client.ClientSettings.GUI_SCALE;

/**
 * The GUI that appears when opening the workbench.
 */

public class WorkbenchGUI extends GeneralInventory {
	/**Buttons used for switching the crafting mode.*/
	Inventory in;
	
	public static WorkbenchGUI activeGUI;
	
	public WorkbenchGUI() {
		super(new Resource("cubyz:workbench"));
		activeGUI = this;
	}
	
	@Override
	protected void positionSlots() {
		width = 180 * GUI_SCALE;
		height = 240 * GUI_SCALE;
		if (in != null)
			setInventory(in);
	}

	@Override
	protected void mouseAction() {
		for(int i = 0; i < inv.length; i++) {
			if (inv[i].grabWithMouse(carriedStack, Window.getWidth()/2, Window.getHeight()/2+height/2)) {
				if (i == inv.length-1 && carriedStack.getItem() != null) {
					// Remove one of each of the items in the crafting grid.
					for(int j = 32; j < inv.length-1; j++) {
						inv[j].reference.add(-1);
					}
				}
			}
			if (i >= 32) {
				// If one of the crafting slots was changed, check if the recipe is changed, too.
				checkCrafting();
			}
		}
	}
	
	@Override
	public void setInventory(Inventory in) {
		this.in = in;
		inv = new InventorySlot[58];
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
		inv[32] = new InventorySlot(in.getStack(0), -60 * GUI_SCALE, 230 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[33] = new InventorySlot(in.getStack(1), -40 * GUI_SCALE, 230 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[34] = new InventorySlot(in.getStack(2), -20 * GUI_SCALE, 230 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[35] = new InventorySlot(in.getStack(3), 0 * GUI_SCALE, 230 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[36] = new InventorySlot(in.getStack(4), 20 * GUI_SCALE, 230 * GUI_SCALE, Component.ALIGN_BOTTOM);

		inv[37] = new InventorySlot(in.getStack(5), -60 * GUI_SCALE, 210 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[38] = new InventorySlot(in.getStack(6), -40 * GUI_SCALE, 210 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[39] = new InventorySlot(in.getStack(7), -20 * GUI_SCALE, 210 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[40] = new InventorySlot(in.getStack(8), 0 * GUI_SCALE, 210 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[41] = new InventorySlot(in.getStack(9), 20 * GUI_SCALE, 210 * GUI_SCALE, Component.ALIGN_BOTTOM);

		inv[42] = new InventorySlot(in.getStack(10), -60 * GUI_SCALE, 190 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[43] = new InventorySlot(in.getStack(11), -40 * GUI_SCALE, 190 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[44] = new InventorySlot(in.getStack(12), -20 * GUI_SCALE, 190 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[45] = new InventorySlot(in.getStack(13), 0 * GUI_SCALE, 190 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[46] = new InventorySlot(in.getStack(14), 20 * GUI_SCALE, 190 * GUI_SCALE, Component.ALIGN_BOTTOM);

		inv[47] = new InventorySlot(in.getStack(15), -60 * GUI_SCALE, 170 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[48] = new InventorySlot(in.getStack(16), -40 * GUI_SCALE, 170 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[49] = new InventorySlot(in.getStack(17), -20 * GUI_SCALE, 170 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[50] = new InventorySlot(in.getStack(18), 0 * GUI_SCALE, 170 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[51] = new InventorySlot(in.getStack(19), 20 * GUI_SCALE, 170 * GUI_SCALE, Component.ALIGN_BOTTOM);

		inv[52] = new InventorySlot(in.getStack(20), -60 * GUI_SCALE, 150 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[53] = new InventorySlot(in.getStack(21), -40 * GUI_SCALE, 150 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[54] = new InventorySlot(in.getStack(22), -20 * GUI_SCALE, 150 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[55] = new InventorySlot(in.getStack(23), 0 * GUI_SCALE, 150 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[56] = new InventorySlot(in.getStack(24), 20 * GUI_SCALE, 150 * GUI_SCALE, Component.ALIGN_BOTTOM);

		inv[57] = new InventorySlot(in.getStack(25), 60 * GUI_SCALE, 190 * GUI_SCALE, Component.ALIGN_BOTTOM, true); // crafting result

		checkCrafting();
	}
	
	/**
	 * Checks if the recipe is valid and adds the corresponding item in the output slot.
	 */
	private void checkCrafting() {
		Item item = null;
		inv[inv.length-1].reference.clear();

		Item[] items = new Item[25];
		int num = 0;
		for(int i = 0; i < 25; i++) {
			if (inv[32 + i].reference.getItem() != null && inv[32 + i].reference.getItem().material != null) {
				items[i] = inv[32 + i].reference.getItem();
				num++;
			}
		}
		if (num != 0) {
			item = new Tool(items);
		}

		if (item != null) {
			inv[inv.length - 1].reference.setItem(item);
			inv[inv.length - 1].reference.add(1);
		}
	}
}
