package cubyz.world.items;

/**
 * A basic crafting recipe that can be created in any size crafting grid.<br>
 * TODO: Add a recipe unlocking mechanism or similar.
 */

public class Recipe {
	
	private int x, y; // Size of the shaped figure. If zero: shapeless.
	private Item [] pattern; // Pattern of all items in the recipe. An entry is null when no item should be placed there.
	private Item result;
	private int num = 0; // Number of items needed. Used to faster search for recipes.
	private int numRet = 0; // Number of items returned after applying this recipe.
	
	public Recipe(int x, int y, Item[] pattern, int numRet, Item result) {
		this.x = x;
		this.y = y;
		this.pattern = pattern;
		this.numRet = numRet;
		this.result = result;
		if (pattern.length != x*y)
			throw new IllegalArgumentException("Size and pattern don't fit.");
		for(int i = 0; i < pattern.length; i++) {
			if (pattern[i] != null) {
				num++;
			}
		}
	}
	public Recipe(Item[] pattern, int numRet, Item result) {
		x = y = 0;
		this.pattern = pattern;
		this.numRet = numRet;
		this.result = result;
		num = pattern.length;
	}
	public int getNum() {
		return num;
	}
	public int getNumRet() {
		return numRet;
	}
	// Returns the item that can be crafted using this recipe, if it can be crafted.
	// The input items need to be in an size×size sized array representing the crafting grid from left to right, top to bottom.
	public Item canCraft(Item[] items, int size) {
		if (x == 0 || y == 0)
			return shapelessCraft(items);
		if (size < x || size < y)
			return null;
		// Remove all colums containing null
		int x0 = 0;
		int xLen = size;
		for(int i = 0; i < size; i++) {
			boolean braek = false;
			for(int j = 0; j < size; j++) {
				braek = items[i+j*size] != null;
				if (braek)
					break;
				if (j == size-1) {
					x0++;
					xLen--;
				}
			}
			if (braek)
				break;
		}
		for(int i = size-1; i >= 0; i--) {
			boolean braek = false;
			for(int j = size-1; j >= 0; j--) {
				braek = items[i+j*size] != null;
				if (braek)
					break;
				if (j == 0) {
					xLen--;
				}
			}
			if (braek)
				break;
		}
		if (xLen < x)
			return null;
		// Remove all rows containing null
		int y0 = 0;
		int yLen = size;
		for(int i = 0; i < items.length; i += size) {
			boolean braek = false;
			for(int j = 0; j < size; j++) {
				braek = items[i+j] != null;
				if (braek)
					break;
				if (j == size-1) {
					y0++;
					yLen--;
				}
			}
			if (braek)
				break;
		}
		for(int i = items.length-size; i >= 0; i -= size) {
			boolean braek = false;
			for(int j = size-1; j >= 0; j--) {
				braek = items[i+j] != null;
				if (braek)
					break;
				if (j == 0) {
					yLen--;
				}
			}
			if (braek)
				break;
		}
		if (yLen < y)
			return null;
		
		// Check the remaining structure for the needed shape:
		int index = 0;
		for(int j = y0; j < y0+yLen; j++) {
			for(int i = x0; i < x0+xLen; i++) {
				if (items[i+j*size] != pattern[index])
					return null;
				index++;
			}
		}
		
		return result;
	}
	
	private Item shapelessCraft(Item[] items) {
		// put all items into a smaller array:
		int index = 0;
		Item[] items2 = new Item[num];
		for(int i = 0; i < items.length; i++) {
			if (items[i] != null) {
				items2[index] = items[i];
				index++;
			}
		}
		// Compare the arrays:
		for(int i = 0; i < pattern.length; i++) {
			for(int j = i; j < items2.length; j++) {
				if (items2[j] == pattern[i]) {
					items2[j] = items2[i];
					items2[i] = pattern[i];
					break;
				}
				if (j == items2.length-1)
					return null;
			}
		}
		return result;
	}
	
	@Override
	public String toString() {
		String res = "Recipe:";
		if (x == 0 || y == 0) {
			res += "\n|";
			for(int i = 0; i < pattern.length; i++) {
				if (pattern[i] == null) res += "null|";
				else res += pattern[i].getRegistryID()+"|";
			}
		} else {
			for(int i = 0; i < y; i++) {
				res += "\n|";
				for(int j = 0; j < x; j++) {
					if (pattern[i*x+j] == null) res += "null|";
					else res += pattern[i*x+j].getRegistryID()+"|";
				}
			}
		}
		res += "\n	|\n	v\n"+numRet+"*"+result.getRegistryID();
		return res;
	}

	@Override
	public boolean equals(Object other) {
		if (!(other instanceof Recipe)) return false;
		Recipe rec = (Recipe)other;
		if (x != rec.x || y != rec.y || pattern.length != rec.pattern.length) return false;
		for(int i = 0; i < pattern.length; i++) {
			if (pattern[i] != rec.pattern[i]) return false;
		}
		return true;
	}
}