package io.spacycubyd.blocks;

import io.spacycubyd.IRenderablePair;

public class Block {

	IRenderablePair pair;
	boolean transparent;
	boolean texConverted;
	private String id;
	private String texture;
	
	public String getTexture() {
		return texture;
	}
	
	protected void setTexture(String texture) {
		this.texture = texture;
	}
	
	public boolean isTransparent() {
		return transparent;
	}
	
	public IRenderablePair getBlockPair() {
		return pair;
	}
	
	public void setBlockPair(IRenderablePair pair) {
		this.pair = pair;
	}
	
	public boolean isTextureConverted() {
		return texConverted;
	}
	
	public void init() {}
	
	public String getID() {
		return id;
	}
	
	/**
	 * The ID can only be changed <b>BEFORE</b> registering the block.
	 * @param id
	 */
	protected void setID(String id) {
		this.id = id;
	}
	
}
