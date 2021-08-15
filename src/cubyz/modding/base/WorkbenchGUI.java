package cubyz.modding.base;

import cubyz.api.CubyzRegistries;
import cubyz.api.Resource;
import cubyz.client.Cubyz;
import cubyz.client.rendering.Window;
import cubyz.gui.Component;
import cubyz.gui.GeneralInventory;
import cubyz.gui.components.Button;
import cubyz.gui.components.InventorySlot;
import cubyz.gui.input.MouseInput;
import cubyz.utils.translate.TextKey;
import cubyz.world.items.Inventory;
import cubyz.world.items.Item;
import cubyz.world.items.Recipe;
import cubyz.world.items.tools.Axe;
import cubyz.world.items.tools.Pickaxe;
import cubyz.world.items.tools.Shovel;
import cubyz.world.items.tools.Sword;

/**
 * The GUI that appears when opening the workbench.
 */

public class WorkbenchGUI extends GeneralInventory {
	private static enum Mode {
		AXE, PICKAXE, SHOVEL, SWORD, NORMAL
	};
	/**Buttons used for switching the crafting mode.*/
	Button axe, pickaxe, shovel, sword, normal;
	Mode craftingMode = Mode.NORMAL;
	Inventory in;
	
	public static WorkbenchGUI activeGUI;
	
	public WorkbenchGUI() {
		super(new Resource("cubyz:workbench"));
		normal = new Button();
		normal.setBounds(-360, 552, 64, 64, Component.ALIGN_BOTTOM);
		normal.setText(TextKey.createTextKey("Normal Grid"));
		axe = new Button();
		axe.setBounds(-360, 480, 64, 64, Component.ALIGN_BOTTOM);
		axe.setText(TextKey.createTextKey("Axe"));
		pickaxe = new Button();
		pickaxe.setBounds(-360, 408, 64, 64, Component.ALIGN_BOTTOM);
		pickaxe.setText(TextKey.createTextKey("Pickaxe"));
		shovel = new Button();
		shovel.setBounds(-360, 336, 64, 64, Component.ALIGN_BOTTOM);
		shovel.setText(TextKey.createTextKey("Shovel"));
		sword = new Button();
		sword.setBounds(-360, 264, 64, 64, Component.ALIGN_BOTTOM);
		sword.setText(TextKey.createTextKey("Sword"));
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
				newInv[32] = new InventorySlot(in.getStack(0), -96, 552, Component.ALIGN_BOTTOM); // head
				newInv[33] = new InventorySlot(in.getStack(1), -128, 480, Component.ALIGN_BOTTOM); // binding
				newInv[34] = new InventorySlot(in.getStack(2), -96, 408, Component.ALIGN_BOTTOM); // handle
				newInv[35] = new InventorySlot(in.getStack(3), 32, 480, Component.ALIGN_BOTTOM, true); // new tool
				
				break;
			case NORMAL:
				newInv = new InventorySlot[42];
				newInv[32] = new InventorySlot(in.getStack(0), -128, 408, Component.ALIGN_BOTTOM);
				newInv[33] = new InventorySlot(in.getStack(3), -64, 408, Component.ALIGN_BOTTOM);
				newInv[34] = new InventorySlot(in.getStack(6), 0, 408, Component.ALIGN_BOTTOM);
				newInv[35] = new InventorySlot(in.getStack(1), -128, 480, Component.ALIGN_BOTTOM);
				newInv[36] = new InventorySlot(in.getStack(4), -64, 480, Component.ALIGN_BOTTOM);
				newInv[37] = new InventorySlot(in.getStack(7), 0, 480, Component.ALIGN_BOTTOM);
				newInv[38] = new InventorySlot(in.getStack(2), -128, 552, Component.ALIGN_BOTTOM);
				newInv[39] = new InventorySlot(in.getStack(5), -64, 552, Component.ALIGN_BOTTOM);
				newInv[40] = new InventorySlot(in.getStack(8), 0, 552, Component.ALIGN_BOTTOM);
				newInv[41] = new InventorySlot(in.getStack(9), 92, 480, Component.ALIGN_BOTTOM, true); // crafting result
				
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
			if(inv[i].grabWithMouse(mouse, carried, win.getWidth()/2, win.getHeight())) {
				if(craftingMode == Mode.NORMAL) {
					if (i == inv.length-1 && carried.getItem() != null) {
						// Remove one of each of the items in the crafting grid.
						for(int j = 32; j < inv.length-1; j++) {
							inv[j].reference.add(-1);
						}
					}
				} else {
					if (i == inv.length-1 && carried.getItem() != null) {
						// Remove items in the crafting grid.
						int[] items;
						switch(craftingMode) {
							case AXE:
								items = Axe.craftingAmount(inv[32].reference, inv[33].reference, inv[34].reference, Cubyz.surface.getCurrentRegistries());
								break;
							case PICKAXE:
								items = Pickaxe.craftingAmount(inv[32].reference, inv[33].reference, inv[34].reference, Cubyz.surface.getCurrentRegistries());
								break;
							case SHOVEL:
								items = Shovel.craftingAmount(inv[32].reference, inv[33].reference, inv[34].reference, Cubyz.surface.getCurrentRegistries());
								break;
							case SWORD:
								items = Sword.craftingAmount(inv[32].reference, inv[33].reference, inv[34].reference, Cubyz.surface.getCurrentRegistries());
								break;
							default:
								return;
						}
						
						for(int j = 32; j < inv.length-1; j++) {
							inv[j].reference.add(-items[j-32]);
						}
					}
				}
			}
			if(i >= 32) {
				// If one of the crafting slots was changed, check if the recipe is changed, too.
				checkCrafting();
			}
		}
	}
	
	@Override
	public void setInventory(Inventory in) {
		this.in = in;
		inv = new InventorySlot[32];
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
		updateMode(Mode.NORMAL);
	}
	
	/**
	 * Checks if the recipe is valid and adds the corresponding item in the output slot.
	 */
	private void checkCrafting() {
		Item item = null;
		inv[inv.length-1].reference.clear();
		switch(craftingMode) {
			case AXE:
				item = Axe.canCraft(inv[32].reference, inv[33].reference, inv[34].reference, Cubyz.surface.getCurrentRegistries());
				break;
			case PICKAXE:
				item = Pickaxe.canCraft(inv[32].reference, inv[33].reference, inv[34].reference, Cubyz.surface.getCurrentRegistries());
				break;
			case SHOVEL:
				item = Shovel.canCraft(inv[32].reference, inv[33].reference, inv[34].reference, Cubyz.surface.getCurrentRegistries());
				break;
			case SWORD:
				item = Sword.canCraft(inv[32].reference, inv[33].reference, inv[34].reference, Cubyz.surface.getCurrentRegistries());
				break;
			case NORMAL:
				// Find out how many and which items are in the crafting grid:
				int num = 0;
				Item[] items = new Item[9];
				for(int i = 0; i < 9; i++) {
					items[i] = inv[32 + i].reference.getItem();
					if(items[i] != null)
						num++;
				}
				Recipe[] recipes = CubyzRegistries.RECIPE_REGISTRY.registered(new Recipe[0]);
				// Find a fitting recipe:
				for(int i = 0; i < recipes.length; i++) {
					Recipe rec = (Recipe) recipes[i];
					if(rec.getNum() != num)
						continue;
					item = rec.canCraft(items, 3);
					if(item != null) {
						inv[41].reference.setItem(item);
						inv[41].reference.add(rec.getNumRet());
						return;
					}
				}
				break;
		}
		if(item != null) {
			inv[inv.length - 1].reference.setItem(item);
			inv[inv.length - 1].reference.add(1);
		}
	}
	
	@Override
	public void render(long nvg, Window win) {
		super.render(nvg, win);

		normal.render(nvg, win);
		axe.render(nvg, win);
		pickaxe.render(nvg, win);
		shovel.render(nvg, win);
		sword.render(nvg, win);
	}

}
