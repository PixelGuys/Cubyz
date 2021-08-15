package cubyz.gui;

import java.awt.Rectangle;

import org.joml.Vector2d;

import cubyz.client.rendering.Window;
import cubyz.gui.input.MouseInput;

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

	private int x, y, lastRenderX, lastRenderY;
	private byte align;

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

	public void render(long nvg, Window src) {
		// Calculate coordinates in the window:
		if((align & ALIGN_LEFT) != 0) {
			lastRenderX = x;
		} else if((align & ALIGN_RIGHT) != 0) {
			lastRenderX = src.getWidth() - x;
		} else {
			lastRenderX = src.getWidth()/2 + x;
		}
		if((align & ALIGN_TOP) != 0) {
			lastRenderY = y;
		} else if((align & ALIGN_BOTTOM) != 0) {
			lastRenderY = src.getHeight() - y;
		} else {
			lastRenderY = src.getHeight()/2 + y;
		}
		// Call the subclass render function:
		render(nvg, src, lastRenderX, lastRenderY);
	}
	
	/**
	 * Renders directly on the screen, without further considering alignment. Only call, if you know what you are doing.
	 * @param nvg
	 * @param src
	 * @param x coordinate with alignment considered.
	 * @param y coordinate with alignment considered.
	 */
	public abstract void render(long nvg, Window src, int x, int y);
	
	public void init(long nvg, Window src) {}
	public void dispose(long nvg, Window src) {}
	public void input(MouseInput mouse) {} // TODO: use in ScrollingContainer
	
}