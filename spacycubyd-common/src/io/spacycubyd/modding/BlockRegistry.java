package io.spacycubyd.modding;

import java.util.Collection;
import java.util.HashMap;

import io.spacycubyd.CubzLogger;
import io.spacycubyd.blocks.Block;

public class BlockRegistry {

	private HashMap<String, Block> blocks;
	private boolean debug = true;
	private boolean alwaysError = Boolean.parseBoolean(System.getProperty("registry.dumpAsError", "true"));
	
	public BlockRegistry() {
		blocks = new HashMap<String, Block>();
	}
	
	public void register(Block block) {
		if (blocks.containsKey(block.getID())) {
			throw new IllegalStateException("Block with ID \"" + block.getID() + "\" is arleady registered!");
		}
		if (block.getID().equals("none")) {
			if (alwaysError) {
				throw new IllegalArgumentException("Block " + block.getClass().getName() + " does not have any ID set!");
			}
			CubzLogger.i.warning("Block " + block.getClass().getName() + " does not have any ID set. Skipping!");
			System.err.flush();
			return;
		}
		blocks.put(block.getID(), block);
		if (debug) {
			CubzLogger.i.info("Registered block " + block.getID());
		}
	}
	
	public void registerAll(Block... b) {
		for (Block bk : b) {
			register(bk);
		}
	}
	
	public Block getByID(String id) {
		return blocks.get(id);
	}
	
	public Collection<Block> getRegisteredBlocks() {
		return blocks.values();
	}
	
}
