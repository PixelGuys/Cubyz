package cubyz.gui.game.inventory;

import org.joml.Vector3f;

import cubyz.api.CubyzRegistries;
import cubyz.api.Resource;
import cubyz.client.Cubyz;
import cubyz.gui.components.Component;
import cubyz.gui.components.InventorySlot;
import cubyz.rendering.Window;
import cubyz.world.items.Inventory;
import cubyz.world.items.Item;
import cubyz.world.items.ItemStack;
import cubyz.world.items.Recipe;

import static cubyz.client.ClientSettings.GUI_SCALE;

/**
 * GUI of the normal inventory(when pressing 'I')
 */

public class InventoryGUI extends GeneralInventory {
	
	int playerInventorySize;
	
	public InventoryGUI() {
		super(new Resource("cubyz:inventory"));
	}

	@Override
	public void close() {
		super.close();
		 // Place the crafting slots in an empty slot or throw them out.
		for(int i = playerInventorySize; i < playerInventorySize + 5; i++) {
			if (inv[i].reference.empty()) continue;
			inv[i].reference.setAmount(Cubyz.player.getInventory().addItem(inv[i].reference.getItem(), inv[i].reference.getAmount()));
			if (inv[i].reference.empty()) continue;
			Cubyz.world.drop(inv[i].reference, Cubyz.player.getPosition(), new Vector3f(), 0);
		}
	}
	
	private void checkCrafting() {
		// Clear everything in case there is no recipe available.
		inv[playerInventorySize+4].reference.clear();
		// Find out how many items are there in the grid and put them in an array:
		int num = 0;
		Item[] ar = new Item[4];
		for(int i = 0; i < 4; i++) {
			ar[i] = inv[playerInventorySize + i].reference.getItem();
			if (ar[i] != null)
				num++;
		}
		Recipe[] recipes = CubyzRegistries.RECIPE_REGISTRY.registered(new Recipe[0]);
		// Find a fitting recipe:
		Item item = null;
		for(Recipe rec : recipes) {
			if (rec.getNum() != num)
				continue;
			item = rec.canCraft(ar, 2);
			if (item != null) {
				
				inv[playerInventorySize+4].reference.setItem(item);
				inv[playerInventorySize+4].reference.add(rec.getNumRet());
				return;
			}
		}
	}

	@Override
	protected void positionSlots() {
		playerInventorySize = Cubyz.player.getInventory().getCapacity();
		inv = new InventorySlot[playerInventorySize + 5];
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
		inv[playerInventorySize] = new InventorySlot(new ItemStack(), 0 * GUI_SCALE, 180 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[playerInventorySize+1] = new InventorySlot(new ItemStack(), 20 * GUI_SCALE, 180 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[playerInventorySize+2] = new InventorySlot(new ItemStack(), 0 * GUI_SCALE, 160 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[playerInventorySize+3] = new InventorySlot(new ItemStack(), 20 * GUI_SCALE, 160 * GUI_SCALE, Component.ALIGN_BOTTOM);
		inv[playerInventorySize+4] = new InventorySlot(new ItemStack(), 60 * GUI_SCALE, 170 * GUI_SCALE, Component.ALIGN_BOTTOM, true);

		width = 180 * GUI_SCALE;
		height = 190 * GUI_SCALE;
	}

	@Override
	protected void mouseAction() {
		boolean notNull = inv[playerInventorySize+4].reference.getItem() != null;
		for(int i = 0; i < inv.length; i++) {
			if (inv[i].grabWithMouse(carriedStack, Window.getWidth()/2, Window.getHeight()/2+height/2)) {
				if (i == playerInventorySize+4 && notNull) {
					// Remove items in the crafting grid.
					for(int j = playerInventorySize; j < playerInventorySize+4; j++) {
						inv[j].reference.add(-1);
					}
				}
			}
			if (i >= playerInventorySize) {
				checkCrafting();
			}
		}
	}
}