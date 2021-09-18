package cubyz.world.blocks;

import java.awt.image.BufferedImage;
import java.util.ArrayList;

import cubyz.utils.datastructures.PixelUtils;

public class CrystalTextureProvider implements TextureProvider {

	@Override
	public void generateTexture(CustomBlock block, ArrayList<BufferedImage> textures, ArrayList<String> ids) {
		BufferedImage template = TextureProvider.getImage("assets/cubyz/blocks/textures/crystal_template_0.png");
		PixelUtils.convertTemplate(template, block.color);
		for(int i = 0; i < 6; i++) {
			block.textureIndices[i] = textures.size();
		}
		textures.add(template);
		ids.add(block.getRegistryID().toString());
	}

}
