package io.cubyz.ui.components;

import org.jungle.MouseInput;
import org.jungle.Window;

import io.cubyz.client.Cubyz;
import io.cubyz.ui.Component;
import io.cubyz.ui.NGraphics;

public class ScrollingContainer extends Container {

	int maxY = 0;
	int scrollY = 0;
	int scrollBarWidth = 20;
	
	int mPickY = -1;
	
	public void render(long nvg, Window src) {
		MouseInput mouse = Cubyz.mouse;
		maxY = 0;
		for (Component child : childrens) {
			maxY = Math.max(maxY, child.getY());
			child.setY(child.getY() - scrollY);
			child.render(nvg, src);
			child.setY(child.getY() + scrollY);
		}
		if (maxY > height) {
			NGraphics.setColor(0, 0, 0);
			NGraphics.fillRect(x + width - scrollBarWidth, y, scrollBarWidth, 10);
			if (mPickY == -1) {
				if (mouse.getX() > x + width - scrollBarWidth && mouse.getX() < x + width) {
					if (mouse.getY() > y && mouse.getY() < height) {
						if (mouse.isLeftButtonPressed()) {
							mPickY = (int) mouse.getY();
						}
					}
				}
			} else {
				if (mouse.isLeftButtonPressed()) {
					scrollY = (int) Math.min(maxY, mouse.getY() - mPickY);
				} else {
					mPickY = -1;
				}
			}
		}
		scrollY = Math.min(maxY, scrollY);
	}
	
}
