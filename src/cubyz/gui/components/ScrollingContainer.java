package cubyz.gui.components;

import cubyz.gui.Component;
import cubyz.gui.NGraphics;
import cubyz.gui.input.Mouse;

public class ScrollingContainer extends Container {

	int maxY = 0;
	int scrollY = 0;
	int scrollBarWidth = 20;
	
	int mPickY = -1;
	
	@Override
	public void render(long nvg, int x, int y) {
		maxY = 0;
		for (Component child : childrens) {
			maxY = Math.max(maxY, child.getY()+child.getHeight());
			child.setY(child.getY() - scrollY);
			child.render(nvg);
			child.setY(child.getY() + scrollY);
		}
		if (maxY > height) {
			NGraphics.setColor(0, 0, 0);
			NGraphics.fillRect(x + width - scrollBarWidth, y, scrollBarWidth, height);
			NGraphics.setColor(255, 255, 255);
			NGraphics.fillRect(x + width - scrollBarWidth, (int) (y+(scrollY/((float) maxY / height))), scrollBarWidth, 10);
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
		} else {
			scrollY = 0;
		}
		scrollY = Math.min(maxY, scrollY);
	}
	
}