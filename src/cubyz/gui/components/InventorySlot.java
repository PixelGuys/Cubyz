package cubyz.gui.components;

import java.awt.Rectangle;

import org.joml.Vector2d;

import cubyz.client.ItemTextures;
import cubyz.gui.input.Mouse;
import cubyz.rendering.Graphics;
import cubyz.rendering.Texture;
import cubyz.rendering.text.Fonts;
import cubyz.rendering.text.TextLine;
import cubyz.world.items.Item;
import cubyz.world.items.ItemStack;
import cubyz.world.items.tools.Tool;

import static cubyz.client.ClientSettings.GUI_SCALE;

/**
 * GUI for an inventory slot referencing an ItemStack.
 */


public class InventorySlot extends Component {
	public static final int SLOT_SIZE = 20;
	public static final Texture SLOT_IMAGE = Texture.loadFromFile("assets/cubyz/guis/inventory/inventory_slot.png");
	static float FONT_SIZE = 8;

	/**State of mouse buttons if the mouse is in the area.*/
	private boolean pressedLeft = false, pressedRight = false;
	public boolean takeOnly;

	public boolean renderFrame = true;
	
	// WARNING: The y-axis for this element goes from bottom to top!
	
	public ItemStack reference;
	
	private Label inv;
	
	public InventorySlot(ItemStack ref, int x, int y, byte align, boolean takeOnly) {
		reference = ref;
		inv = new Label();
		inv.setFontSize(FONT_SIZE * GUI_SCALE);
		inv.setTextAlign(Component.ALIGN_CENTER);
		setBounds(x, y, SLOT_SIZE * GUI_SCALE, SLOT_SIZE * GUI_SCALE, align);
		this.takeOnly = takeOnly;
	}
	public InventorySlot(ItemStack ref, int x, int y, byte align) {
		this(ref, x, y, align, false);
	}
	public InventorySlot(ItemStack ref) {
		this(ref, 0, 0, (byte) 0, false);
	}
	
	public boolean isInside(Vector2d vec, int width, int height) {
		Rectangle hitbox = new Rectangle(width+this.getX(), height-this.getY(), this.width, this.height);
		return hitbox.contains(vec.x, vec.y);
	}
	
	public void drawTooltip(int width, int height) {
		Item item = reference.getItem();
		if (item != null) {
			if (isInside(Mouse.getCurrentPos(), width, height)) {
				float x = (float)Mouse.getX() + 10;
				float y = (float)Mouse.getY() + 10;
				String tooltip;
				if (item instanceof Tool) {
					tooltip = item.getName() == null ? "???" : item.getName().getTranslation();
					Tool tool = (Tool) item;
					tooltip += "\nTime to swing: "+tool.swingTime+" s";
					tooltip += "\nPickaxe power: "+(int) (100*tool.pickaxePower)+" %";
					tooltip += "\nAxe power: "+(int) (100*tool.axePower)+" %";
					tooltip += "\nShovel power: "+(int) (100*tool.shovelPower)+" %";
					tooltip += "\nDurability: "+tool.durability+"/"+tool.maxDurability;
				} else {
					tooltip = item.getName() == null ? "???" : item.getName().getTranslation();
				}
				String[] lines = tooltip.split("\n");
				TextLine[] textLines = new TextLine[lines.length];
				float textWidth = 0;
				for(int i = 0; i < lines.length; i++) {
					textLines[i] = new TextLine(Fonts.PIXEL_FONT, "#ffffff"+lines[i], FONT_SIZE * GUI_SCALE, false);
					textWidth = Math.max(textWidth, textLines[i].getWidth());
				}
				float textHeight = lines.length * FONT_SIZE * GUI_SCALE;
				
				Graphics.setColor(0x141414);
				Graphics.fillRect(x, y, textWidth + 1, textHeight + 1);
				Graphics.setColor(0x7F7F7F);
				Graphics.drawRect((int)x, (int)y, (int)textWidth + 1, (int)textHeight + 1);
				for(int i = 0; i < textLines.length; i++) {
					textLines[i].render(x, y + i * FONT_SIZE * GUI_SCALE);
				}
			}
		}
	}
	
	public boolean grabWithMouse(ItemStack carried, int width, int height) {
		if (!isInside(Mouse.getCurrentPos(), width, height)) {
			if (!pressedLeft && !pressedRight)
				return false;
			// If the right button was pressed above this, put one item down as soon as the mouse is outside:
			if (pressedRight && carried.getItem() != null) {
				if (reference.getItem() == carried.getItem()) {
					if (reference.add(1) != 0)
						carried.add(-1);
				}
				if (reference.getItem() == null) {
					reference.setItem(carried.getItem());
					reference.setAmount(1);
					carried.add(-1);
				}
				pressedRight = false;
				return true;
			}
		}
		// Only do something when the button is released:
		if (Mouse.isLeftButtonPressed()) {
			pressedLeft = true;
			return false;
		}
		if (Mouse.isRightButtonPressed()) {
			pressedRight = true;
			return false;
		}
		if (!pressedLeft && !pressedRight)
			return false;
		
		if (takeOnly) {
			pressedRight = pressedLeft = false;
			// Take all items from this slot if possible, no matter what button is pressed:
			if (carried.getItem() == null) {
				if (reference.getItem() == null) return true;
				carried.setItem(reference.getItem());
			} else if (carried.getItem() != reference.getItem()) {
				return false; // Cannot pick it up.
			}
			if (carried.canAddAll(reference.getAmount())) {
				carried.add(reference.getAmount());
				reference.clear();
				return true;
			}
			return false;
		}
		if (pressedRight && carried.getItem() != null) {
			if (reference.getItem() == carried.getItem()) {
				if (reference.add(1) != 0)
					carried.add(-1);
			}
			if (reference.getItem() == null) {
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
		if (reference.getItem() == carried.getItem()) {
			if (reference.getItem() == null) return false;
			carried.add(-reference.add(carried.getAmount()));
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
	public void render(int x, int y) {
		if (renderFrame)
			Graphics.drawImage(SLOT_IMAGE, x, y, width, height);
		Item item = reference.getItem();
		if (item != null) {
			Graphics.drawImage(ItemTextures.getTexture(item), x + 2 * GUI_SCALE, y + 2 * GUI_SCALE, width - 4 * GUI_SCALE, height - 4 * GUI_SCALE);
			if (item instanceof Tool) {
				Tool tool = (Tool)item;
				int durab = tool.durability*255/tool.maxDurability;
				Graphics.setColor((255 - durab) << 16 | durab << 8 | 0);
				Graphics.fillRect(x + 2 * GUI_SCALE, y + 18 * GUI_SCALE, 16.0f / 255.0f * durab * GUI_SCALE, 2 * GUI_SCALE);
				Graphics.setColor(0xffffff);
			}
			if(reference.getAmount() != 1) {
				inv.setText("" + reference.getAmount());
				inv.render(x + 16 * GUI_SCALE, y + 16 * GUI_SCALE);
			}
		}
	}

}
