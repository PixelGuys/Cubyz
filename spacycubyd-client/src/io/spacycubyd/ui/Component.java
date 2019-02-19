package io.spacycubyd.ui;

import java.awt.Rectangle;

import org.joml.Vector2d;
import org.jungle.Window;

public abstract class Component {

	protected int x, y, width, height;
	

	public int getX() {
		return x;
	}

	public void setX(int x) {
		this.x = x;
	}

	public int getY() {
		return y;
	}

	public void setY(int y) {
		this.y = y;
	}

	public int getWidth() {
		return width;
	}

	public void setWidth(int width) {
		this.width = width;
	}

	public int getHeight() {
		return height;
	}

	public void setHeight(int height) {
		this.height = height;
	}
	
	public void setSize(int w, int h) {
		width = w;
		height = h;
	}
	
	public void setPosition(int w, int h) {
		x = w;
		y = h;
	}
	
	public boolean isInside(int x, int y) {
		Rectangle hitbox = new Rectangle(this.x, this.y, width, height);
		return hitbox.contains(x, y);
	}
	
	public boolean isInside(Vector2d vec) {
		return isInside((int) vec.x, (int) vec.y);
	}
	
	public abstract void render(long nvg, Window src);
	
}