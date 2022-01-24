package cubyz.gui.components;

import java.awt.Rectangle;

import org.joml.Vector2d;

import cubyz.rendering.Window;

/**
 * A type for basic components of the GUI system.
 */

public abstract class Component {
	/**How the coordinates are given relative to bounding frame.*/
	public static final byte	ALIGN_TOP_LEFT		= 0b0101,
								ALIGN_TOP			= 0b0100,
								ALIGN_TOP_RIGHT		= 0b0110,
								ALIGN_LEFT			= 0b0001,
								ALIGN_CENTER		= 0b0000,
								ALIGN_RIGHT			= 0b0010,
								ALIGN_BOTTOM_LEFT	= 0b1001,
								ALIGN_BOTTOM		= 0b1000,
								ALIGN_BOTTOM_RIGHT	= 0b1010;

	protected int x, y;
	private int lastRenderX, lastRenderY;
	protected byte align;

	protected int width, height;
	

	public final int getX() {
		return x;
	}

	public final int getY() {
		return y;
	}

	public void setY(int y) {
		this.y = y;
	}

	public int getWidth() {
		return width;
	}

	public int getHeight() {
		return height;
	}
	
	public void setPosition(int x, int y, byte align) {
		this.x = x;
		this.y = y;
		this.align = align;
	}
	
	public void setBounds(int x, int y, int width, int height, byte align) {
		this.x = x;
		this.y = y;
		this.width = width;
		this.height = height;
		this.align = align;
	}
	
	public boolean isInside(int x, int y) {
		Rectangle hitbox = new Rectangle(this.lastRenderX, this.lastRenderY, width, height);
		return hitbox.contains(x, y);
	}
	
	public boolean isInside(Vector2d vec) {
		return isInside((int) vec.x, (int) vec.y);
	}

	public final void render() {
		renderInContainer(0, 0, Window.getWidth(), Window.getHeight());
	}

	public final void renderInContainer(int containerX, int containerY, int width, int height) {
		// Calculate coordinates in the container:
		if ((align & ALIGN_LEFT) != 0) {
			lastRenderX = x + containerX;
		} else if ((align & ALIGN_RIGHT) != 0) {
			lastRenderX = width - x + containerX;
		} else {
			lastRenderX = width/2 + x + containerX;
		}
		if ((align & ALIGN_TOP) != 0) {
			lastRenderY = y + containerY;
		} else if ((align & ALIGN_BOTTOM) != 0) {
			lastRenderY = height - y + containerY;
		} else {
			lastRenderY = height/2 + y + containerY;
		}
		// Call the subclass render function:
		render(lastRenderX, lastRenderY);
	}
	
	/**
	 * Renders directly on the screen, without further considering alignment. Only call, if you know what you are doing.
	 * @param nvg
	 * @param src
	 * @param x coordinate with alignment considered.
	 * @param y coordinate with alignment considered.
	 */
	public abstract void render(int x, int y);
	
	public void init() {}
	public void dispose() {}
	
}