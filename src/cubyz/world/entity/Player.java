package cubyz.world.entity;

import org.joml.Vector3f;

import cubyz.api.CubyzRegistries;
import cubyz.command.CommandSource;
import cubyz.utils.json.JsonObject;
import cubyz.world.ServerWorld;
import cubyz.world.blocks.BlockInstance;
import cubyz.world.blocks.Block.BlockClass;
import cubyz.world.items.Inventory;
import cubyz.world.items.tools.Tool;

/**
 * Base class for both implementation and MP version of Player.
 * @author zenith391
 */

public class Player extends Entity implements CommandSource {
	public static final float cameraHeight = 1.7f;
	

	private boolean flying = false;
	private Inventory inv = new Inventory(32); // 4*8 normal inventory.
	private BlockInstance toBreak = null;
	private long timeStarted = 0;
	private int maxTime = -1;
	private int breakingSlot = -1; // Slot used to break the block. Slot change results in restart of block breaking.

	public Player(ServerWorld world) {
		super(CubyzRegistries.ENTITY_REGISTRY.getByID("cubyz:player"), null, world, 16, 16, 0.5f);
	}
	
	public boolean isFlying() {
		return flying;
	}
	
	public void setFlying(boolean fly) {
		flying = fly;
	}
	
	public long getRemainingBreakTime() {
		return (maxTime+timeStarted) - System.currentTimeMillis();
	}
	
	public void move(Vector3f inc, Vector3f rot) {
		// Store it locally so the hunger mechanics can still use it.
		vx = (float) Math.sin(rot.y) * -1.0F * inc.z + (float) Math.sin(rot.y - Math.PI/2) * -1.0F * inc.x;
		vz = (float) Math.cos(rot.y) * inc.z + (float) Math.cos(rot.y - Math.PI/2) * inc.x;
		if (inc.y != 0) {
			vy = inc.y;
		}
	}
	
	@Override
	public void update(float deltaTime) {
		if (!flying) {
			super.update(deltaTime);
		} else {
			position.add(vx*deltaTime, vy*deltaTime, vz*deltaTime);
			vy = 0;
		}
	}

	@Override
	public Inventory getInventory() {
		return inv;
	}

	@Override
	public void feedback(String feedback) {}
	
	@Override
	public void loadFrom(JsonObject json) {
		super.loadFrom(json);
		inv.loadFrom(json.getObjectOrNew("inventory"), world.getCurrentRegistries());
	}
	
	@Override
	public JsonObject save() {
		JsonObject json = super.save();
		json.put("inventory", inv.save());
		return json;
	}
	
	private void calculateBreakTime(BlockInstance bi, int slot) {
		if(bi == null || bi.getBlock().getBlockClass() == BlockClass.UNBREAKABLE) {
			return;
		}
		timeStarted = System.currentTimeMillis();
		maxTime = (int)(Math.round(bi.getBlock().getHardness()*200));
		if(inv.getItem(slot) instanceof Tool) {
			Tool tool = (Tool)inv.getItem(slot);
			if(tool.canBreak(bi.getBlock())) {
				maxTime = (int)(maxTime/tool.getSpeed());
			}
		}
	}

	public void breaking(BlockInstance bi, int slot, ServerWorld world) {
		if(bi != toBreak || breakingSlot != slot) {
			resetBlockBreaking(); // Make sure block breaking animation is reset.
			toBreak = bi;
			breakingSlot = slot;
			calculateBreakTime(bi, slot);
		}
		if(bi == null || bi.getBlock().getBlockClass() == BlockClass.UNBREAKABLE)
			return;
		long deltaTime = System.currentTimeMillis() - timeStarted;
		bi.setBreakingAnimation((float) deltaTime / (float) maxTime);
		if (deltaTime > maxTime) {
			if(Tool.class.isInstance(inv.getItem(slot))) {
				if(((Tool)inv.getItem(slot)).used()) {
					inv.getStack(slot).clear();
				}
			}
			world.removeBlock(bi.getX(), bi.getY(), bi.getZ());
		}
	}

	public void resetBlockBreaking() {
		if(toBreak != null) {
			toBreak.setBreakingAnimation(0);
			toBreak = null;
		}
	}

	@Override
	public ServerWorld getWorld() {
		return world;
	}
	
}
