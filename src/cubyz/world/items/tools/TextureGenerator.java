package cubyz.world.items.tools;

import cubyz.world.items.Item;

import java.awt.image.BufferedImage;
import java.io.File;

import javax.imageio.ImageIO;

/**
 * Generates the texture of a Tool using the material information.
 */
public class TextureGenerator {
	/*
	0  1  2  3  4
	5  6  7  8  9
	10 11 12 13 14
	15 16 17 18 19
	20 21 22 23 24
	*/

	private static void drawRegion(Item[] offsetGrid, int x, int y, BufferedImage img) {
		if(offsetGrid[12] != null) {
			// Count neighbors:
			int diagonalNeighbors = 0;
			int straighNeighbors = 0;
			if(offsetGrid[7] != null) {
				straighNeighbors++;
			}
			if(offsetGrid[11] != null) {
				straighNeighbors++;
			}
			if(offsetGrid[13] != null) {
				straighNeighbors++;
			}
			if(offsetGrid[17] != null) {
				straighNeighbors++;
			}
			if(offsetGrid[6] != null) {
				diagonalNeighbors++;
			}
			if(offsetGrid[8] != null) {
				diagonalNeighbors++;
			}
			if(offsetGrid[16] != null) {
				diagonalNeighbors++;
			}
			if(offsetGrid[18] != null) {
				diagonalNeighbors++;
			}
			int neighbors = straighNeighbors + diagonalNeighbors;

			img.setRGB(x + 1, y + 1, 0xff000000);
			img.setRGB(x + 1, y + 2, 0xff000000);
			img.setRGB(x + 2, y + 1, 0xff000000);
			img.setRGB(x + 2, y + 2, 0xff000000);

			// Checkout straight neighbors:
			if(offsetGrid[7] != null) {
				img.setRGB(x + 1, y, 0xff000000);
				img.setRGB(x + 2, y, 0xff000000);
				if(offsetGrid[1] != null && offsetGrid[16] == null && straighNeighbors <= 1) {
					img.setRGB(x + 2, y + 3, 0xff000000);
				}
				if(offsetGrid[3] != null && offsetGrid[18] == null && straighNeighbors <= 1) {
					img.setRGB(x + 1, y + 3, 0xff000000);
				}
			}
			if(offsetGrid[11] != null) {
				img.setRGB(x, y + 1, 0xff000000);
				img.setRGB(x, y + 2, 0xff000000);
				if(offsetGrid[5] != null && offsetGrid[8] == null && straighNeighbors <= 1) {
					img.setRGB(x + 3, y + 2, 0xff000000);
				}
				if(offsetGrid[15] != null && offsetGrid[18] == null && straighNeighbors <= 1) {
					img.setRGB(x + 3, y + 1, 0xff000000);
				}
			}
			if(offsetGrid[13] != null) {
				img.setRGB(x + 3, y + 1, 0xff000000);
				img.setRGB(x + 3, y + 2, 0xff000000);
				if(offsetGrid[9] != null && offsetGrid[6] == null && straighNeighbors <= 1) {
					img.setRGB(x, y + 2, 0xff000000);
				}
				if(offsetGrid[19] != null && offsetGrid[16] == null && straighNeighbors <= 1) {
					img.setRGB(x, y + 1, 0xff000000);
				}
			}
			if(offsetGrid[17] != null) {
				img.setRGB(x + 1, y + 3, 0xff000000);
				img.setRGB(x + 2, y + 3, 0xff000000);
				if(offsetGrid[21] != null && offsetGrid[6] == null && straighNeighbors <= 1) {
					img.setRGB(x + 2, y, 0xff000000);
				}
				if(offsetGrid[23] != null && offsetGrid[8] == null && straighNeighbors <= 1) {
					img.setRGB(x + 1, y, 0xff000000);
				}
			}

			// Checkout diagonal neighbors:
			if(offsetGrid[6] != null) {
				img.setRGB(x, y, 0xff000000);
				img.setRGB(x - 1, y, 0xff000000);
				img.setRGB(x, y - 1, 0xff000000);
				img.setRGB(x + 1, y, 0xff000000);
				img.setRGB(x, y + 1, 0xff000000);
				if(offsetGrid[1] != null && offsetGrid[7] == null && neighbors <= 2) {
					img.setRGB(x + 3, y + 2, 0xff000000);
				}
				if(offsetGrid[5] != null && offsetGrid[11] == null && neighbors <= 2) {
					img.setRGB(x + 2, y + 3, 0xff000000);
				}
			}
			if(offsetGrid[8] != null) {
				img.setRGB(x + 3, y, 0xff000000);
				img.setRGB(x + 2, y, 0xff000000);
				img.setRGB(x + 3, y - 1, 0xff000000);
				img.setRGB(x + 4, y, 0xff000000);
				img.setRGB(x + 3, y + 1, 0xff000000);
				if(offsetGrid[3] != null && offsetGrid[7] == null && neighbors <= 2) {
					img.setRGB(x, y + 2, 0xff000000);
				}
				if(offsetGrid[9] != null && offsetGrid[13] == null && neighbors <= 2) {
					img.setRGB(x + 1, y + 3, 0xff000000);
				}
			}
			if(offsetGrid[16] != null) {
				img.setRGB(x, y + 3, 0xff000000);
				img.setRGB(x - 1, y + 3, 0xff000000);
				img.setRGB(x, y + 2, 0xff000000);
				img.setRGB(x + 1, y + 3, 0xff000000);
				img.setRGB(x, y + 4, 0xff000000);
				if(offsetGrid[21] != null && offsetGrid[17] == null && neighbors <= 2) {
					img.setRGB(x + 3, y + 1, 0xff000000);
				}
				if(offsetGrid[15] != null && offsetGrid[11] == null && neighbors <= 2) {
					img.setRGB(x + 2, y, 0xff000000);
				}
			}
			if(offsetGrid[18] != null) {
				img.setRGB(x + 3, y + 3, 0xff000000);
				img.setRGB(x + 2, y + 3, 0xff000000);
				img.setRGB(x + 3, y + 2, 0xff000000);
				img.setRGB(x + 4, y + 3, 0xff000000);
				img.setRGB(x + 3, y + 4, 0xff000000);
				if(offsetGrid[23] != null && offsetGrid[17] == null && neighbors <= 2) {
					img.setRGB(x, y + 1, 0xff000000);
				}
				if(offsetGrid[19] != null && offsetGrid[13] == null && neighbors <= 2) {
					img.setRGB(x + 1, y, 0xff000000);
				}
			}

			// Make stuff more round when there is many incoming connections:
			if(diagonalNeighbors >= 3 || straighNeighbors == 4) {
				img.setRGB(x + 0, y + 1, 0xff000000);
				img.setRGB(x + 0, y + 2, 0xff000000);
				img.setRGB(x + 3, y + 1, 0xff000000);
				img.setRGB(x + 3, y + 2, 0xff000000);
				img.setRGB(x + 1, y + 0, 0xff000000);
				img.setRGB(x + 1, y + 3, 0xff000000);
				img.setRGB(x + 2, y + 0, 0xff000000);
				img.setRGB(x + 2, y + 3, 0xff000000);
				// Check which of the neighbors was empty:
				if(offsetGrid[6] == null) {
					img.setRGB(x + 0, y + 0, 0xff000000);
					img.setRGB(x + 2, y - 1, 0xff000000);
					img.setRGB(x - 1, y + 2, 0xff000000);
				}
				if(offsetGrid[8] == null) {
					img.setRGB(x + 3, y + 0, 0xff000000);
					img.setRGB(x + 1, y - 1, 0xff000000);
					img.setRGB(x + 4, y + 2, 0xff000000);
				}
				if(offsetGrid[16] == null) {
					img.setRGB(x + 0, y + 3, 0xff000000);
					img.setRGB(x + 2, y + 4, 0xff000000);
					img.setRGB(x - 1, y + 1, 0xff000000);
				}
				if(offsetGrid[18] == null) {
					img.setRGB(x + 3, y + 3, 0xff000000);
					img.setRGB(x + 1, y + 4, 0xff000000);
					img.setRGB(x + 4, y + 1, 0xff000000);
				}
			}
		}
	}
	static Item item = new Item();
	static Item[][] testCases = new Item[][] {
		new Item[] {
			null, item, item, item, null,
			item, null, item, null, item,
			null, null, item, null, null,
			null, null, item, null, null,
			null, item, item, item, null,
		},
		new Item[] {
			null, null, item, item, null,
			null, item, null, null, null,
			item, null, item, null, null,
			item, null, null, item, null,
			null, null, null, null, item,
		},
		new Item[] {
			null, item, item, item, null,
			null, item, item, item, null,
			null, item, item, item, null,
			null, null, item, null, null,
			null, null, item, null, null,
		},
		new Item[] {
			null, item, null, null, null,
			item, item, item, null, null,
			null, item, item, null, null,
			null, null, null, item, null,
			null, null, null, null, item,
		},
		new Item[] {
			null, item, item, item, null,
			null, item, item, item, null,
			null, null, item, null, null,
			null, null, item, null, null,
			null, null, item, null, null,
		},
		new Item[] {
			null, item, item, item, null,
			item, null, item, null, item,
			item, null, item, null, item,
			null, null, item, null, null,
			null, null, item, null, null,
		},
		new Item[] {
			null, item, item, item, null,
			item, null, item, item, item,
			item, item, item, null, item,
			null, null, item, null, null,
			null, item, item, item, null,
		},
		new Item[] {
			item, null, item, null, item,
			null, item, null, item, null,
			item, null, null, null, item,
			null, item, null, item, null,
			item, null, item, null, item,
		},
		new Item[] {
			null, item, item, item, null,
			item, null, null, null, item,
			item, null, null, null, item,
			item, null, null, null, item,
			null, item, item, item, null,
		},
		new Item[] {
			item, null, item, null, item,
			item, item, item, item, item,
			item, null, item, null, item,
			null, null, item, null, null,
			null, null, item, null, null,
		},
		new Item[] {
			null, null, null, null, null,
			null, item, null, null, null,
			item, item, item, null, null,
			null, item, null, item, null,
			null, null, null, null, item,
		},
	};
	public static void generate(Item[] grid) {
		BufferedImage fullStack = new BufferedImage(32, 16*testCases.length, BufferedImage.TYPE_INT_ARGB);
		for(int j = 0; j < testCases.length; j++) {
			grid = testCases[j];
			BufferedImage img = new BufferedImage(32, 16, BufferedImage.TYPE_INT_ARGB);
			int[] gridCentersX = new int[] {
				2, 5, 8, 11, 14,
				2, 5, 8, 11, 14,
				2, 5, 8, 11, 14,
				2, 5, 8, 11, 14,
				2, 5, 8, 11, 14,
			};
			int[] gridCentersY = new int[] {
				2, 2, 2, 2, 2,
				5, 5, 5, 5, 5,
				8, 8, 8, 8, 8,
				11, 11, 11, 11, 11,
				14, 14, 14, 14, 14,
			};
			for(int x = 0; x < 32; x++) {
				for(int y = 0; y < 16; y++) {
					img.setRGB(x, y, 0xffffffff);
				}
			}
			for(int x = 0; x < 16; x += 3) {
				for(int y = 0; y < 16; y++) {
					img.setRGB(16+x, y, 0xff7f6000);
				}
			}
			for(int x = 0; x < 16; x++) {
				for(int y = 0; y < 16; y += 3) {
					img.setRGB(16+x, y, 0xff7f6000);
				}
			}
			for(int i = 0; i < 25; i++) {
				if(grid[i] == null) continue;
				img.setRGB(16+gridCentersX[i], gridCentersY[i], 0xff000000);
				img.setRGB(16+gridCentersX[i], gridCentersY[i]-1, 0xff000000);
				img.setRGB(16+gridCentersX[i]-1, gridCentersY[i], 0xff000000);
				img.setRGB(16+gridCentersX[i]-1, gridCentersY[i]-1, 0xff000000);
			}
			// Split the thing into segments. Segments are lines of 3 points that appear to have similar slope.
			for(int x = 0; x < 5; x++) {
				for(int y = 0; y < 5; y++) {

					Item[] offsetGrid = new Item[25];
					for(int dx = -2; dx <= 2; dx++) {
						for(int dy = -2; dy <= 2; dy++) {
							if(x + dx >= 0 && x + dx < 5) {
								if(y + dy >= 0 && y + dy < 5) {
									int index = x + dx + 5 * (y + dy);
									int offsetIndex = 2 + dx + 5 * (2 + dy);
									offsetGrid[offsetIndex] = grid[index];
								}
							}
						}
					}
					int index = x + 5*y;
					drawRegion(offsetGrid, gridCentersX[index] - 2, gridCentersY[index] - 2, img);
				}
			}

			fullStack.getGraphics().drawImage(img, 0, 16*j, null);
		}
		try {
			ImageIO.write(fullStack, "PNG", new File("test.png"));
		} catch (Exception e) {
			e.printStackTrace();
		}
	}
}
