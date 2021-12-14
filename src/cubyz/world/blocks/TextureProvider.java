package cubyz.world.blocks;

import java.awt.image.BufferedImage;
import java.io.File;
import java.util.Random;

import javax.imageio.ImageIO;

import cubyz.utils.Logger;

public interface TextureProvider {
	BufferedImage generateTexture(CustomOre block);
	
	public static int[] createColorPalette(CustomOre block, int differentColors, int brightnessScale, int randomAdditive) {
		int [] colors = new int[differentColors];
		Random rand = new Random(block.seed);
		for(int i = 0; i < differentColors; i++) { //TODO: Make sure the contrast fits everywhere and maybe use hue-shifting.
			int r = (block.color >>> 16) & 255;
			int g = (block.color >>> 8) & 255;
			int b = (block.color >>> 0) & 255;
			// Add a brightness value to the color:
			int brightness = (int)(-brightnessScale*(differentColors/2.0-i)/differentColors);
			if (brightness > 0) {
				brightness *= block.shinyness+1;
			}
			r += brightness;
			g += brightness;
			b += brightness;
			// make sure that once a color channel is satured the others get increased further:
			int totalDif = 0;
			if (r > 255) {
				totalDif += r-255;
			}
			if (g > 255) {
				totalDif += g-255;
			}
			if (b > 255) {
				totalDif += b-255;
			}
			totalDif = totalDif*3/2;
			r += totalDif;
			g += totalDif;
			b += totalDif;
			// Add some flavor to the color, so it's not just a scale based on lighting:
			r += rand.nextInt(randomAdditive*2) - randomAdditive;
			g += rand.nextInt(randomAdditive*2) - randomAdditive;
			b += rand.nextInt(randomAdditive*2) - randomAdditive;
			// Bound checks:
			if (r > 255) r = 255;
			if (r < 0) r = 0;
			if (g > 255) g = 255;
			if (g < 0) g = 0;
			if (b > 255) b = 255;
			if (b < 0) b = 0;
			colors[i] = (r << 16) | (g << 8) | b | 0xff000000;
		}
		return colors;
	}
	
	public static BufferedImage getImage(String file) {
		try {
			return ImageIO.read(new File(file));
		} catch(Exception e) {
			Logger.error(e);
		}
		return null;
	}
}
