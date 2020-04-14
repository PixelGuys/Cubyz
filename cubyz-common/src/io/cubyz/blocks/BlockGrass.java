package io.cubyz.blocks;

/*
 * Not the grassed dirt, separate for vegetation grass
 */
public class BlockGrass extends Block {

	public BlockGrass() {
		setID("cubyz:grass_vegetation");
		setHardness(0.3f);
		setSolid(false);
		bc = BlockClass.LEAF;
		transparent = true;
		absorption = 0x06080008; // Absorbs red and blue light.
	}
	
}
