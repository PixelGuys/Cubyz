package io.cubyz.base;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.client.Cubyz;
import io.cubyz.items.Inventory;
import io.cubyz.items.Item;
import io.cubyz.items.Recipe;
import io.cubyz.items.tools.Axe;
import io.cubyz.items.tools.Pickaxe;
import io.cubyz.items.tools.Shovel;
import io.cubyz.items.tools.Sword;
import io.cubyz.translate.TextKey;
import io.cubyz.ui.GeneralInventory;
import io.cubyz.ui.MenuGUI;
import io.cubyz.ui.components.Button;
import io.cubyz.ui.components.InventorySlot;
import io.jungle.MouseInput;
import io.jungle.Window;

// TODO
public class WorkbenchGUI extends GeneralInventory {
	private static enum Mode {
		AXE, PICKAXE, SHOVEL, SWORD, NORMAL
	};

	Button axe, pickaxe, shovel, sword, normal;
	Mode craftingMode = Mode.NORMAL;
	Inventory in;
	
	public static WorkbenchGUI activeGUI;
	
	public WorkbenchGUI() {
		normal = new Button();
		normal.setSize(64, 64);
		normal.setText(new TextKey("Normal Grid"));
		axe = new Button();
		axe.setSize(64, 64);
		axe.setText(new TextKey("Axe"));
		pickaxe = new Button();
		pickaxe.setSize(64, 64);
		pickaxe.setText(new TextKey("Pickaxe"));
		shovel = new Button();
		shovel.setSize(64, 64);
		shovel.setText(new TextKey("Shovel"));
		sword = new Button();
		sword.setSize(64, 64);
		sword.setText(new TextKey("Sword"));
		activeGUI = this;
		
		normal.setOnAction(() -> {
			WorkbenchGUI.activeGUI.updateMode(Mode.NORMAL);
		});
		axe.setOnAction(() -> {
			WorkbenchGUI.activeGUI.updateMode(Mode.AXE);
		});
		pickaxe.setOnAction(() -> {
			WorkbenchGUI.activeGUI.updateMode(Mode.PICKAXE);
		});
		shovel.setOnAction(() -> {
			WorkbenchGUI.activeGUI.updateMode(Mode.SHOVEL);
		});
		sword.setOnAction(() -> {
			WorkbenchGUI.activeGUI.updateMode(Mode.SWORD);
		});
	}
	
	public void updateMode(Mode mode) {
		if(craftingMode == mode)
			return;
		craftingMode = mode;
		InventorySlot [] newInv;
		switch(mode) {
			case AXE:
			case PICKAXE:
			case SHOVEL:
			case SWORD:
				newInv = new InventorySlot[36];
				newInv[32] = new InventorySlot(in.getStack(0), -96, 552); // head
				newInv[33] = new InventorySlot(in.getStack(1), -128, 480); // binding
				newInv[34] = new InventorySlot(in.getStack(2), -96, 408); // handle
				newInv[35] = new InventorySlot(in.getStack(3), 32, 480, true); // new tool
				
				break;
			case NORMAL:
				newInv = new InventorySlot[42];
				newInv[32] = new InventorySlot(in.getStack(0), -128, 408);
				newInv[33] = new InventorySlot(in.getStack(3), -64, 408);
				newInv[34] = new InventorySlot(in.getStack(6), 0, 408);
				newInv[35] = new InventorySlot(in.getStack(1), -128, 480);
				newInv[36] = new InventorySlot(in.getStack(4), -64, 480);
				newInv[37] = new InventorySlot(in.getStack(7), 0, 480);
				newInv[38] = new InventorySlot(in.getStack(2), -128, 552);
				newInv[39] = new InventorySlot(in.getStack(5), -64, 552);
				newInv[40] = new InventorySlot(in.getStack(8), 0, 552);
				newInv[41] = new InventorySlot(in.getStack(9), 92, 480, true); // crafting result
				
				break;
			default: return;
		}
		System.arraycopy(inv, 0, newInv, 0, 32);
		inv = newInv;
		checkCrafting();
	}
	
	@Override
	protected void positionSlots() {
		width = 576;
		height = 576;
	}

	@Override
	protected void mouseAction(MouseInput mouse, Window win) {
		for(int i = 0; i < inv.length; i++) {
			// TODO: Don't really swap the references. Just swap the contents of the references. That will make everything a lot easier.
			if(inv[i].grabWithMouse(mouse, carried, win.getWidth()/2, win.getHeight())) {
				if (i == inv.length-1 && inv[inv.length-1].reference.getItem() != null) {
					// Remove items in the crafting grid.
					for(int j = 32; j < inv.length-1; j++) {
						inv[j].reference.clear(); // TODO: Perform a proper material management.
					}
				}
			}
			if(i >= 32) {
				checkCrafting();
			}
		}
	}
	
	@Override
	public MenuGUI setInventory(Inventory in) {
		this.in = in;
		inv = new InventorySlot[32];
		Inventory inventory = Cubyz.world.getLocalPlayer().getInventory();
		for(int i = 0; i < 8; i++) {
			inv[i] = new InventorySlot(inventory.getStack(i), i*64-256, 64);
		}
		for(int i = 0; i < 8; i++) {
			inv[i+8] = new InventorySlot(inventory.getStack(i+8), i*64-256, 192);
		}
		for(int i = 0; i < 8; i++) {
			inv[i+16] = new InventorySlot(inventory.getStack(i+16), i*64-256, 256);
		}
		for(int i = 0; i < 8; i++) {
			inv[i+24] = new InventorySlot(inventory.getStack(i+24), i*64-256, 320);
		}
		
		updateMode(Mode.NORMAL);
		return this;
	}
	
	private void checkCrafting() {
		Item item = null;
		inv[inv.length-1].reference.clear();
		switch(craftingMode) {
			case AXE:
				item = Axe.canCraft(inv[32].reference, inv[33].reference, inv[34].reference);
				break;
			case PICKAXE:
				item = Pickaxe.canCraft(inv[32].reference, inv[33].reference, inv[34].reference);
				break;
			case SHOVEL:
				item = Shovel.canCraft(inv[32].reference, inv[33].reference, inv[34].reference);
				break;
			case SWORD:
				item = Sword.canCraft(inv[32].reference, inv[33].reference, inv[34].reference);
				break;
			case NORMAL:
				// Find out how many items are there in the grid and put them in an array:
				int num = 0;
				Item[] ar = new Item[9];
				for(int i = 0; i < 9; i++) {
					ar[i] = inv[32+i].reference.getItem();
					if(ar[i] != null)
						num++;
				}
				// Get the recipes for the given number of items(TODO!):
				Object[] recipes = CubyzRegistries.RECIPE_REGISTRY.registered();
				// Find a fitting recipe:
				for(int i = 0; i < recipes.length; i++) {
					Recipe rec = (Recipe) recipes[i];
					if(rec.getNum() != num)
						continue;
					item = rec.canCraft(ar, 3);
					if(item != null) {
						inv[41].reference.setItem(item);
						inv[41].reference.add(rec.getNumRet());
						return;
					}
				}
				break;
		}
		if(item != null) {
			inv[inv.length-1].reference.setItem(item);
			inv[inv.length-1].reference.add(1);
		}
	}
	
	@Override
	public void render(long nvg, Window win) {
		super.render(nvg, win);
		normal.setPosition(win.getWidth() / 2 - 360, win.getHeight()-552);
		axe.setPosition(win.getWidth() / 2 - 360, win.getHeight()-480);
		pickaxe.setPosition(win.getWidth() / 2 - 360, win.getHeight()-408);
		shovel.setPosition(win.getWidth() / 2 - 360, win.getHeight()-336);
		sword.setPosition(win.getWidth() / 2 - 360, win.getHeight()-264);

		normal.render(nvg, win);
		axe.render(nvg, win);
		pickaxe.render(nvg, win);
		shovel.render(nvg, win);
		sword.render(nvg, win);
	}

}
