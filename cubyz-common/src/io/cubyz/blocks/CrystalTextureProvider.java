package io.cubyz.blocks;

import java.awt.image.BufferedImage;

import io.cubyz.util.ColorUtils;

public class CrystalTextureProvider implements TextureProvider {
	
	public static void convertTemplate(BufferedImage tem, int color) {
		color |= 0x1f1f1f; // Prevent overflows.
		for(int x = 0; x < tem.getWidth(); x++) {
			for(int y = 0; y < tem.getHeight(); y++) {
				int hsvItem = ColorUtils.getHSV(color);
				int hsvTemp = tem.getRGB(x, y);
				int a = hsvTemp >>> 24;
				int h1 =  (hsvItem >>> 16) & 255;
				int s1 = (hsvItem >>> 8) & 255;
				int v1 = (hsvItem >>> 0) & 255;
				int h2 =  (hsvTemp >>> 16) & 255;
				int s2 = (hsvTemp >>> 8) & 255;
				if(s2 >= 128) s2 |= 0xffffff00;
				int v2 = (hsvTemp >>> 0) & 255;
				if(v2 >= 128) v2 |= 0xffffff00;
				h2 += h1;
				s2 += s1;
				v2 += v1;
				h2 &= 255;
				s2 = Math.max(0, Math.min(s2, 255));
				v2 = Math.max(0, Math.min(v2, 255));
				int resHSV = (h2 << 16) | (s2 << 8) | v2;
				tem.setRGB(x, y, ColorUtils.getRGB(resHSV) | (a << 24));
			}
		}
	}

	@Override
	public BufferedImage generateTexture(CustomBlock block) {
		BufferedImage template = TextureProvider.getImage("addons/cubyz/blocks/textures/crystal_template_0.png");
		convertTemplate(template, block.color);
		return template;
	}

}
