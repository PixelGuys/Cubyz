
package io.cubyz.blocks;

public class Grass extends Block {

	public Grass() {
		setID("cubyz:grass");
		setHardness(6);
		bc = BlockClass.SAND;
		texConverted = true; // texture already in runtime format
	}
	
}
