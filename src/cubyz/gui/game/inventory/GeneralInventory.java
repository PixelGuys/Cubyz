package cubyz.gui.game.inventory;

import cubyz.multiplayer.Protocols;
import org.joml.Vector3f;

import cubyz.api.Resource;
import cubyz.client.Cubyz;
import cubyz.gui.MenuGUI;
import cubyz.gui.components.Component;
import cubyz.gui.components.InventorySlot;
import cubyz.gui.input.Mouse;
import cubyz.rendering.Graphics;
import cubyz.rendering.Window;
import cubyz.world.items.Item;
import cubyz.world.items.ItemStack;

import static cubyz.client.ClientSettings.GUI_SCALE;

/**
 * A class containing common functionality from all Inventory GUIs(tooltips, inventory slot movement, inventory slot drawing).
 */

public abstract class GeneralInventory extends MenuGUI {
	protected InventorySlot[] inv = null;

	/** ItemStack carried by the mouse.*/
	protected ItemStack carriedStack = new ItemStack();
	protected InventorySlot carried = null;

	protected int width, height;

	public GeneralInventory(Resource id) {
		super(id);
	}

	@Override
	public void close() {
		 // Place the last stack carried by the mouse in an empty slot.
		if (!carriedStack.empty()) {
			carriedStack.setAmount(Cubyz.player.getInventory_AND_DONT_FORGET_TO_SEND_CHANGES_TO_THE_SERVER().addItem(carriedStack.getItem(), carriedStack.getAmount()));
			if (!carriedStack.empty()) {
				Cubyz.world.drop(carriedStack, Cubyz.player.getPosition(), new Vector3f(), 0);
			}
		}
		Protocols.GENERIC_UPDATE.sendInventory_full(Cubyz.world.serverConnection, Cubyz.player.getInventory_AND_DONT_FORGET_TO_SEND_CHANGES_TO_THE_SERVER());
	}

	@Override
	public void init() {
		Mouse.setGrabbed(false);
		positionSlots();
	}

	@Override
	public void updateGUIScale() {
		positionSlots();
		carried = new InventorySlot(carriedStack);
	}

	@Override
	public void render() {
		if (carried == null) {
			carried = new InventorySlot(carriedStack);
			carried.renderFrame = false;
		}

		Graphics.setColor(0xDFDFDF);
		Graphics.fillRect(Window.getWidth()/2 - width/2, Window.getHeight()/2 - height/2, width, height);
		Graphics.setColor(0xFFFFFF);
		for(int i = 0; i < inv.length; i++) {
			inv[i].renderInContainer(Window.getWidth()/2 - width/2, Window.getHeight()/2 - height/2, width, height);
		}
		Graphics.setColor(0x000000);
		// Check if the mouse takes up a new ItemStack/sets one down.
		mouseAction();

		// Draw the stack carried by the mouse:
		Item item = carriedStack.getItem();
		if (item != null) {
			int x = (int)Mouse.getCurrentPos().x;
			int y = (int)Mouse.getCurrentPos().y;
			Graphics.setColor(0xFFFFFF);
			carried.setPosition(x - 16 * GUI_SCALE, y - 16 * GUI_SCALE, Component.ALIGN_TOP_LEFT);
			carried.render();
		}
		// Draw tooltips, when the nothing is carried.
		if (item == null) {
			for(int i = 0; i < inv.length; i++) { // tooltips
				inv[i].drawTooltip(Window.getWidth() / 2, Window.getHeight()/2+height/2);
			}
		}
	}

	@Override
	public boolean doesPauseGame() {
		return false;
	}

	protected abstract void positionSlots();

	protected abstract void mouseAction();
}
