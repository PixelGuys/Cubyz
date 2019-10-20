package io.cubyz.ui.components;

import java.awt.Rectangle;

import org.joml.Vector2d;
import org.jungle.MouseInput;
import org.jungle.Window;
import org.jungle.hud.Font;

import io.cubyz.items.Item;
import io.cubyz.items.ItemStack;
import io.cubyz.items.tools.Tool;
import io.cubyz.ui.Component;
import io.cubyz.ui.NGraphics;

// GUI for an inventory slot referencing an ItemStack somewhere else.
public class InventorySlot extends Component {
	public static final int SLOTSIZE = 64;
	public static final int SLOT = NGraphics.loadImage("assets/cubyz/guis/inventory/inventory_slot.png");

	private boolean pressed = false;
	private boolean pressedR = false;
	public boolean takeOnly;
	
	// WARNING: The y-axis for this element goes from bottom to top!
	
	public ItemStack reference;
	
	private Label inv;
	
	public InventorySlot(ItemStack ref, int x, int y, boolean takeOnly) {
		reference = ref;
		inv = new Label();
		inv.setFont(new Font("Default", 16.f));
		this.x = x;
		this.y = y;
		width = height = SLOTSIZE;
		this.takeOnly = takeOnly;
	}
	public InventorySlot(ItemStack ref, int x, int y) {
		this(ref, x, y, false);
	}
	
	public boolean isInside(Vector2d vec, int width, int height) {
		Rectangle hitbox = new Rectangle(width+this.x, height-this.y, this.width, this.height);
		return hitbox.contains(vec.x, vec.y);
	}
	
	public boolean grabWithMouse(MouseInput mouse, ItemStack carried, int width, int height) {
		if(takeOnly && carried.getItem() != null && reference.getItem() != null)
			return false;
		if(!isInside(mouse.getCurrentPos(), width, height))
			return false;
		if(mouse.isLeftButtonPressed()) {
			pressed = true;
			return false;
		}
		if(mouse.isRightButtonPressed()) {
			pressedR = true;
			return false;
		}
		if(!pressed && !pressedR)
			return false;
		if(pressedR && carried.getItem() != null) {
			if(reference.getItem() == carried.getItem()) {
				if(reference.add(1) != 0)
					carried.add(-1);
			}
			if(reference.getItem() == null) {
				reference.setItem(carried.getItem());
				reference.setAmount(1);
				carried.add(-1);
			}
			pressedR = false;
			return true;
		}
		pressedR = false;
		// If the mouse button was just released inside after pressing:
		// Remove the ItemStack from this slot and replace with the one carried by the mouse.
		// Actual replacement in the inventory is done elsewhere.
		pressed = false;
		if(reference.getItem() == carried.getItem()) {
			reference.setAmount(carried.getAmount() + reference.getAmount());
			carried.clear();
			return true;
		}
		Item buf = reference.getItem();
		int bufInt = reference.getAmount();
		reference.setItem(carried.getItem());
		reference.setAmount(carried.getAmount());
		carried.setItem(buf);
		carried.setAmount(bufInt);
		return true;
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
			if(Tool.class.isInstance(item)) {
				Tool tool = (Tool)item;
				float durab = tool.durability();
				NGraphics.setColor((int)((1.0f - durab)*255.0f), (int)(durab*255.0f), 0);
				NGraphics.fillRect(win.getWidth()/2 + x + 8, win.getHeight() - y + 56, (int)(48.0f*durab), 4);
				NGraphics.setColor(0, 0, 0);
			}
			inv.setText("" + reference.getAmount());
			inv.setPosition(win.getWidth()/2 + x + 50, win.getHeight() - y + 48);
			inv.render(nvg, win);
		}
	}

}
