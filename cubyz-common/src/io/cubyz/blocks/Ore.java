package io.cubyz.blocks;

public class Ore extends Block {

	private float chance;
	private int height;

	public float getChance() {
		return chance;
	}

	public int getHeight() {
		return height;
	}

	public void setChance(float chance) {
		this.chance = chance;
	}

	public void setHeight(int height) {
		this.height = height;
	}
	
}