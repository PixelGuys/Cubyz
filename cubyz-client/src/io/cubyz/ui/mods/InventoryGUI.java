package io.cubyz.ui.mods;

import org.jungle.Keyboard;
import org.jungle.Window;
import org.jungle.hud.Font;
import org.lwjgl.glfw.GLFW;

import io.cubyz.client.Cubyz;
import io.cubyz.items.Inventory;
import io.cubyz.items.Item;
import io.cubyz.items.ItemStack;
import io.cubyz.items.Recipe;
import io.cubyz.ui.MenuGUI;
import io.cubyz.ui.NGraphics;
import io.cubyz.ui.components.InventorySlot;
import io.cubyz.ui.components.Label;

// TODO: add possibility to capture and release stacks with the mouse.

public class InventoryGUI extends MenuGUI {

	private InventorySlot inv [] = null;
	
	private ItemStack carried = new ItemStack(); // ItemStack currently carried by the mouse.
	private Label num;

	public void close() {
		Cubyz.mouse.setGrabbed(true);
		 // Place the last stack carried by the mouse in an empty slot.
		if(carried.getItem() != null) {
			for(int i = 0; i < inv.length; i++) {
				if(inv[i].reference.getItem() == null) {
					Cubyz.world.getLocalPlayer().getInventory().setSlot(carried, i);
					return;
				}
			}
			//DropItemStack(carried); //TODO!
		}
	}

	@Override
	public void init(long nvg) {
		Cubyz.mouse.setGrabbed(false);
		num = new Label();
		num.setFont(new Font("OpenSans Bold", 16.f));
		if(inv == null) {
			inv = new InventorySlot[37];
			Inventory inventory = Cubyz.world.getLocalPlayer().getInventory();
			for(int i = 0; i < 8; i++) {
				inv[i] = new InventorySlot(inventory.getStack(i), i*64-256, 64);
			}
			for(int i = 0; i < 8; i++) {
				inv[i+8] = new InventorySlot(inventory.getStack(i+8), i*64-256, 256);
			}
			for(int i = 0; i < 8; i++) {
				inv[i+16] = new InventorySlot(inventory.getStack(i+16), i*64-256, 320);
			}
			for(int i = 0; i < 8; i++) {
				inv[i+24] = new InventorySlot(inventory.getStack(i+24), i*64-256, 384);
			}
			inv[32] = new InventorySlot(inventory.getStack(32), 0, 544);
			inv[33] = new InventorySlot(inventory.getStack(33), 64, 544);
			inv[34] = new InventorySlot(inventory.getStack(34), 0, 480);
			inv[35] = new InventorySlot(inventory.getStack(35), 64, 480);
			inv[36] = new InventorySlot(inventory.getStack(36), 192, 512);
		}
	}

	@Override
	public void render(long nvg, Window win) {
		NGraphics.setColor(191, 191, 191);
		NGraphics.fillRect(win.getWidth()/2-288, win.getHeight()-576, 576, 576);
		NGraphics.setColor(0, 0, 0);
		for(int i = 0; i < inv.length; i++) {
			inv[i].render(nvg, win);
		}
		if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_ESCAPE)) {
			Cubyz.gameUI.setMenu(null);
			Cubyz.mouse.setGrabbed(true);
		}
		// Check if the mouse takes up a new ItemStack/sets one down.
		ItemStack newlyCarried;
		for(int i = 0; i < inv.length; i++) {
			newlyCarried = inv[i].grabWithMouse(Cubyz.mouse, carried, win.getWidth()/2, win.getHeight());
			if(newlyCarried != null) {
				Cubyz.world.getLocalPlayer().getInventory().setSlot(carried, i);
				carried = newlyCarried;
				if(i >= 32) {
					checkCrafting();
				}
			}
		}
		// Draw the stack carried by the mouse:
		Item item = carried.getItem();
		if(item != null) {
			if(item.getImage() == -1) {
				item.setImage(NGraphics.loadImage(item.getTexture()));
			}
			int x = (int)Cubyz.mouse.getCurrentPos().x;
			int y = (int)Cubyz.mouse.getCurrentPos().y;
			NGraphics.drawImage(item.getImage(), x - 32, y - 32, 64, 64);
			num.setText("" + carried.getAmount());
			num.setPosition(x + 50-32, y + 48-32);
			num.render(nvg, win);
		}
	}

	@Override
	public boolean doesPauseGame() {
		return false;
	}
	
	private void checkCrafting() {
		// Find out how many items are there in the grid and put them in an array:
		int num = 0;
		Item[] ar = new Item[4];
		for(int i = 0; i < 4; i++) {
			ar[i] = inv[32+i].reference.getItem();
			if(ar[i] != null)
				num++;
		}
		// Get the recipes for the given number of items:
		Recipe[] recipes = new Recipe[0];//TODO!
		// Find a fitting recipe:
		Item item = null;
		for(int i = 0; i < recipes.length; i++) {
			item = recipes[i].canCraft(ar, 4);
			if(item != null) {
				// TODO: add the recipes result to the appropiate slot.
				break;
			}
		}
	}
}