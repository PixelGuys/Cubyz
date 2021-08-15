package cubyz.gui;

import org.joml.Vector3f;

import cubyz.api.Resource;
import cubyz.client.Cubyz;
import cubyz.client.GameLauncher;
import cubyz.client.rendering.Font;
import cubyz.client.rendering.Window;
import cubyz.gui.components.InventorySlot;
import cubyz.gui.components.Label;
import cubyz.gui.input.MouseInput;
import cubyz.world.items.Item;
import cubyz.world.items.ItemStack;

/**
 * A class containing common functionality from all Inventory GUIs(tooltips, inventory slot movement, inventory slot drawing).
 */

public abstract class GeneralInventory extends MenuGUI {
	protected InventorySlot inv [] = null;
	
	/** ItemStack carried by the mouse.*/
	protected ItemStack carried = new ItemStack();
	private Label num;
	
	protected int width, height;
	
	public GeneralInventory(Resource id) {
		super(id);
	}

	@Override
	public void close() {
		 // Place the last stack carried by the mouse in an empty slot.
		if(!carried.empty()) {
			carried.setAmount(Cubyz.player.getInventory().addItem(carried.getItem(), carried.getAmount()));
			if(!carried.empty()) {
				Cubyz.surface.drop(carried, Cubyz.player.getPosition(), new Vector3f(), 0);
			}
		}
	}

	@Override
	public void init(long nvg) {
		GameLauncher.input.mouse.setGrabbed(false);
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
		// Check if the mouse takes up a new ItemStack/sets one down.
		mouseAction(GameLauncher.input.mouse, win);
		
		// Draw the stack carried by the mouse:
		Item item = carried.getItem();
		if(item != null) {
			if(item.getImage() == -1) {
				item.setImage(NGraphics.loadImage(item.getTexture()));
			}
			int x = (int)GameLauncher.input.mouse.getCurrentPos().x;
			int y = (int)GameLauncher.input.mouse.getCurrentPos().y;
			NGraphics.drawImage(item.getImage(), x - 32, y - 32, 64, 64);
			num.setText("" + carried.getAmount());
			num.setPosition(x+50-32, y+48-32, Component.ALIGN_TOP_LEFT);
			num.render(nvg, win);
		}
		// Draw tooltips, when the nothing is carried.
		if(item == null) {
			for(int i = 0; i < inv.length; i++) { // tooltips
				inv[i].drawTooltip(GameLauncher.input.mouse, win.getWidth() / 2, win.getHeight());
			}
		}
	}

	@Override
	public boolean doesPauseGame() {
		return false;
	}
	
	protected abstract void positionSlots();
	
	protected abstract void mouseAction(MouseInput mouse, Window win);
}
