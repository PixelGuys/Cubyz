package cubyz.world.items.tools;

import cubyz.utils.json.JsonArray;
import cubyz.utils.json.JsonObject;
import cubyz.world.items.Item;

import java.awt.image.BufferedImage;
import java.io.File;
import java.util.ArrayList;

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

	/**
	 * Contains the material(s) of a single pixel and tries to avoid multiple materials.
	 */
	private static class PixelData {
		public int maxNeighbors = -1;
		public ArrayList<Item> items = new ArrayList<>();
		public void add(Item item, int neighbors) {
			if(neighbors > maxNeighbors) {
				maxNeighbors = neighbors;
				items.clear();
			}
			if(neighbors == maxNeighbors) {
				items.add(item);
			}
		}
	}

	private static int countNeighbors(Item[] offsetGrid) {
		int neighbors = 0;
		// direct neighbors count 1.5 times as much.
		if(offsetGrid[7] != null) {
			neighbors += 3;
		}
		if(offsetGrid[11] != null) {
			neighbors += 3;
		}
		if(offsetGrid[13] != null) {
			neighbors += 3;
		}
		if(offsetGrid[17] != null) {
			neighbors += 3;
		}
		if(offsetGrid[6] != null) {
			neighbors += 2;
		}
		if(offsetGrid[8] != null) {
			neighbors += 2;
		}
		if(offsetGrid[16] != null) {
			neighbors += 2;
		}
		if(offsetGrid[18] != null) {
			neighbors += 2;
		}
		return neighbors;
	}

	private static void drawRegion(Item[] offsetGrid, int[] neighborCount, int x, int y, PixelData[][] img) {
		Item item = offsetGrid[12];
		if(item != null) {
			// Count diagonal and straight neighbors:
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
			int neighbors = diagonalNeighbors + straighNeighbors;

			img[x + 1][y + 1].add(item, neighborCount[12]);
			img[x + 1][y + 2].add(item, neighborCount[12]);
			img[x + 2][y + 1].add(item, neighborCount[12]);
			img[x + 2][y + 2].add(item, neighborCount[12]);

			// Checkout straight neighbors:
			if(offsetGrid[7] != null) {
				if(neighborCount[7] >= neighborCount[12]) {
					img[x + 1][y].add(item, neighborCount[12]);
					img[x + 2][y].add(item, neighborCount[12]);
				}
				if(offsetGrid[1] != null && offsetGrid[16] == null && straighNeighbors <= 1) {
					img[x + 2][y + 3].add(item, neighborCount[12]);
				}
				if(offsetGrid[3] != null && offsetGrid[18] == null && straighNeighbors <= 1) {
					img[x + 1][y + 3].add(item, neighborCount[12]);
				}
			}
			if(offsetGrid[11] != null) {
				if(neighborCount[11] >= neighborCount[12]) {
					img[x][y + 1].add(item, neighborCount[12]);
					img[x][y + 2].add(item, neighborCount[12]);
				}
				if(offsetGrid[5] != null && offsetGrid[8] == null && straighNeighbors <= 1) {
					img[x + 3][y + 2].add(item, neighborCount[12]);
				}
				if(offsetGrid[15] != null && offsetGrid[18] == null && straighNeighbors <= 1) {
					img[x + 3][y + 1].add(item, neighborCount[12]);
				}
			}
			if(offsetGrid[13] != null) {
				if(neighborCount[13] >= neighborCount[12]) {
					img[x + 3][y + 1].add(item, neighborCount[12]);
					img[x + 3][y + 2].add(item, neighborCount[12]);
				}
				if(offsetGrid[9] != null && offsetGrid[6] == null && straighNeighbors <= 1) {
					img[x][y + 2].add(item, neighborCount[12]);
				}
				if(offsetGrid[19] != null && offsetGrid[16] == null && straighNeighbors <= 1) {
					img[x][y + 1].add(item, neighborCount[12]);
				}
			}
			if(offsetGrid[17] != null) {
				if(neighborCount[17] >= neighborCount[12]) {
					img[x + 1][y + 3].add(item, neighborCount[12]);
					img[x + 2][y + 3].add(item, neighborCount[12]);
				}
				if(offsetGrid[21] != null && offsetGrid[6] == null && straighNeighbors <= 1) {
					img[x + 2][y].add(item, neighborCount[12]);
				}
				if(offsetGrid[23] != null && offsetGrid[8] == null && straighNeighbors <= 1) {
					img[x + 1][y].add(item, neighborCount[12]);
				}
			}

			// Checkout diagonal neighbors:
			if(offsetGrid[6] != null) {
				if(neighborCount[6] >= neighborCount[12]) {
					img[x][y].add(item, neighborCount[12]);
				}
				img[x + 1][y].add(item, neighborCount[12]);
				img[x][y + 1].add(item, neighborCount[12]);
				if(offsetGrid[1] != null && offsetGrid[7] == null && neighbors <= 2) {
					img[x + 3][y + 2].add(item, neighborCount[12]);
				}
				if(offsetGrid[5] != null && offsetGrid[11] == null && neighbors <= 2) {
					img[x + 2][y + 3].add(item, neighborCount[12]);
				}
			}
			if(offsetGrid[8] != null) {
				if(neighborCount[8] >= neighborCount[12]) {
					img[x + 3][y].add(item, neighborCount[12]);
				}
				img[x + 2][y].add(item, neighborCount[12]);
				img[x + 3][y + 1].add(item, neighborCount[12]);
				if(offsetGrid[3] != null && offsetGrid[7] == null && neighbors <= 2) {
					img[x][y + 2].add(item, neighborCount[12]);
				}
				if(offsetGrid[9] != null && offsetGrid[13] == null && neighbors <= 2) {
					img[x + 1][y + 3].add(item, neighborCount[12]);
				}
			}
			if(offsetGrid[16] != null) {
				if(neighborCount[16] >= neighborCount[12]) {
					img[x][y + 3].add(item, neighborCount[12]);
				}
				img[x][y + 2].add(item, neighborCount[12]);
				img[x + 1][y + 3].add(item, neighborCount[12]);
				if(offsetGrid[21] != null && offsetGrid[17] == null && neighbors <= 2) {
					img[x + 3][y + 1].add(item, neighborCount[12]);
				}
				if(offsetGrid[15] != null && offsetGrid[11] == null && neighbors <= 2) {
					img[x + 2][y].add(item, neighborCount[12]);
				}
			}
			if(offsetGrid[18] != null) {
				if(neighborCount[18] >= neighborCount[12]) {
					img[x + 3][y + 3].add(item, neighborCount[12]);
				}
				img[x + 2][y + 3].add(item, neighborCount[12]);
				img[x + 3][y + 2].add(item, neighborCount[12]);
				if(offsetGrid[23] != null && offsetGrid[17] == null && neighbors <= 2) {
					img[x][y + 1].add(item, neighborCount[12]);
				}
				if(offsetGrid[19] != null && offsetGrid[13] == null && neighbors <= 2) {
					img[x + 1][y].add(item, neighborCount[12]);
				}
			}

			// Make stuff more round when there is many incoming connections:
			if(diagonalNeighbors >= 3 || straighNeighbors == 4) {
				img[x + 0][y + 1].add(item, neighborCount[12]);
				img[x + 0][y + 2].add(item, neighborCount[12]);
				img[x + 3][y + 1].add(item, neighborCount[12]);
				img[x + 3][y + 2].add(item, neighborCount[12]);
				img[x + 1][y + 0].add(item, neighborCount[12]);
				img[x + 1][y + 3].add(item, neighborCount[12]);
				img[x + 2][y + 0].add(item, neighborCount[12]);
				img[x + 2][y + 3].add(item, neighborCount[12]);
				// Check which of the neighbors was empty:
				if(offsetGrid[6] == null) {
					img[x + 0][y + 0].add(item, neighborCount[12]);
					img[x + 2][y - 1].add(item, neighborCount[12]);
					img[x - 1][y + 2].add(item, neighborCount[12]);
				}
				if(offsetGrid[8] == null) {
					img[x + 3][y + 0].add(item, neighborCount[12]);
					img[x + 1][y - 1].add(item, neighborCount[12]);
					img[x + 4][y + 2].add(item, neighborCount[12]);
				}
				if(offsetGrid[16] == null) {
					img[x + 0][y + 3].add(item, neighborCount[12]);
					img[x + 2][y + 4].add(item, neighborCount[12]);
					img[x - 1][y + 1].add(item, neighborCount[12]);
				}
				if(offsetGrid[18] == null) {
					img[x + 3][y + 3].add(item, neighborCount[12]);
					img[x + 1][y + 4].add(item, neighborCount[12]);
					img[x + 4][y + 1].add(item, neighborCount[12]);
				}
			}
		}
	}

	private static float[][] generateHeightMap(Item[][] itemGrid) {
		float[][] heightMap = new float[17][17];
		for(int x = 0; x < 17; x++) {
			for(int y = 0; y < 17; y++) {
				// The heighmap basically consists of the amount of neighbors this pixel has.
				// Also check if there are different neighbors.
				Item oneItem = itemGrid[x == 0 ? x : x-1][y == 0 ? y : y-1];
				boolean hasDifferentItems = false;
				for(int dx = -1; dx <= 0; dx++) {
					if(x + dx < 0 || x + dx >= 16) continue;
					for(int dy = -1; dy <= 0; dy++) {
						if(y + dy < 0 || y + dy >= 16) continue;

						heightMap[x][y] += itemGrid[x + dx][y + dy] != null ? (1 + (float)(4 * Math.random() - 2) * itemGrid[x + dx][y + dy].material.roughness) : 0;
						if(itemGrid[x + dx][y + dy] != oneItem)
							hasDifferentItems = true;
					}
				}

				// If there is multiple items at this junction, make it go inward to make embedded parts stick out more:
				if(hasDifferentItems) {
					heightMap[x][y]--;
				}
				
				// Take into account further neighbors with lower priority:

				for(int dx = -2; dx <= 1; dx++) {
					if(x + dx < 0 || x + dx >= 16) continue;
					for(int dy = -2; dy <= 1; dy++) {
						if(y + dy < 0 || y + dy >= 16) continue;

						heightMap[x][y] += itemGrid[x + dx][y + dy] != null ? 1.0f/((dx + 0.5f)*(dx + 0.5f) + (dy + 0.5f)*(dy + 0.5f)) : 0;
						if(itemGrid[x + dx][y + dy] != oneItem)
							hasDifferentItems = true;
					}
				}
			}
		}
		return heightMap;
	}
	static Item item = new Item();
	static Item i2em = new Item();
	static Item i3em = new Item();
	static Item i4em = new Item();
	static Item[][] testCases = new Item[][] {
		new Item[] {
			null, item, item, item, null,
			item, null, i2em, null, item,
			null, null, i2em, null, null,
			null, null, i2em, null, null,
			null, null, i2em, null, null,
		},
		new Item[] {
			null, null, i3em, i3em, null,
			null, i3em, null, null, null,
			i3em, null, item, null, null,
			i3em, null, null, item, null,
			null, null, null, null, item,
		},
		new Item[] {
			null, i4em, i4em, i4em, null,
			null, i4em, i4em, i4em, null,
			null, i4em, i4em, i4em, null,
			null, null, item, null, null,
			null, null, item, null, null,
		},
		new Item[] {
			null, item, null, null, null,
			item, i2em, item, null, null,
			null, item, i2em, null, null,
			null, null, null, i2em, null,
			null, null, null, null, i2em,
		},
		new Item[] {
			null, item, item, item, null,
			null, item, i2em, item, null,
			null, null, item, null, null,
			null, null, item, null, null,
			null, null, item, null, null,
		},
		new Item[] {
			null, item, i2em, item, null,
			i2em, null, item, null, i2em,
			item, null, i2em, null, item,
			null, null, item, null, null,
			null, null, i2em, null, null,
		},
		new Item[] {
			null, i4em, item, item, null,
			i4em, null, i4em, item, item,
			item, i4em, item, null, item,
			null, null, item, null, null,
			null, item, item, item, null,
		},
		new Item[] {
			i3em, null, i3em, null, i3em,
			null, item, null, item, null,
			i3em, null, null, null, i3em,
			null, item, null, item, null,
			i3em, null, i3em, null, i3em,
		},
		new Item[] {
			null, item, i3em, item, null,
			i3em, null, null, null, i3em,
			item, null, null, null, item,
			item, null, null, null, item,
			null, i3em, item, i3em, null,
		},
		new Item[] {
			i2em, null, item, null, i2em,
			i2em, i4em, item, i4em, i2em,
			i2em, null, item, null, i2em,
			null, null, item, null, null,
			null, null, item, null, null,
		},
		new Item[] {
			null, null, null, null, null,
			null, item, null, null, null,
			i3em, item, item, null, null,
			null, i3em, null, item, null,
			null, null, null, null, item,
		},
	};
	public static void generate(Item[] grid) {
		JsonObject material = new JsonObject();
		material.put("density", 1.0f);
		material.put("resistance", 1.0f);
		material.put("power", 1.0f);
		material.put("roughness", 0.7f);
		JsonArray colors = new JsonArray();
		colors.addInts(0xff522e05, 0xff502c03, 0xff553204, 0xff67400e, 0xff784a12, 0xff984a22, 0xffaa4a32, 0xffab4a42, 0xffac4a52, 0xffad4a62, 0xffbc4a62, 0xffcc8a62, 0xffdc9a62, 0xffeeaa66, 0xffffbb77, 0xffffcc88, 0xffffdd99, 0xffffee99, 0xffffffaa, 0xffffffbb, 0xffffffcc, 0xffffffdd, 0xffffffee, 0xffffffff);
		material.put("colors", colors);
		item.material = new Material(material);

		material = new JsonObject();
		material.put("density", 1.0f);
		material.put("resistance", 1.0f);
		material.put("power", 1.0f);
		material.put("roughness", 0.3f);
		colors = new JsonArray();
		colors.addInts(0xff4a9494, 0xff53a5a5, 0xff59b3b3, 0xff59bbbb, 0xff7dcbcb);
		material.put("colors", colors);
		i2em.material = new Material(material);

		material = new JsonObject();
		material.put("density", 1.0f);
		material.put("resistance", 1.0f);
		material.put("power", 1.0f);
		material.put("roughness", 1.0f);
		colors = new JsonArray();
		colors.addInts(0xff282828, 0xff404040, 0xff606060, 0xff808080, 0xffb0b0b0);
		material.put("colors", colors);
		i3em.material = new Material(material);

		material = new JsonObject();
		material.put("density", 1.0f);
		material.put("resistance", 1.0f);
		material.put("power", 1.0f);
		material.put("roughness", 0.0f);
		colors = new JsonArray();
		colors.addInts(0xff28af28, 0xff40bf40, 0xff60cf60, 0xff80df80, 0xffb0ffb0);
		material.put("colors", colors);
		i4em.material = new Material(material);

		BufferedImage fullStack = new BufferedImage(32, 16*testCases.length, BufferedImage.TYPE_INT_ARGB);
		for(int j = 0; j < testCases.length; j++) {
			grid = testCases[j];
			BufferedImage img = new BufferedImage(32, 16, BufferedImage.TYPE_INT_ARGB);
			PixelData[][] pixelMaterials = new PixelData[16][16];
			for(int x = 0; x < 16; x++) {
				for(int y = 0; y < 16; y++) {
					pixelMaterials[x][y] = new PixelData();
				}
			}
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
				img.setRGB(16+gridCentersX[i], gridCentersY[i], grid[i].material.colorPalette[2]);
				img.setRGB(16+gridCentersX[i], gridCentersY[i]-1, grid[i].material.colorPalette[2]);
				img.setRGB(16+gridCentersX[i]-1, gridCentersY[i], grid[i].material.colorPalette[2]);
				img.setRGB(16+gridCentersX[i]-1, gridCentersY[i]-1, grid[i].material.colorPalette[2]);
			}
			// Count all neighbors:
			int[] neighborCount = new int[25];
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
					neighborCount[index] = countNeighbors(offsetGrid);
				}
			}
			// Split the thing into segments. Segments are lines of 3 points that appear to have similar slope.
			for(int x = 0; x < 5; x++) {
				for(int y = 0; y < 5; y++) {

					Item[] offsetGrid = new Item[25];
					int[] offsetNeighborCount = new int[25];
					for(int dx = -2; dx <= 2; dx++) {
						for(int dy = -2; dy <= 2; dy++) {
							if(x + dx >= 0 && x + dx < 5) {
								if(y + dy >= 0 && y + dy < 5) {
									int index = x + dx + 5 * (y + dy);
									int offsetIndex = 2 + dx + 5 * (2 + dy);
									offsetGrid[offsetIndex] = grid[index];
									offsetNeighborCount[offsetIndex] = neighborCount[index];
								}
							}
						}
					}
					int index = x + 5*y;
					drawRegion(offsetGrid, offsetNeighborCount, gridCentersX[index] - 2, gridCentersY[index] - 2, pixelMaterials);
				}
			}

			Item[][] itemGrid = new Item[16][16];
			for(int x = 0; x < 16; x++) {
				for(int y = 0; y < 16; y++) {
					if(pixelMaterials[x][y].items.size() != 0) {
						// Choose a random material at conflict zones:
						itemGrid[x][y] = pixelMaterials[x][y].items.get((int)(Math.random()*pixelMaterials[x][y].items.size()));
					}
				}
			}
			// Generate a height map, which will be used for lighting calulations.
			float[][] heightMap = generateHeightMap(itemGrid);
			for(int x = 0; x < 16; x++) {
				for(int y = 0; y < 16; y++) {
					Item mat = itemGrid[x][y];
					img.setRGB(x + 16, y, item.material.colorPalette[(int)heightMap[x][y]]);
					if(mat == null) continue;

					// Calculate the lighting based on the nearest free space:
					float lightTL = heightMap[x][y] - heightMap[x + 1][y + 1];
					float lightTR = heightMap[x + 1][y] - heightMap[x][y + 1];
					int light = 2 - (int)Math.round((lightTL*2 + lightTR)/6);
					light = Math.max(Math.min(light, 4), 0);
					img.setRGB(x, y, mat.material.colorPalette[light]);
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
