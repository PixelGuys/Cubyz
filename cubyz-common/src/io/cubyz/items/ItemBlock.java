package io.cubyz.items;

import io.cubyz.blocks.Block;

public class ItemBlock extends Item {

	public ItemBlock(Block block) {
		this.fullTexturePath = "block/" + block.getTexture();
		this.itemDisplayName = block.getClass().getSimpleName();
	}
	
}
