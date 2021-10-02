package cubyz.client.entity;

import cubyz.client.Cubyz;
import cubyz.gui.input.Keybindings;
import cubyz.rendering.Camera;
import cubyz.world.NormalChunk;
import cubyz.world.ServerWorld;
import cubyz.world.blocks.Block;
import cubyz.world.blocks.BlockInstance;
import cubyz.world.blocks.Block.BlockClass;
import cubyz.world.entity.Entity;
import cubyz.world.entity.Player;
import cubyz.world.items.ItemBlock;
import cubyz.world.items.tools.Tool;

public class ClientPlayer extends Player {
	private int breakCooldown = 10;
	private int buildCooldown = 10;

	private long lastUpdateTime = 0;


	public ClientPlayer(Player player) {
		super(null);
		this.id = player.id;
		this.position.set(player.getPosition());
	}
	
	public void update() {
		long newTime = System.currentTimeMillis();
		float deltaTime = (newTime - lastUpdateTime)/1000.0f;
		if(lastUpdateTime == 0) {
			lastUpdateTime = newTime;
			return;
		}
		lastUpdateTime = newTime;
		if(Cubyz.world.getChunk((int)Cubyz.player.getPosition().x >> NormalChunk.chunkShift, (int)Cubyz.player.getPosition().y >> NormalChunk.chunkShift, (int)Cubyz.player.getPosition().z >> NormalChunk.chunkShift) == null) return;
		if(Cubyz.gameUI.doesGUIPauseGame() || Cubyz.world == null) {
			return;
		}
		if (!Cubyz.gameUI.doesGUIBlockInput()) {
			move(Cubyz.playerInc, Camera.getRotation());
			if (breakCooldown > 0) {
				breakCooldown--;
			}
			if (buildCooldown > 0) {
				buildCooldown--;
			}
			if (Keybindings.isPressed("destroy")) {
				//Breaking Blocks
				if(isFlying()) { // Ignore hardness when in flying.
					if (breakCooldown == 0) {
						breakCooldown = 7;
						Object bi = Cubyz.msd.getSelected();
						if (bi != null && bi instanceof BlockInstance && ((BlockInstance)bi).getBlock().getBlockClass() != BlockClass.UNBREAKABLE) {
							Cubyz.world.removeBlock(((BlockInstance)bi).getX(), ((BlockInstance)bi).getY(), ((BlockInstance)bi).getZ());
						}
					}
				}
				else {
					Object selected = Cubyz.msd.getSelected();
					if(selected instanceof BlockInstance) {
						breaking((BlockInstance)selected, Cubyz.inventorySelection, Cubyz.world);
					}
				}
				// Hit entities:
				Object selected = Cubyz.msd.getSelected();
				if(selected instanceof Entity) {
					((Entity)selected).hit(getInventory().getItem(Cubyz.inventorySelection) instanceof Tool ? (Tool)getInventory().getItem(Cubyz.inventorySelection) : null, Camera.getViewMatrix().positiveZ(Cubyz.dir).negate());
				}
			} else {
				resetBlockBreaking();
			}
			if (Keybindings.isPressed("place/use") && buildCooldown <= 0) {
				if((Cubyz.msd.getSelected() instanceof BlockInstance) && ((BlockInstance)Cubyz.msd.getSelected()).getBlock().onClick(Cubyz.world, ((BlockInstance)Cubyz.msd.getSelected()).getPosition())) {
					// Interact with block(potentially do a hand animation, in the future).
				} else if(getInventory().getItem(Cubyz.inventorySelection) instanceof ItemBlock) {
					// Build block:
					if (Cubyz.msd.getSelected() != null) {
						buildCooldown = 10;
						Cubyz.msd.placeBlock(getInventory(), Cubyz.inventorySelection, Cubyz.world);
					}
				} else if(getInventory().getItem(Cubyz.inventorySelection) != null) {
					// Use item:
					if(getInventory().getItem(Cubyz.inventorySelection).onUse(Cubyz.player)) {
						getInventory().getStack(Cubyz.inventorySelection).add(-1);
						buildCooldown = 10;
					}
				}
			}
		}
		Cubyz.playerInc.x = Cubyz.playerInc.y = Cubyz.playerInc.z = 0.0F; // Reset positions
		super.update(deltaTime);
		Cubyz.world.getLocalPlayer().getPosition().set(position); // TODO: Correctly send update information to the server.
	}

	@Override
	protected Block getBlock(int x, int y, int z) {
		return Cubyz.world.getBlock(x, y, z);
	}
	@Override
	protected byte getBlockData(int x, int y, int z) {
		return Cubyz.world.getBlockData(x, y, z);
	}

	@Override
	public ServerWorld getWorld() {
		return Cubyz.world;
	}
}
