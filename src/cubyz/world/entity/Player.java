package cubyz.world.entity;

import org.joml.Vector3f;

import cubyz.api.CubyzRegistries;
import cubyz.command.CommandSource;
import cubyz.utils.json.JsonObject;
import cubyz.world.World;
import cubyz.world.blocks.BlockInstance;
import cubyz.world.blocks.Blocks;
import cubyz.world.blocks.Blocks.BlockClass;
import cubyz.world.items.Inventory;
import cubyz.world.items.tools.Tool;

/**
 * Base class for both implementation and MP version of Player.
 * @author zenith391
 */

public class Player extends Entity implements CommandSource {
	public static final float cameraHeight = 2.65f;
	

	private boolean flying = false;
	private Inventory inv = new Inventory(32); // 4*8 normal inventory.
	private BlockInstance toBreak = null;
	private long timeStarted = 0;
	private int maxTime = -1;
	private int breakingSlot = -1; // Slot used to break the block. Slot change results in restart of block breaking.

	public Player(World world) {
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
	
	public void setInventory(Inventory inv) {
		this.inv = inv;
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
	
	private boolean calculateBreakTime(BlockInstance bi, int slot) {
		if (bi == null || Blocks.blockClass(bi.getBlock()) == BlockClass.UNBREAKABLE) {
			return false;
		}
		float power = 0;
		float swingTime = 1;
		if (inv.getItem(slot) instanceof Tool) {
			Tool tool = (Tool)inv.getItem(slot);
			power = tool.getPower(bi.getBlock());
			swingTime = tool.swingTime;
		}
		if (power >= Blocks.breakingPower(bi.getBlock())) {
			timeStarted = System.currentTimeMillis();
			maxTime = (int)(Math.round(Blocks.hardness(bi.getBlock())*200));
			if (power != 0) {
				maxTime = (int)(maxTime*swingTime/power);
			}
			return true;
		}
		return false;
	}

	public void breaking(BlockInstance bi, int slot, World world) {
		if (bi != toBreak || breakingSlot != slot) {
			if (calculateBreakTime(bi, slot)) {
				resetBlockBreaking(); // Make sure block breaking animation is reset.
				toBreak = bi;
				breakingSlot = slot;
			} else {
				return;
			}
		}
		if (bi == null || Blocks.blockClass(bi.getBlock()) == BlockClass.UNBREAKABLE)
			return;
		long deltaTime = System.currentTimeMillis() - timeStarted;
		bi.breakAnim = (float) deltaTime / (float) maxTime;
		if (deltaTime > maxTime) {
			if (inv.getItem(slot) instanceof Tool) {
				if (((Tool)inv.getItem(slot)).onUse()) {
					inv.getStack(slot).clear();
				}
			}
			world.removeBlock(bi.x, bi.y, bi.z);
		}
	}

	public void resetBlockBreaking() {
		if (toBreak != null) {
			toBreak.breakAnim = 0;
			toBreak = null;
		}
	}

	@Override
	public World getWorld() {
		return world;
	}
	
}
