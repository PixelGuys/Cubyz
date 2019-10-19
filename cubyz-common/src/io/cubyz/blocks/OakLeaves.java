package io.cubyz.blocks;

public class OakLeaves extends Block {

	public OakLeaves() {
		setID("cubyz:oak_leaves");
		setHardness(0.4f);
		bc = BlockClass.LEAF;
		this.transparent = true;
		this.degradable = true;
	}
	
}