import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import java.util.Random;
import javax.imageio.ImageIO;

public class OreTexture {
	public static BufferedImage getImage(String fileName) {
		try {
			return ImageIO.read(new File(fileName));
		} catch(Exception e) {e.printStackTrace();}
		return null;
	}
	
	public static BufferedImage generateOreTexture(BufferedImage stone, long seed, int color, float shinyness) {
		BufferedImage canvas = new BufferedImage(16, 16, BufferedImage.TYPE_INT_RGB);
		Random rand = new Random(seed);
		// Init the canvas:
		for(int px = 0; px < 16; px++) {
			for(int py = 0; py < 16; py++) {
				canvas.setRGB(px, py, stone.getRGB(px, py));
			}
		}
		// Size arguments for the semi major axis:
		double size = 1.5 + rand.nextDouble()*1.5;
		double variation = 0.5*size*rand.nextDouble();
		// Size arguments of the semi minor axis:
		double standard2 = size/3.8*0.7*rand.nextDouble();
		double variation2 = (standard2)*0.5*rand.nextDouble();
		// standard rotation and how far the rotation may differ for each spawn location:
		double rotation0 = rand.nextDouble()*2*Math.PI;
		double rotationVar = 0*rand.nextDouble()*2*Math.PI;
		// Make bigger ovals more rough:
		float roughness = (float)(size*(1-standard2)/3.0);
		int differentColors = 4 + (int)(1.5*(size-1.5));
		int [] colors = new int[differentColors]; // Use a color palette of less than 6 different colors.
		for(int i = 0; i < differentColors; i++) { //TODO: Make sure the contrast fits everywhere and maybe use hue-shifting.
			int r = (color >>> 16) & 255;
			int g = (color >>> 8) & 255;
			int b = (color >>> 0) & 255;
			// Add a brightness value to the color:
			int brightness = (int)(-100*(differentColors/2.0-i)/differentColors);
			if(brightness > 0) {
				brightness *= shinyness+1;
			}
			r += brightness;
			g += brightness;
			b += brightness;
			// make sure that once a color channel is satured the others get increased further:
			int totalDif = 0;
			if(r > 255) {
				totalDif += r-255;
			}
			if(g > 255) {
				totalDif += g-255;
			}
			if(b > 255) {
				totalDif += b-255;
			}
			totalDif = totalDif*3/2;
			r += totalDif;
			g += totalDif;
			b += totalDif;
			// Add some flavor to the color, so it's not just a scale based on lighting:
			r += rand.nextInt(32) - 16;
			g += rand.nextInt(32) - 16;
			b += rand.nextInt(32) - 16;
			// Bound checks:
			if(r > 255) r = 255;
			if(r < 0) r = 0;
			if(g > 255) g = 255;
			if(g < 0) g = 0;
			if(b > 255) b = 255;
			if(b < 0) b = 0;
			colors[i] = (r << 16) | (g << 8) | b;
		}
		// Number of ovals drawn:
		int spawns = (int)(rand.nextDouble()*4) + 8 + (int)(30.0/Math.pow(size-variation/2, 4));
		boolean isCrystal = rand.nextDouble() < 0.0; // TODO
		int tries = 0;
		outer:
		for(int i = 0; i < spawns; i++) {
			if(!isCrystal) { // Just some rotated oval shape.
				double actualSize = size - rand.nextDouble()*variation;
				double actualSizeSmall = actualSize*(1 - (standard2+variation2*(rand.nextDouble() - 0.5)));
				// Rotate the oval by a random angle:
				double angle = rotation0 + rand.nextDouble()*rotationVar;
				double xMain = Math.sin(angle)/actualSize;
				double yMain = Math.cos(angle)/actualSize;
				double xSecn = Math.cos(angle)/actualSizeSmall;
				double ySecn = -Math.sin(angle)/actualSizeSmall;
				// Make sure the ovals don't touch the border of the block texture to remove hard edges between the ore and normal stone blocks:
				double xOffset = Math.max(Math.abs(xMain*actualSize*actualSize), Math.abs(xSecn*actualSizeSmall*actualSizeSmall));
				double yOffset = Math.max(Math.abs(yMain*actualSize*actualSize), Math.abs(ySecn*actualSizeSmall*actualSizeSmall));
				double x = xOffset + rand.nextDouble()*(15 - 2*xOffset);
				double y = yOffset + rand.nextDouble()*(15 - 2*yOffset);
				int xMin = Math.max(0, (int)(x-actualSize));
				int xMax = Math.min(15, (int)(x+actualSize));
				int yMin = Math.max(0, (int)(y-actualSize));
				int yMax = Math.min(15, (int)(y+actualSize));
				// Make sure this ellipse doesn't come too close to another one:
				for(int px = xMin-1; px <= xMax+1; px++) {
					for(int py = yMin-1; py <= yMax+1; py++) {
						if(px == -1 || px == 16 || py == -1 || py == 16) continue;
						double deltaX = px-x;
						double deltaY = py-y;
						double distMain = deltaX*xMain+deltaY*yMain;
						double distSecn = deltaX*xSecn+deltaY*ySecn;
						if(distMain*distMain+distSecn*distSecn < 1.3) {
							if(stone.getRGB(px, py) != canvas.getRGB(px, py)) {
								// Give 3 tries to create the oval coordinates, then move on to the next spawn, yo the program cannot get stuck in an infinite loop.
								tries++;
								if(tries < 3)
									i--;
								continue outer;
							}
						}
					}
				}
				tries = 0;
				for(int px = xMin; px <= xMax; px++) {
					for(int py = yMin; py <= yMax; py++) {
						// Add more variety to the texture by shifting the coordinates by a random amount:
						double deltaX = px - x;
						double deltaY = py - y;
						double distMain = deltaX*xMain + deltaY*yMain;
						double distSecn = deltaX*xSecn + deltaY*ySecn;
						double dist = distMain*distMain + distSecn*distSecn;
						if(dist < 1) {
							// Light is determined as how far to the upper left the current pixel is relative to the center.
							double light = (-(distMain*xMain*actualSize + distSecn*xSecn*actualSizeSmall)*Math.sqrt(0.5) - (distMain*yMain*actualSize + distSecn*ySecn*actualSizeSmall)*Math.sqrt(0.5));
							light += (rand.nextFloat()-.5f)*roughness/4; // Randomly shift the lighting to get a more rough appearance.
							// Determine the index in the color palette that fits the pseudo-lighting conditions:
							int lightIndex = (int)Math.round((3 + light*8.0/3)*differentColors/6);
							if(lightIndex < 0) lightIndex = 0;
							if(lightIndex >= differentColors) lightIndex = differentColors-1;
							int bestColor = colors[lightIndex];
							canvas.setRGB(px, py, 0xff000000 | bestColor);
						}
					}
				}
			} else { // TODO

			}
		}
		return canvas;
	}

	public static void main(String[] args) { // Just playing around with some ore textures. Don't mind the code and the random image appearing in the project path.
		int n = 100;
		BufferedImage stone = getImage("../../cubyz-client/addons/cubyz/blocks/textures/stone.png");
		BufferedImage canvas = new BufferedImage(16*n, 16*n, BufferedImage.TYPE_INT_RGB);
		for(int ix = 0; ix < n; ix++) {
			for(int iy = 0; iy < n; iy++) {
				long seed = 4378256*ix ^ 574690546*iy;
				Random rand = new Random(seed);
				BufferedImage ore = generateOreTexture(stone, seed, rand.nextInt(0xffffff), rand.nextFloat());
				canvas.getGraphics().drawImage(ore, ix*16, iy*16, null);
			}
		}
		try {
			ImageIO.write(canvas, "png", new File("test.png"));
		} catch (IOException e) {
			e.printStackTrace();
		}
	}
}
