package cubyz.client.entity;

import cubyz.client.Cubyz;
import cubyz.gui.input.Keybindings;
import cubyz.multiplayer.Protocols;
import cubyz.rendering.Camera;
import cubyz.world.ChunkData;
import cubyz.world.NormalChunk;
import cubyz.world.World;
import cubyz.world.blocks.Blocks;
import cubyz.world.blocks.BlockInstance;
import cubyz.world.blocks.Blocks.BlockClass;
import cubyz.world.entity.Entity;
import cubyz.world.entity.Player;
import cubyz.world.items.Inventory;
import cubyz.world.items.Item;
import cubyz.world.items.ItemBlock;
import cubyz.world.items.ItemStack;
import cubyz.world.items.tools.Tool;

public class ClientPlayer extends Player {
	private long nextBreak = System.currentTimeMillis();
	private long nextBuild = System.currentTimeMillis();

	private long lastUpdateTime = 0;


	public ClientPlayer(World world, int id) {
		super(world, "");
		this.id = id;
	}
	
	public void update() {
		long newTime = System.currentTimeMillis();
		float deltaTime = (newTime - lastUpdateTime)/1000.0f;
		if (lastUpdateTime == 0) {
			lastUpdateTime = newTime;
			return;
		}
		lastUpdateTime = newTime;
		
		double px = Cubyz.player.getPosition().x;
		double py = Cubyz.player.getPosition().y;
		double pz = Cubyz.player.getPosition().z;
		NormalChunk ch = Cubyz.world.getChunk((int) px, (int) py, (int) pz);
		if (ch == null || !ch.isGenerated()) {
			if (ch != null)
				Cubyz.world.queueChunks(new ChunkData[] {ch}); // Seems like the chunk didn't get loaded correctly.
			return;
		}
		if (Cubyz.gameUI.doesGUIPauseGame() || Cubyz.world == null) {
			return;
		}
		if (!Cubyz.gameUI.doesGUIBlockInput()) {
			move(Cubyz.playerInc, Camera.getRotation());
			if (Keybindings.isPressed("destroy")) {
				//Breaking Blocks
				Object selected = Cubyz.msd.getSelected();
				if (isFlying()) { // Ignore hardness when in flying.
					if(newTime - nextBreak > 0) {
						nextBreak = newTime + 250;
						if (selected instanceof BlockInstance && Blocks.blockClass(((BlockInstance)selected).getBlock()) != BlockClass.UNBREAKABLE) {
							Cubyz.world.updateBlock(((BlockInstance)selected).x, ((BlockInstance)selected).y, ((BlockInstance)selected).z, 0);
						}
					}
				} else {
					if (selected instanceof BlockInstance) {
						breaking((BlockInstance)selected, Cubyz.inventorySelection, Cubyz.world);
					}
				}
				// Hit entities:
				if (selected instanceof Entity) {
					Item heldItem = getInventory_AND_DONT_FORGET_TO_SEND_CHANGES_TO_THE_SERVER().getItem(Cubyz.inventorySelection);
					((Entity)selected).hit(heldItem instanceof Tool ? (Tool)heldItem : null, Camera.getViewMatrix().positiveZ(Cubyz.dir).negate());
				}
			} else {
				resetBlockBreaking();
			}
			if (Keybindings.isPressed("place/use") && (newTime - nextBuild > 0)) {
				Object selected = Cubyz.msd.getSelected();
				if (selected instanceof BlockInstance && Blocks.onClick(((BlockInstance)selected).getBlock(), Cubyz.world, ((BlockInstance)selected).getPosition())) {
					// Interact with block(potentially do a hand animation, in the future).
				} else if (getInventory_AND_DONT_FORGET_TO_SEND_CHANGES_TO_THE_SERVER().getItem(Cubyz.inventorySelection) instanceof ItemBlock) {
					// Build block:
					if (selected != null) {
						nextBuild = newTime + 250;
						ItemStack stack = getInventory_AND_DONT_FORGET_TO_SEND_CHANGES_TO_THE_SERVER().getStack(Cubyz.inventorySelection);
						int oldAmount = stack.getAmount();
						Cubyz.msd.placeBlock(stack, Cubyz.world);
						if(oldAmount != stack.getAmount()) {
							Protocols.GENERIC_UPDATE.sendInventory_ItemStack_add(Cubyz.world.serverConnection, Cubyz.inventorySelection, stack.getAmount() - oldAmount);
						}
					}
				} else if (getInventory_AND_DONT_FORGET_TO_SEND_CHANGES_TO_THE_SERVER().getItem(Cubyz.inventorySelection) != null) {
					// Use item:
					if (getInventory_AND_DONT_FORGET_TO_SEND_CHANGES_TO_THE_SERVER().getItem(Cubyz.inventorySelection).onUse(Cubyz.player)) {
						getInventory_AND_DONT_FORGET_TO_SEND_CHANGES_TO_THE_SERVER().getStack(Cubyz.inventorySelection).add(-1);
						Protocols.GENERIC_UPDATE.sendInventory_ItemStack_add(Cubyz.world.serverConnection, Cubyz.inventorySelection, -1);
						nextBuild = newTime + 250;
					}
				}
			}
		}
		Cubyz.playerInc.x = Cubyz.playerInc.y = Cubyz.playerInc.z = 0.0F; // Reset positions
		super.update(deltaTime);
		Cubyz.world.getLocalPlayer().getPosition().set(position); // TODO: Correctly send update information to the server.
	}

	public Inventory getInventory() {
		throw new IllegalStateException("You must not access the player inventory directly. This would cause synchronization issues.");
	}

	/**
	 * To send changes to the server, look at the GenericUpdateProtocol.
	 * @return
	 */
	public Inventory getInventory_AND_DONT_FORGET_TO_SEND_CHANGES_TO_THE_SERVER() {
		return super.getInventory();
	}

	@Override
	protected int getBlock(int x, int y, int z) {
		return Cubyz.world.getBlock(x, y, z);
	}

	@Override
	public World getWorld() {
		return Cubyz.world;
	}
}
