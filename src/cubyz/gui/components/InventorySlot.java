package cubyz.gui.components;

import java.awt.Rectangle;

import org.joml.Vector2d;

import cubyz.client.GameLauncher;
import cubyz.gui.Component;
import cubyz.gui.NGraphics;
import cubyz.gui.input.Mouse;
import cubyz.rendering.Font;
import cubyz.rendering.Graphics;
import cubyz.rendering.Texture;
import cubyz.world.blocks.Block;
import cubyz.world.items.Item;
import cubyz.world.items.ItemBlock;
import cubyz.world.items.ItemStack;
import cubyz.world.items.tools.Modifier;
import cubyz.world.items.tools.Tool;

/**
 * GUI for an inventory slot referencing an ItemStack.
 */


public class InventorySlot extends Component {
	public static final int SLOT_SIZE = 64;
	public static Texture SLOT_IMAGE = Texture.loadFromFile("assets/cubyz/guis/inventory/inventory_slot.png");

	/**State of mouse buttons if the mouse is in the area.*/
	private boolean pressedLeft = false, pressedRight = false;
	public boolean takeOnly;
	
	// WARNING: The y-axis for this element goes from bottom to top!
	
	public ItemStack reference;
	
	private Label inv;
	
	public InventorySlot(ItemStack ref, int x, int y, byte align, boolean takeOnly) {
		reference = ref;
		inv = new Label();
		inv.setFont(new Font("Default", 16.f));
		setBounds(x, y, SLOT_SIZE, SLOT_SIZE, align);
		this.takeOnly = takeOnly;
	}
	public InventorySlot(ItemStack ref, int x, int y, byte align) {
		this(ref, x, y, align, false);
	}
	
	public boolean isInside(Vector2d vec, int width, int height) {
		Rectangle hitbox = new Rectangle(width+this.getX(), height-this.getY(), this.width, this.height);
		return hitbox.contains(vec.x, vec.y);
	}
	
	public void drawTooltip(int width, int height) {
		Item item = reference.getItem();
		if(item != null) {
			if(isInside(Mouse.getCurrentPos(), width, height)) {
				double x = Mouse.getX() + 10;
				double y = Mouse.getY() + 10;
				String tooltip;
				if(item instanceof Tool) {
					tooltip = item.getName() == null ? "???" : item.getName().getTranslation();
					for(Modifier m : ((Tool)item).getModifiers()) {
						tooltip += "\n"+m.getName()+"\n"+m.getDescription()+"\n";
					}
				} else {
					tooltip = item.getName() == null ? "???" : item.getName().getTranslation();
				}
				float[] bounds = NGraphics.getTextSize(tooltip);
				Graphics.setColor(0x141414);
				Graphics.fillRect((float)x, (float)y, bounds[0], bounds[1]);
				Graphics.setColor(0x7F7F7F);
				Graphics.drawRect((int)x, (int)y, (int)bounds[0], (int)bounds[1]);
				NGraphics.setColor(255, 255, 255);
				NGraphics.drawText((int) x, (int) y, tooltip);
			}
		}
	}
	
	public boolean grabWithMouse(ItemStack carried, int width, int height) {
		if(!isInside(Mouse.getCurrentPos(), width, height)) {
			if(!pressedLeft && !pressedRight)
				return false;
			// If the right button was pressed above this, put one item down as soon as the mouse is outside:
			if(pressedRight && carried.getItem() != null) {
				if(reference.getItem() == carried.getItem()) {
					if(reference.add(1) != 0)
						carried.add(-1);
				}
				if(reference.getItem() == null) {
					reference.setItem(carried.getItem());
					reference.setAmount(1);
					carried.add(-1);
				}
				pressedRight = false;
				return true;
			}
		}
		// Only do something when the button is released:
		if(Mouse.isLeftButtonPressed()) {
			pressedLeft = true;
			return false;
		}
		if(Mouse.isRightButtonPressed()) {
			pressedRight = true;
			return false;
		}
		if(!pressedLeft && !pressedRight)
			return false;
		
		if(takeOnly) {
			pressedRight = pressedLeft = false;
			// Take all items from this slot if possible, no matter what button is pressed:
			if(carried.getItem() == null) {
				if(reference.getItem() == null) return true;
				carried.setItem(reference.getItem());
			} else if(carried.getItem() != reference.getItem()) {
				return false; // Cannot pick it up.
			}
			if(carried.canAddAll(reference.getAmount())) {
				carried.add(reference.getAmount());
				reference.clear();
				return true;
			}
			return false;
		}
		if(pressedRight && carried.getItem() != null) {
			if(reference.getItem() == carried.getItem()) {
				if(reference.add(1) != 0)
					carried.add(-1);
			}
			if(reference.getItem() == null) {
				reference.setItem(carried.getItem());
				reference.setAmount(1);
				carried.add(-1);
			}
			pressedRight = false;
			return true;
		}
		pressedRight = false;
		// If the mouse button was just released inside after pressing:
		// Remove the ItemStack from this slot and replace with the one carried by the mouse.
		// Actual replacement in the inventory is done elsewhere.
		pressedLeft = false;
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
	public void render(long nvg, int x, int y) {
		Graphics.drawImage(SLOT_IMAGE, x, y, width, height);
		Item item = reference.getItem();
		if(item != null) {
			if(item.getImage() == null) {
				if (item instanceof ItemBlock) {
					ItemBlock ib = (ItemBlock) item;
					Block b = ib.getBlock();
					if (item.getTexture() != null) {
						item.setImage(Texture.loadFromFile(item.getTexture()));
					} else {
						item.setImage(GameLauncher.logic.blockPreview(b).getColorTexture());
					}
				} else {
					item.setImage(Texture.loadFromFile(item.getTexture()));
				}
			}
			Graphics.drawImage(item.getImage(), x + 4, y + 4, width - 8, height - 8);
			if(Tool.class.isInstance(item)) {
				Tool tool = (Tool)item;
				float durab = tool.durability();
				Graphics.setColor((int)((1.0f - durab)*255.0f)<<16 | (int)(durab*255.0f)<<8 | 0);
				Graphics.fillRect(x + 8, y + 56, 48.0f*durab, 4);
				NGraphics.setColor(0, 0, 0);
			}
			inv.setText("" + reference.getAmount());
			inv.render(nvg, x + 50, y + 48);
		}
	}

}
