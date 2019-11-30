package io.cubyz.entity;

import org.joml.Vector3f;
import org.joml.Vector3i;

import io.cubyz.api.Resource;
import io.cubyz.blocks.Block.BlockClass;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.items.Inventory;
import io.cubyz.items.tools.Tool;
import io.cubyz.ndt.NDTContainer;
import io.cubyz.world.World;

public class PlayerEntity extends EntityType {

	public static class PlayerImpl extends Player {
		
		private boolean flying = false;
		private Inventory inv = new Inventory(37); // 4*8 normal inventory + 4 crafting slots + 1 crafting result slot.
		private BlockInstance toBreak = null;
		private long timeStarted = 0;
		private int maxTime = -1;
		private int breakingSlot = -1; // Slot used to break the block. Slot change results in restart of block breaking.
		
		@Override
		public boolean isFlying() {
			return flying;
		}
		
		@Override
		public void setFlying(boolean fly) {
			flying = fly;
		}
		
		public long getRemainingBreakTime() {
			return (maxTime+timeStarted) - System.currentTimeMillis();
		}
		
		@Override
		public void move(Vector3f inc, Vector3f rot) {
			float deltaX = 0;
			float deltaZ = 0;
			if (inc.z != 0) {
				deltaX += (float) Math.sin(Math.toRadians(rot.y)) * -1.0F * inc.z;
				deltaZ += (float) Math.cos(Math.toRadians(rot.y)) * inc.z;
			}
			if (inc.x != 0) {
				deltaX += (float) Math.sin(Math.toRadians(rot.y - 90)) * -1.0F * inc.x;
				deltaZ += (float) Math.cos(Math.toRadians(rot.y - 90)) * inc.x;
			}
			if (inc.y != 0) {
				vy = inc.y;
			}
			if(deltaX != 0)
				deltaX = _getX(deltaX);
			if(deltaZ != 0)
				deltaZ = _getZ(deltaZ);
			position.add(deltaX, 0, deltaZ);
		}
		
		@Override
		public void update() {
			super.update();
			if (!flying) {
				vy -= 0.015F;
			}
			if (vy < 0) {
				Vector3i bp = new Vector3i(position.x + (int) Math.round(position.relX), (int) Math.floor(position.y), position.z + (int) Math.round(position.relZ));
				float relX = position.relX +0.5F - Math.round(position.relX);
				float relZ = position.relZ + 0.5F- Math.round(position.relZ);
				if(checkBlock(bp.x, bp.y, bp.z)) {
					vy = 0;
				}
				else if (relX < 0.3) {
					if (checkBlock(bp.x - 1, bp.y, bp.z)) {
						vy = 0;
					}
					else if (relZ < 0.3 && checkBlock(bp.x - 1, bp.y, bp.z - 1)) {
						vy = 0;
					}
					else if (relZ > 0.7 && checkBlock(bp.x - 1, bp.y, bp.z + 1)) {
						vy = 0;
					}
				}
				else if (relX > 0.7) {
					if (checkBlock(bp.x + 1, bp.y, bp.z)) {
						vy = 0;
					}
					else if (relZ < 0.3 && checkBlock(bp.x + 1, bp.y, bp.z - 1)) {
						vy = 0;
					}
					else if (relZ > 0.7 && checkBlock(bp.x + 1, bp.y, bp.z + 1)) {
						vy = 0;
					}
				}
				if (relZ < 0.3 && checkBlock(bp.x, bp.y, bp.z - 1)) {
					vy = 0;
				}
				else if (relZ > 0.7 && checkBlock(bp.x, bp.y, bp.z + 1)) {
					vy = 0;
				}
			}
			position.add(0, vy, 0);
			if (flying) {
				vy = 0;
			}
		}

		@Override
		public Inventory getInventory() {
			return inv;
		}

		@Override
		public void feedback(String feedback) {
			
		}
		
		@Override
		public void loadFrom(NDTContainer ndt) {
			super.loadFrom(ndt);
			if (ndt.hasKey("inventory")) {
				inv.loadFrom(ndt.getContainer("inventory"));
			}
		}
		
		@Override
		public NDTContainer saveTo(NDTContainer ndt) {
			ndt = super.saveTo(ndt);
			ndt.setContainer("inventory", inv.saveTo(new NDTContainer()));
			return ndt;
		}
		
		private void calculateBreakTime(BlockInstance bi, int slot) {
			if(bi == null || bi.getBlock().getBlockClass() == BlockClass.UNBREAKABLE) {
				return;
			}
			timeStarted = System.currentTimeMillis();
			maxTime = (int)(Math.round(bi.getBlock().getHardness()*200));
			if(Tool.class.isInstance(inv.getItem(slot))) {
				Tool tool = (Tool)inv.getItem(slot);
				if(tool.canBreak(bi.getBlock())) {
					maxTime = (int)(maxTime/tool.getSpeed());
				}
			}
		}

		@Override
		public void breaking(BlockInstance bi, int slot, World w) {
			if(bi != toBreak || breakingSlot != slot) {
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
				w.removeBlock(bi.getX(), bi.getY(), bi.getZ());
				if(w.getLocalPlayer().getInventory().addItem(bi.getBlock().getBlockDrop(), 1) != 0) {
					//DropItemOnTheGround(); //TODO: Add this function.
				}
			}
		}
	}

	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "player");
	}

	@Override
	public void setID(int ID) {}

	@Override
	public Entity newEntity() {
		return new PlayerImpl();
	}
	
}
