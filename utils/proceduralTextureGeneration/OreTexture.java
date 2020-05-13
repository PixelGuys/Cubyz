import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import java.util.Random;
import javax.imageio.ImageIO;

public class OreTexture {
	public static BufferedImage getImage(String fileName) {
		try {
			return ImageIO.read(new File(fileName));
		} catch(Exception e) {}//e.printStackTrace();}
		return null;
	}
	
	public static int dist(int r1, int g1, int b1, int r2, int g2, int b2) {
		int max1 = Math.max(r1, Math.max(g1, b1));
		int max2 = Math.max(r2, Math.max(g2, b2));
		int min1 = Math.min(r1, Math.min(g1, b1));
		int min2 = Math.min(r2, Math.min(g2, b2));
		int dr = r2-r1;
		int dg = g2-g1;
		int db = b2-b1;
		return dr*dr + dg*dg + db*db;
	}

	public static void main(String[] args) { // Just playing around with some ore textures. Don't mind the code and the random image appearing in the project path.
		int n = 10;
		BufferedImage stone = getImage("../../cubyz-client/assets/cubyz/textures/blocks/stone.png");
		BufferedImage canvas = new BufferedImage(16*n, 16*n, BufferedImage.TYPE_INT_RGB);
		for(int ix = 0; ix < n; ix++) {
			for(int iy = 0; iy < n; iy++) {
				Random rand = new Random(4378256*ix ^ 574690546*iy);
				for(int px = 0; px < 16; px++) {
					for(int py = 0; py < 16; py++) {
						canvas.setRGB(px+ix*16, py+iy*16, stone.getRGB(px, py));
					}
				}
				int color = (int)(rand.nextDouble()*0xffffff);
				int [] colors = new int[6]; // Use a color palette of only 8 different colors.
				for(int i = 0; i < 6; i++) {
					int brightness = -100*(3-i)/4;
					int r = (color >>> 16) & 255;
					int g = (color >>> 8) & 255;
					int b = (color >>> 0) & 255;
					r += brightness;
					g += brightness;
					b += brightness;
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
					if(r > 255) r = 255;
					if(r < 0) r = 0;
					if(g > 255) g = 255;
					if(g < 0) g = 0;
					if(b > 255) b = 255;
					if(b < 0) b = 0;
					r += rand.nextInt(32) - 16;
					g += rand.nextInt(32) - 16;
					b += rand.nextInt(32) - 16;
					if(r > 255) r = 255;
					if(r < 0) r = 0;
					if(g > 255) g = 255;
					if(g < 0) g = 0;
					if(b > 255) b = 255;
					if(b < 0) b = 0;
					colors[i] = (r << 16) | (g << 8) | b;
				}
				double size = 1.1 + rand.nextDouble()*1.5;
				double variation = 0.5*size*rand.nextDouble();
				double standard2 = size/3.5*0.7*rand.nextDouble();
				double variation2 = (1-standard2)*0.5*rand.nextDouble();
				double rotation0 = rand.nextDouble()*2*Math.PI;
				double rotationVar = rand.nextDouble()*2*Math.PI;
				int spawns = (int)(rand.nextDouble()*4)+8+(int)(30.0/Math.pow(size-variation/2, 4));
				boolean isCrystal = rand.nextDouble() < 0.0;//0.5;
				int tries = 0;
				outer:
				for(int i = 0; i < spawns; i++) {
					if(!isCrystal) { // Just some rotated oval shape.
						double actualSize = size - rand.nextDouble()*variation;
						double actualSizeSmall = actualSize*(1-(standard2+variation2*(rand.nextDouble()-0.5)));
						// Rotate the oval by a random angle:
						double angle = rotation0 + rand.nextDouble()*rotationVar;
						double xMain = Math.sin(angle)/actualSize;
						double yMain = Math.cos(angle)/actualSize;
						double xSecn = Math.cos(angle)/actualSizeSmall;
						double ySecn = -Math.sin(angle)/actualSizeSmall;
						// Make sure the ovals don't touch the border of the block texture to remove hard edges between ore and stone blocks:
						double xOffset = Math.max(Math.abs(xMain*actualSize*actualSize), Math.abs(xSecn*actualSizeSmall*actualSizeSmall));
						double yOffset = Math.max(Math.abs(yMain*actualSize*actualSize), Math.abs(ySecn*actualSizeSmall*actualSizeSmall));
						double x = xOffset + rand.nextDouble()*(15 - 2*xOffset);
						double y = yOffset + rand.nextDouble()*(15 - 2*yOffset);
						int xMin = (int)(x-actualSize);
						int xMax = (int)(x+actualSize);
						int yMin = (int)(y-actualSize);
						int yMax = (int)(y+actualSize);
						if(xMin < 0) xMin = 0;
						if(xMax > 15) xMax = 15;
						if(yMin < 0) yMin = 0;
						if(yMax > 15) yMax = 15;
						for(int px = xMin; px <= xMax; px++) {
							for(int py = yMin; py <= yMax; py++) {
								double deltaX = px-x;
								double deltaY = py-y;
								double distMain = deltaX*xMain+deltaY*yMain;
								double distSecn = deltaX*xSecn+deltaY*ySecn;
								if(distMain*distMain+distSecn*distSecn < 1) {
									if(stone.getRGB(px, py) != canvas.getRGB(px + ix*16, py + iy*16)) {
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
								double deltaX = px-x;
								double deltaY = py-y;
								double distMain = deltaX*xMain+deltaY*yMain;
								double distSecn = deltaX*xSecn+deltaY*ySecn;
								if(distMain*distMain+distSecn*distSecn < 1) {
									double light = -deltaX*Math.sqrt(0.5)-deltaY*Math.sqrt(0.5);
									int lightScaled = (int)(light*40/actualSizeSmall);
									int alpha = (int)((1-distMain*distMain-distSecn*distSecn)*128*Math.min(size/1.5, 1));
									int colorBG = stone.getRGB(px, py);
									int rBG = (colorBG >>> 16) & 255;
									int gBG = (colorBG >>> 8) & 255;
									int bBG = (colorBG >>> 0) & 255;
									int r = (color >>> 16) & 255;
									int g = (color >>> 8) & 255;
									int b = (color >>> 0) & 255;
									r += lightScaled;
									g += lightScaled;
									b += lightScaled;
									r = (r*alpha + (255-alpha)*rBG)/255;
									g = (g*alpha + (255-alpha)*gBG)/255;
									b = (b*alpha + (255-alpha)*bBG)/255;
									if(r > 255) r = 255;
									if(r < 0) r = 0;
									if(g > 255) g = 255;
									if(g < 0) g = 0;
									if(b > 255) b = 255;
									if(b < 0) b = 0;
									int max = dist(r, g, b, rBG, gBG, bBG);
									int bestColor = colorBG;
									// Find the closest value from the palette:
									for(int l = 0; l < colors.length; l++) {
										int r2 = (colors[l] >> 16) & 255;
										int g2 = (colors[l] >> 8) & 255;
										int b2 = (colors[l] >> 0) & 255;
										int dist = dist(r, g, b, r2, g2, b2);
										if(dist < max) {
											max = dist;
											bestColor = colors[l];
										}
									}
									lightScaled = 3 + (int)Math.round(light*8.0/actualSizeSmall/3);
									if(lightScaled < 0) lightScaled = 0;
									if(lightScaled >= 6) lightScaled = 5;
									bestColor = colors[lightScaled];
									canvas.setRGB(px+ix*16, py+iy*16, 0xff000000 | bestColor);
								}
							}
						}
					} else { // TODO

					}
				}
			}
		}
		try {
			ImageIO.write(canvas, "png", new File("test.png"));
		} catch (IOException e) {
			// TODO Auto-generated catch block
			e.printStackTrace();
		}
	}
}
