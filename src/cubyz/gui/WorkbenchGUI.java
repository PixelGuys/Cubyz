package cubyz.gui;

import cubyz.api.Resource;
import cubyz.client.Cubyz;
import cubyz.gui.components.Button;
import cubyz.gui.components.InventorySlot;
import cubyz.rendering.Window;
import cubyz.utils.translate.TextKey;
import cubyz.world.items.Inventory;
import cubyz.world.items.Item;
import cubyz.world.items.tools.Axe;
import cubyz.world.items.tools.Pickaxe;
import cubyz.world.items.tools.Shovel;
import cubyz.world.items.tools.Sword;
import cubyz.world.items.tools.Tool;

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
		normal.setBounds(-424, 552, 128, 64, Component.ALIGN_BOTTOM);
		normal.setFontSize(32);
		normal.setText(TextKey.createTextKey("Grid"));
		axe = new Button();
		axe.setBounds(-424, 480, 128, 64, Component.ALIGN_BOTTOM);
		axe.setFontSize(32);
		axe.setText(TextKey.createTextKey("Axe"));
		pickaxe = new Button();
		pickaxe.setBounds(-424, 408, 128, 64, Component.ALIGN_BOTTOM);
		pickaxe.setFontSize(32);
		pickaxe.setText(TextKey.createTextKey("Pickaxe"));
		shovel = new Button();
		shovel.setBounds(-424, 336, 128, 64, Component.ALIGN_BOTTOM);
		shovel.setFontSize(32);
		shovel.setText(TextKey.createTextKey("Shovel"));
		sword = new Button();
		sword.setBounds(-424, 264, 128, 64, Component.ALIGN_BOTTOM);
		sword.setFontSize(32);
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
				newInv = new InventorySlot[58];
				newInv[32] = new InventorySlot(in.getStack(0), -192, 672, Component.ALIGN_BOTTOM);
				newInv[33] = new InventorySlot(in.getStack(1), -128, 672, Component.ALIGN_BOTTOM);
				newInv[34] = new InventorySlot(in.getStack(2), -64, 672, Component.ALIGN_BOTTOM);
				newInv[35] = new InventorySlot(in.getStack(3), 0, 672, Component.ALIGN_BOTTOM);
				newInv[36] = new InventorySlot(in.getStack(4), 64, 672, Component.ALIGN_BOTTOM);

				newInv[37] = new InventorySlot(in.getStack(5), -192, 608, Component.ALIGN_BOTTOM);
				newInv[38] = new InventorySlot(in.getStack(6), -128, 608, Component.ALIGN_BOTTOM);
				newInv[39] = new InventorySlot(in.getStack(7), -64, 608, Component.ALIGN_BOTTOM);
				newInv[40] = new InventorySlot(in.getStack(8), 0, 608, Component.ALIGN_BOTTOM);
				newInv[41] = new InventorySlot(in.getStack(9), 64, 608, Component.ALIGN_BOTTOM);

				newInv[42] = new InventorySlot(in.getStack(10), -192, 544, Component.ALIGN_BOTTOM);
				newInv[43] = new InventorySlot(in.getStack(11), -128, 544, Component.ALIGN_BOTTOM);
				newInv[44] = new InventorySlot(in.getStack(12), -64, 544, Component.ALIGN_BOTTOM);
				newInv[45] = new InventorySlot(in.getStack(13), 0, 544, Component.ALIGN_BOTTOM);
				newInv[46] = new InventorySlot(in.getStack(14), 64, 544, Component.ALIGN_BOTTOM);

				newInv[47] = new InventorySlot(in.getStack(15), -192, 480, Component.ALIGN_BOTTOM);
				newInv[48] = new InventorySlot(in.getStack(16), -128, 480, Component.ALIGN_BOTTOM);
				newInv[49] = new InventorySlot(in.getStack(17), -64, 480, Component.ALIGN_BOTTOM);
				newInv[50] = new InventorySlot(in.getStack(18), 0, 480, Component.ALIGN_BOTTOM);
				newInv[51] = new InventorySlot(in.getStack(19), 64, 480, Component.ALIGN_BOTTOM);

				newInv[52] = new InventorySlot(in.getStack(20), -192, 416, Component.ALIGN_BOTTOM);
				newInv[53] = new InventorySlot(in.getStack(21), -128, 416, Component.ALIGN_BOTTOM);
				newInv[54] = new InventorySlot(in.getStack(22), -64, 416, Component.ALIGN_BOTTOM);
				newInv[55] = new InventorySlot(in.getStack(23), 0, 416, Component.ALIGN_BOTTOM);
				newInv[56] = new InventorySlot(in.getStack(24), 64, 416, Component.ALIGN_BOTTOM);

				newInv[57] = new InventorySlot(in.getStack(25), 192, 544, Component.ALIGN_BOTTOM, true); // crafting result
				
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
		height = 704;
	}

	@Override
	protected void mouseAction() {
		for(int i = 0; i < inv.length; i++) {
			if(inv[i].grabWithMouse(carriedStack, Window.getWidth()/2, Window.getHeight())) {
				if(craftingMode == Mode.NORMAL) {
					if (i == inv.length-1 && carriedStack.getItem() != null) {
						// Remove one of each of the items in the crafting grid.
						for(int j = 32; j < inv.length-1; j++) {
							inv[j].reference.add(-1);
						}
					}
				} else {
					if (i == inv.length-1 && carriedStack.getItem() != null) {
						// Remove items in the crafting grid.
						int[] items;
						switch(craftingMode) {
							case AXE:
								items = Axe.craftingAmount(inv[32].reference, inv[33].reference, inv[34].reference, Cubyz.world.getCurrentRegistries());
								break;
							case PICKAXE:
								items = Pickaxe.craftingAmount(inv[32].reference, inv[33].reference, inv[34].reference, Cubyz.world.getCurrentRegistries());
								break;
							case SHOVEL:
								items = Shovel.craftingAmount(inv[32].reference, inv[33].reference, inv[34].reference, Cubyz.world.getCurrentRegistries());
								break;
							case SWORD:
								items = Sword.craftingAmount(inv[32].reference, inv[33].reference, inv[34].reference, Cubyz.world.getCurrentRegistries());
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
				item = Axe.canCraft(inv[32].reference, inv[33].reference, inv[34].reference, Cubyz.world.getCurrentRegistries());
				break;
			case PICKAXE:
				item = Pickaxe.canCraft(inv[32].reference, inv[33].reference, inv[34].reference, Cubyz.world.getCurrentRegistries());
				break;
			case SHOVEL:
				item = Shovel.canCraft(inv[32].reference, inv[33].reference, inv[34].reference, Cubyz.world.getCurrentRegistries());
				break;
			case SWORD:
				item = Sword.canCraft(inv[32].reference, inv[33].reference, inv[34].reference, Cubyz.world.getCurrentRegistries());
				break;
			case NORMAL:
				Item[] items = new Item[25];
				int num = 0;
				for(int i = 0; i < 25; i++) {
					if(inv[32 + i].reference.getItem() != null && inv[32 + i].reference.getItem().material != null) {
						items[i] = inv[32 + i].reference.getItem();
						num++;
					}
				}
				if(num != 0) {
					item = new Tool(items);
				}
				break;
		}
		if(item != null) {
			inv[inv.length - 1].reference.setItem(item);
			inv[inv.length - 1].reference.add(1);
		}
	}
	
	@Override
	public void render() {
		super.render();

		normal.render();
		axe.render();
		pickaxe.render();
		shovel.render();
		sword.render();
	}

}
