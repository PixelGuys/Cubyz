package io.cubyz.blocks;

import java.awt.Color;
import java.awt.image.BufferedImage;
import java.util.Random;

public class CrystalTextureProvider implements TextureProvider {
	
	public int makeBetter(int color) {
		int r = (color >>> 16) & 255;
		int g = (color >>> 8) & 255;
		int b = (color >>> 0) & 255;
		float[] hsb = Color.RGBtoHSB(r, g, b, null);
		hsb[2] = Math.min(1, hsb[2]+0.25f);
		hsb[0] += (float)Math.random()*0.1f - 0.05f;
		return Color.HSBtoRGB(hsb[0], hsb[1], hsb[2]);
	}

	@Override
	public BufferedImage generateTexture(CustomBlock block, BufferedImage stone) {

		BufferedImage canvas = new BufferedImage(16, 16, BufferedImage.TYPE_INT_RGB);
		Random rand = new Random(block.seed);
		int[] colors = TextureProvider.createColorPalette(block, 4, 50, 12);
		
		// Make the colors brighter:
		for(int i = 0; i < colors.length; i++) {
			colors[i] = makeBetter(colors[i]);
		}
		
		// Create the background:
		for(int x = 0; x < 16; x++ ) {
			for(int y = 0; y < 16; y++) {
				canvas.setRGB(x, y, colors[1]);
			}
		}
		
		// Add some structural details:
		int rifts = rand.nextInt(8) + 5;
		for(int i = 0; i < rifts; i++) {
			double orientation = rand.nextDouble()*2*Math.PI;
			double xStep = Math.sin(orientation);
			double yStep = Math.cos(orientation);
			int size = rand.nextInt(8) + 8;
			double x = 8 + rand.nextDouble()*(14-size*Math.abs(xStep)) - (14-size*Math.abs(xStep))/2;
			double y = 8 + rand.nextDouble()*(14-size*Math.abs(yStep)) - (14-size*Math.abs(yStep))/2;
			x -= xStep*size/2;
			y -= yStep*size/2;
			for(int step = 0; step <= size; step++) {
				int xPos = (int)(x - yStep*0.5);
				int yPos = (int)(y + xStep*0.5);
				canvas.setRGB(xPos, yPos, colors[0]);
				xPos = (int)(x + yStep*0.5);
				yPos = (int)(y - xStep*0.5);
				canvas.setRGB(xPos, yPos, colors[2]);
				x += xStep;
				y += yStep;
			}
		}
		
		// Add some sharp points:
		int numPoints = 4 + rand.nextInt(8);
		for(int i = 0; i < numPoints; i++) {
			canvas.setRGB(rand.nextInt(16), rand.nextInt(16), colors[3]);
		}
		return canvas;
	}

}
