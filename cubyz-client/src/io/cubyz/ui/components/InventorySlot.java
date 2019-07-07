package io.cubyz.ui.components;

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
	
	// WARNING: The y-axis for this element goes from bottom to top!
	
	ItemStack reference;
	
	private Label inv;
	
	public InventorySlot(ItemStack ref, int x, int y) {
		reference = ref;
		inv = new Label();
		inv.setFont(new Font("OpenSans Bold", 16.f));
		this.x = x;
		this.y = y;
		width = height = SLOTSIZE;
	}

	@Override
	public void render(long nvg, Window win) {
		NGraphics.drawImage(SLOT, win.getWidth()/2 + x, win.getHeight() - y, width, height);
		Item item = reference.getItem();
		if(item != null) {
			if(item.getImage() == -1) {
				item.setImage(NGraphics.loadImage(item.getTexture()));
			}
			NGraphics.drawImage(item.getImage(), win.getWidth()/2 + x + 2, win.getHeight() - y + 2, width - 4, height - 4);
			inv.setText("" + reference.getAmount());
			inv.setPosition(win.getWidth()/2 + x + 50, win.getHeight() - y + 48);
			inv.render(nvg, win);
		}
	}

}
