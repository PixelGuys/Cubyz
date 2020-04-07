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
	}
	
}
