package io.cubyz.ui.components;

import org.jungle.Window;

import io.cubyz.ui.Component;
import io.cubyz.ui.NGraphics;

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
	public void render(long nvg, Window src) {
		NGraphics.setColor(0, 0, 0);
		NGraphics.drawRect(x, y, width, height);
		NGraphics.setColor(255, 0, 0);
		NGraphics.fillRect(x, y, (width / maxValue) * value, height);
	}

}
