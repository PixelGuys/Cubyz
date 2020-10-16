package io.cubyz.ui;

import io.cubyz.api.Resource;
import io.cubyz.client.Cubyz;
import io.cubyz.items.Item;
import io.cubyz.items.ItemStack;
import io.cubyz.ui.components.InventorySlot;
import io.cubyz.ui.components.Label;
import io.jungle.MouseInput;
import io.jungle.Window;
import io.jungle.hud.Font;

/**
 * A class containing common functionality from all Inventory GUIs(tooltips, inventory slot movement, inventory slot drawing).
 */

public abstract class GeneralInventory extends MenuGUI {
	protected InventorySlot inv [] = null;
	
	protected ItemStack carried = new ItemStack(); // ItemStack currently carried by the mouse.
	private Label num;
	
	protected int width, height;
	
	public GeneralInventory(Resource id) {
		super(id);
	}

	public void close() {
		Cubyz.mouse.setGrabbed(true);
		 // Place the last stack carried by the mouse in an empty slot.
		if(carried.getItem() != null) {
			for(int i = 0; i < inv.length; i++) {
				if(inv[i].reference.getItem() == null && !inv[i].takeOnly) {
					Cubyz.world.getLocalPlayer().getInventory().setStack(i, carried);
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
		num.setFont(new Font("Default", 16.f));
		positionSlots();
	}

	@Override
	public void render(long nvg, Window win) {
		NGraphics.setColor(191, 191, 191);
		NGraphics.fillRect(win.getWidth()/2-width/2, win.getHeight()-height, width, height);
		NGraphics.setColor(0, 0, 0);
		for(int i = 0; i < inv.length; i++) {
			inv[i].render(nvg, win);
		}
		/*if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_ESCAPE)) {
			Cubyz.gameUI.setMenu(null);
			Cubyz.mouse.setGrabbed(true);
		}*/
		// Check if the mouse takes up a new ItemStack/sets one down.
		mouseAction(Cubyz.mouse, win);
		
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
		for(int i = 0; i < inv.length; i++) { // tooltips
			inv[i].drawTooltip(Cubyz.mouse, win.getWidth() / 2, win.getHeight());
		}
	}

	@Override
	public boolean doesPauseGame() {
		return false;
	}
	
	protected abstract void positionSlots();
	
	protected abstract void mouseAction(MouseInput mouse, Window win);
}
