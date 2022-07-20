package cubyz.gui.components;

import org.joml.Vector4i;

import cubyz.gui.input.Mouse;
import cubyz.rendering.Graphics;
import cubyz.rendering.Window;

public class ScrollingContainer extends Container {

	int maxY = 0;
	int scrollY = 0;
	int scrollBarWidth = 20;
	
	int mPickY = -1;

	private byte interiorAlign = ALIGN_BOTTOM;
	
	@Override
	public void render(int x, int y) {
		Vector4i oldClip = Graphics.setClip(new Vector4i(x, Window.getHeight() - y - height, width, height));
		maxY = 0;
		for (Component child : children.toArray()) {
			maxY = Math.max(maxY, child.getY()+child.getHeight());
			child.renderInContainer(x, y - scrollY, width, height);
		}
		maxY -= height;
		if (maxY > 0) {
			Graphics.setColor(0x000000);
			Graphics.fillRect(x + width - scrollBarWidth, y, scrollBarWidth, height);
			Graphics.setColor(0xffffff);
			Graphics.fillRect(x + width - scrollBarWidth, y+(scrollY/((float) maxY / height)), scrollBarWidth, 10);
			if (mPickY == -1) {
				if (Mouse.getX() > x + width - scrollBarWidth && Mouse.getX() < x + width) {
					if (Mouse.getY() > y && Mouse.getY() < height) {
						if (Mouse.isLeftButtonPressed()) {
							mPickY = (int) Mouse.getY();
						}
					}
				}
			} else {
				if (Mouse.isLeftButtonPressed()) {
					scrollY = (int) Math.min(maxY, Mouse.getY()*(maxY/height) + mPickY);
				} else {
					mPickY = -1;
				}
			}
			scrollY += -Mouse.getScrollOffset() * 40;
			if (scrollY < 0) scrollY = 0;
			scrollY = Math.min(maxY, scrollY);
		} else {
			if((interiorAlign & ALIGN_TOP) != 0) {
				scrollY = 0;
			} else if((interiorAlign & ALIGN_BOTTOM) != 0) {
				scrollY = maxY;
			} else {
				scrollY = maxY/2;
			}
		}
		Graphics.restoreClip(oldClip);
	}

	public void setInteriorAlign(byte interiorAlign) {
		this.interiorAlign = interiorAlign;
	}

    public void scrollToEnd(){
        scrollY = height;
    }
}