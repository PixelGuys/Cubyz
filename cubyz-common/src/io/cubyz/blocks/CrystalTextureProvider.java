package io.cubyz.blocks;

import java.awt.image.BufferedImage;

import io.cubyz.util.PixelUtils;

public class CrystalTextureProvider implements TextureProvider {

	@Override
	public BufferedImage generateTexture(CustomBlock block) {
		BufferedImage template = TextureProvider.getImage("addons/cubyz/blocks/textures/crystal_template_0.png");
		PixelUtils.convertTemplate(template, block.color);
		return template;
	}

}
