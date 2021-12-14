package cubyz.world.items.tools;

import cubyz.world.items.Item;

import java.awt.image.BufferedImage;
import java.util.ArrayList;
import java.util.Random;

/**
 * Generates the texture of a Tool using the material information.
 */
public class TextureGenerator {
	/** Used to translate between grid and pixel coordinates. */
	static final int[] GRID_CENTERS_X = new int[] {
		2, 5, 8, 11, 14,
		2, 5, 8, 11, 14,
		2, 5, 8, 11, 14,
		2, 5, 8, 11, 14,
		2, 5, 8, 11, 14,
	};
	/** Used to translate between grid and pixel coordinates. */
	static final int[] GRID_CENTERS_Y = new int[] {
		2, 2, 2, 2, 2,
		5, 5, 5, 5, 5,
		8, 8, 8, 8, 8,
		11, 11, 11, 11, 11,
		14, 14, 14, 14, 14,
	};

	/**
	 * Contains the material(s) of a single pixel and tries to avoid multiple materials.
	 */
	private static class PixelData {
		public int maxNeighbors = -1;
		public ArrayList<Item> items = new ArrayList<>();
		public void add(Item item, int neighbors) {
			if (neighbors > maxNeighbors) {
				maxNeighbors = neighbors;
				items.clear();
			}
			if (neighbors == maxNeighbors) {
				items.add(item);
			}
		}
	}

	/**
	 * Counts the neighbors, while prioritizing direct neighbors over diagonals.
	 * @param offsetGrid
	 * @return
	 */
	private static int countNeighbors(Item[] offsetGrid) {
		int neighbors = 0;
		// direct neighbors count 1.5 times as much.
		if (offsetGrid[7] != null) {
			neighbors += 3;
		}
		if (offsetGrid[11] != null) {
			neighbors += 3;
		}
		if (offsetGrid[13] != null) {
			neighbors += 3;
		}
		if (offsetGrid[17] != null) {
			neighbors += 3;
		}
		if (offsetGrid[6] != null) {
			neighbors += 2;
		}
		if (offsetGrid[8] != null) {
			neighbors += 2;
		}
		if (offsetGrid[16] != null) {
			neighbors += 2;
		}
		if (offsetGrid[18] != null) {
			neighbors += 2;
		}
		return neighbors;
	}

	/**
	 * This part is responsible for associating each pixel with an item.
	 * @param offsetGrid grid translated towards the given region.
	 * @param neighborCount computed with `countNeighbors()`
	 * @param x position on the texture grid
	 * @param y position on the texture grid
	 * @param pixels
	 */
	private static void drawRegion(Item[] offsetGrid, int[] neighborCount, int x, int y, PixelData[][] pixels) {
		Item item = offsetGrid[12];
		if (item != null) {
			// Count diagonal and straight neighbors:
			int diagonalNeighbors = 0;
			int straighNeighbors = 0;
			if (offsetGrid[7] != null) {
				straighNeighbors++;
			}
			if (offsetGrid[11] != null) {
				straighNeighbors++;
			}
			if (offsetGrid[13] != null) {
				straighNeighbors++;
			}
			if (offsetGrid[17] != null) {
				straighNeighbors++;
			}
			if (offsetGrid[6] != null) {
				diagonalNeighbors++;
			}
			if (offsetGrid[8] != null) {
				diagonalNeighbors++;
			}
			if (offsetGrid[16] != null) {
				diagonalNeighbors++;
			}
			if (offsetGrid[18] != null) {
				diagonalNeighbors++;
			}
			int neighbors = diagonalNeighbors + straighNeighbors;

			pixels[x + 1][y + 1].add(item, neighborCount[12]);
			pixels[x + 1][y + 2].add(item, neighborCount[12]);
			pixels[x + 2][y + 1].add(item, neighborCount[12]);
			pixels[x + 2][y + 2].add(item, neighborCount[12]);

			// Checkout straight neighbors:
			if (offsetGrid[7] != null) {
				if (neighborCount[7] >= neighborCount[12]) {
					pixels[x + 1][y].add(item, neighborCount[12]);
					pixels[x + 2][y].add(item, neighborCount[12]);
				}
				if (offsetGrid[1] != null && offsetGrid[16] == null && straighNeighbors <= 1) {
					pixels[x + 2][y + 3].add(item, neighborCount[12]);
				}
				if (offsetGrid[3] != null && offsetGrid[18] == null && straighNeighbors <= 1) {
					pixels[x + 1][y + 3].add(item, neighborCount[12]);
				}
			}
			if (offsetGrid[11] != null) {
				if (neighborCount[11] >= neighborCount[12]) {
					pixels[x][y + 1].add(item, neighborCount[12]);
					pixels[x][y + 2].add(item, neighborCount[12]);
				}
				if (offsetGrid[5] != null && offsetGrid[8] == null && straighNeighbors <= 1) {
					pixels[x + 3][y + 2].add(item, neighborCount[12]);
				}
				if (offsetGrid[15] != null && offsetGrid[18] == null && straighNeighbors <= 1) {
					pixels[x + 3][y + 1].add(item, neighborCount[12]);
				}
			}
			if (offsetGrid[13] != null) {
				if (neighborCount[13] >= neighborCount[12]) {
					pixels[x + 3][y + 1].add(item, neighborCount[12]);
					pixels[x + 3][y + 2].add(item, neighborCount[12]);
				}
				if (offsetGrid[9] != null && offsetGrid[6] == null && straighNeighbors <= 1) {
					pixels[x][y + 2].add(item, neighborCount[12]);
				}
				if (offsetGrid[19] != null && offsetGrid[16] == null && straighNeighbors <= 1) {
					pixels[x][y + 1].add(item, neighborCount[12]);
				}
			}
			if (offsetGrid[17] != null) {
				if (neighborCount[17] >= neighborCount[12]) {
					pixels[x + 1][y + 3].add(item, neighborCount[12]);
					pixels[x + 2][y + 3].add(item, neighborCount[12]);
				}
				if (offsetGrid[21] != null && offsetGrid[6] == null && straighNeighbors <= 1) {
					pixels[x + 2][y].add(item, neighborCount[12]);
				}
				if (offsetGrid[23] != null && offsetGrid[8] == null && straighNeighbors <= 1) {
					pixels[x + 1][y].add(item, neighborCount[12]);
				}
			}

			// Checkout diagonal neighbors:
			if (offsetGrid[6] != null) {
				if (neighborCount[6] >= neighborCount[12]) {
					pixels[x][y].add(item, neighborCount[12]);
				}
				pixels[x + 1][y].add(item, neighborCount[12]);
				pixels[x][y + 1].add(item, neighborCount[12]);
				if (offsetGrid[1] != null && offsetGrid[7] == null && neighbors <= 2) {
					pixels[x + 3][y + 2].add(item, neighborCount[12]);
				}
				if (offsetGrid[5] != null && offsetGrid[11] == null && neighbors <= 2) {
					pixels[x + 2][y + 3].add(item, neighborCount[12]);
				}
			}
			if (offsetGrid[8] != null) {
				if (neighborCount[8] >= neighborCount[12]) {
					pixels[x + 3][y].add(item, neighborCount[12]);
				}
				pixels[x + 2][y].add(item, neighborCount[12]);
				pixels[x + 3][y + 1].add(item, neighborCount[12]);
				if (offsetGrid[3] != null && offsetGrid[7] == null && neighbors <= 2) {
					pixels[x][y + 2].add(item, neighborCount[12]);
				}
				if (offsetGrid[9] != null && offsetGrid[13] == null && neighbors <= 2) {
					pixels[x + 1][y + 3].add(item, neighborCount[12]);
				}
			}
			if (offsetGrid[16] != null) {
				if (neighborCount[16] >= neighborCount[12]) {
					pixels[x][y + 3].add(item, neighborCount[12]);
				}
				pixels[x][y + 2].add(item, neighborCount[12]);
				pixels[x + 1][y + 3].add(item, neighborCount[12]);
				if (offsetGrid[21] != null && offsetGrid[17] == null && neighbors <= 2) {
					pixels[x + 3][y + 1].add(item, neighborCount[12]);
				}
				if (offsetGrid[15] != null && offsetGrid[11] == null && neighbors <= 2) {
					pixels[x + 2][y].add(item, neighborCount[12]);
				}
			}
			if (offsetGrid[18] != null) {
				if (neighborCount[18] >= neighborCount[12]) {
					pixels[x + 3][y + 3].add(item, neighborCount[12]);
				}
				pixels[x + 2][y + 3].add(item, neighborCount[12]);
				pixels[x + 3][y + 2].add(item, neighborCount[12]);
				if (offsetGrid[23] != null && offsetGrid[17] == null && neighbors <= 2) {
					pixels[x][y + 1].add(item, neighborCount[12]);
				}
				if (offsetGrid[19] != null && offsetGrid[13] == null && neighbors <= 2) {
					pixels[x + 1][y].add(item, neighborCount[12]);
				}
			}

			// Make stuff more round when there is many incoming connections:
			if (diagonalNeighbors >= 3 || straighNeighbors == 4) {
				pixels[x + 0][y + 1].add(item, neighborCount[12]);
				pixels[x + 0][y + 2].add(item, neighborCount[12]);
				pixels[x + 3][y + 1].add(item, neighborCount[12]);
				pixels[x + 3][y + 2].add(item, neighborCount[12]);
				pixels[x + 1][y + 0].add(item, neighborCount[12]);
				pixels[x + 1][y + 3].add(item, neighborCount[12]);
				pixels[x + 2][y + 0].add(item, neighborCount[12]);
				pixels[x + 2][y + 3].add(item, neighborCount[12]);
				// Check which of the neighbors was empty:
				if (offsetGrid[6] == null) {
					pixels[x + 0][y + 0].add(item, neighborCount[12]);
					pixels[x + 2][y - 1].add(item, neighborCount[12]);
					pixels[x - 1][y + 2].add(item, neighborCount[12]);
				}
				if (offsetGrid[8] == null) {
					pixels[x + 3][y + 0].add(item, neighborCount[12]);
					pixels[x + 1][y - 1].add(item, neighborCount[12]);
					pixels[x + 4][y + 2].add(item, neighborCount[12]);
				}
				if (offsetGrid[16] == null) {
					pixels[x + 0][y + 3].add(item, neighborCount[12]);
					pixels[x + 2][y + 4].add(item, neighborCount[12]);
					pixels[x - 1][y + 1].add(item, neighborCount[12]);
				}
				if (offsetGrid[18] == null) {
					pixels[x + 3][y + 3].add(item, neighborCount[12]);
					pixels[x + 1][y + 4].add(item, neighborCount[12]);
					pixels[x + 4][y + 1].add(item, neighborCount[12]);
				}
			}
		}
	}

	private static float[][] generateHeightMap(Item[][] itemGrid, Random rand) {
		float[][] heightMap = new float[17][17];
		for(int x = 0; x < 17; x++) {
			for(int y = 0; y < 17; y++) {
				// The heighmap basically consists of the amount of neighbors this pixel has.
				// Also check if there are different neighbors.
				Item oneItem = itemGrid[x == 0 ? x : x-1][y == 0 ? y : y-1];
				boolean hasDifferentItems = false;
				for(int dx = -1; dx <= 0; dx++) {
					if (x + dx < 0 || x + dx >= 16) continue;
					for(int dy = -1; dy <= 0; dy++) {
						if (y + dy < 0 || y + dy >= 16) continue;

						heightMap[x][y] += itemGrid[x + dx][y + dy] != null ? (1 + (4 * rand.nextFloat() - 2) * itemGrid[x + dx][y + dy].material.roughness) : 0;
						if (itemGrid[x + dx][y + dy] != oneItem)
							hasDifferentItems = true;
					}
				}

				// If there is multiple items at this junction, make it go inward to make embedded parts stick out more:
				if (hasDifferentItems) {
					heightMap[x][y]--;
				}
				
				// Take into account further neighbors with lower priority:

				for(int dx = -2; dx <= 1; dx++) {
					if (x + dx < 0 || x + dx >= 16) continue;
					for(int dy = -2; dy <= 1; dy++) {
						if (y + dy < 0 || y + dy >= 16) continue;

						heightMap[x][y] += itemGrid[x + dx][y + dy] != null ? 1.0f/((dx + 0.5f)*(dx + 0.5f) + (dy + 0.5f)*(dy + 0.5f)) : 0;
						if (itemGrid[x + dx][y + dy] != oneItem)
							hasDifferentItems = true;
					}
				}
			}
		}
		return heightMap;
	}
	
	public static void generate(Tool tool) {
		BufferedImage img = tool.texture;
		PixelData[][] pixelMaterials = new PixelData[16][16];
		for(int x = 0; x < 16; x++) {
			for(int y = 0; y < 16; y++) {
				pixelMaterials[x][y] = new PixelData();
			}
		}

		Random rand = new Random(tool.hashCode());
		
		// Count all neighbors:
		int[] neighborCount = new int[25];
		for(int x = 0; x < 5; x++) {
			for(int y = 0; y < 5; y++) {
				Item[] offsetGrid = new Item[25];
				for(int dx = -2; dx <= 2; dx++) {
					for(int dy = -2; dy <= 2; dy++) {
						if (x + dx >= 0 && x + dx < 5) {
							if (y + dy >= 0 && y + dy < 5) {
								int index = x + dx + 5 * (y + dy);
								int offsetIndex = 2 + dx + 5 * (2 + dy);
								offsetGrid[offsetIndex] = tool.craftingGrid[index];
							}
						}
					}
				}
				int index = x + 5 * y;
				neighborCount[index] = countNeighbors(offsetGrid);
			}
		}

		// Push all items from the regions on a 16×16 image grid.
		for(int x = 0; x < 5; x++) {
			for(int y = 0; y < 5; y++) {

				Item[] offsetGrid = new Item[25];
				int[] offsetNeighborCount = new int[25];
				for(int dx = -2; dx <= 2; dx++) {
					for(int dy = -2; dy <= 2; dy++) {
						if (x + dx >= 0 && x + dx < 5) {
							if (y + dy >= 0 && y + dy < 5) {
								int index = x + dx + 5 * (y + dy);
								int offsetIndex = 2 + dx + 5 * (2 + dy);
								offsetGrid[offsetIndex] = tool.craftingGrid[index];
								offsetNeighborCount[offsetIndex] = neighborCount[index];
							}
						}
					}
				}
				int index = x + 5*y;
				drawRegion(offsetGrid, offsetNeighborCount, GRID_CENTERS_X[index] - 2, GRID_CENTERS_Y[index] - 2, pixelMaterials);
			}
		}

		Item[][] itemGrid = tool.materialGrid;
		for(int x = 0; x < 16; x++) {
			for(int y = 0; y < 16; y++) {
				if (pixelMaterials[x][y].items.size() != 0) {
					// Choose a random material at conflict zones:
					itemGrid[x][y] = pixelMaterials[x][y].items.get(rand.nextInt(pixelMaterials[x][y].items.size()));
				}
			}
		}
		// Generate a height map, which will be used for lighting calulations.
		float[][] heightMap = generateHeightMap(itemGrid, rand);
		for(int x = 0; x < 16; x++) {
			for(int y = 0; y < 16; y++) {
				Item mat = itemGrid[x][y];
				if (mat == null) continue;

				// Calculate the lighting based on the nearest free space:
				float lightTL = heightMap[x][y] - heightMap[x + 1][y + 1];
				float lightTR = heightMap[x + 1][y] - heightMap[x][y + 1];
				int light = 2 - (int) Math.round((lightTL * 2 + lightTR) / 6);
				light = Math.max(Math.min(light, 4), 0);
				img.setRGB(x, y, mat.material.colorPalette[light]);
			}
		}
	}
}
