package io.cubyz.ui.components;

import io.cubyz.ui.Component;
import io.cubyz.ui.NGraphics;
import io.jungle.Window;

/**
 * A bar that shows progress :P<br>
 * TODO: Custom color.
 */

public class ProgressBar extends Component {

	int value;
	int maxValue;

	public int getValue() {
		return value;
	}

	public void setValue(int value) {
		this.value = value;
	}

	public int getMaxValue() {
		return maxValue;
	}

	public void setMaxValue(int maxValue) {
		this.maxValue = maxValue;
	}

	@Override
	public void render(long nvg, Window src, int x, int y) {
		NGraphics.setColor(0, 0, 0);
		NGraphics.drawRect(x, y, width, height);
		NGraphics.setColor(255, 0, 0);
		NGraphics.fillRect(x, y, (width / maxValue) * value, height);
	}

}
