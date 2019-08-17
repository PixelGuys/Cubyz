package io.cubyz.ui.components;

import java.awt.Rectangle;

import org.joml.Vector2d;
import org.jungle.MouseInput;
import org.jungle.Window;
import org.jungle.hud.Font;

import io.cubyz.items.Item;
import io.cubyz.items.ItemStack;
import io.cubyz.ui.Component;
import io.cubyz.ui.NGraphics;

// GUI for an inventory slot referencing an ItemStack somewhere else.
public class InventorySlot extends Component {
	public static final int SLOTSIZE = 64;
	public static final int SLOT = NGraphics.loadImage("assets/cubyz/guis/inventory/inventory_slot.png");

	private boolean pressed = false;
	
	// WARNING: The y-axis for this element goes from bottom to top!
	
	public ItemStack reference;
	
	private Label inv;
	
	public InventorySlot(ItemStack ref, int x, int y) {
		reference = ref;
		inv = new Label();
		inv.setFont(new Font("Default", 16.f));
		this.x = x;
		this.y = y;
		width = height = SLOTSIZE;
	}
	
	public boolean isInside(Vector2d vec, int width, int height) {
		Rectangle hitbox = new Rectangle(width+this.x, height-this.y, this.width, this.height);
		return hitbox.contains(vec.x, vec.y);
	}
	
	public ItemStack grabWithMouse(MouseInput mouse, ItemStack carried, int width, int height) {
		if(!isInside(mouse.getCurrentPos(), width, height))
			return null;
		if(mouse.isLeftButtonPressed()) {
			pressed = true;
			return null;
		}
		if(!pressed)
			return null;
		
		// If the mouse button was just released inside after pressing:
		// Remove the ItemStack from this slot and replace with the one carried by the mouse.
		// Actual replacement in the inventory is done elsewhere.
		pressed = false;
		ItemStack ret = reference;
		reference = carried;
		return ret;
	}

	@Override
	public void render(long nvg, Window win) {
		NGraphics.drawImage(SLOT, win.getWidth()/2 + x, win.getHeight() - y, width, height);
		Item item = reference.getItem();
		if(item != null) {
			if(item.getImage() == -1) {
				item.setImage(NGraphics.loadImage(item.getTexture()));
			}
			NGraphics.drawImage(item.getImage(), win.getWidth()/2 + x + 4, win.getHeight() - y + 4, width - 8, height - 8);
			inv.setText("" + reference.getAmount());
			inv.setPosition(win.getWidth()/2 + x + 50, win.getHeight() - y + 48);
			inv.render(nvg, win);
		}
	}

}
