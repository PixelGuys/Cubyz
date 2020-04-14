package io.cubyz.blocks;

public class OakLeaves extends Block {

	public OakLeaves() {
		setID("cubyz:oak_leaves");
		setHardness(0.4f);
		bc = BlockClass.LEAF;
		this.transparent = true;
		this.degradable = true;
		absorption = 0x0f100010; // Absorbs red and blue light.
	}
	
}