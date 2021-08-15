package cubyz.world.blocks;

import java.awt.image.BufferedImage;

import cubyz.utils.datastructures.PixelUtils;

public class CrystalTextureProvider implements TextureProvider {

	@Override
	public BufferedImage generateTexture(CustomBlock block) {
		BufferedImage template = TextureProvider.getImage("assets/cubyz/blocks/textures/crystal_template_0.png");
		PixelUtils.convertTemplate(template, block.color);
		return template;
	}

}
