package cubyz.gui.components;

import cubyz.gui.Component;
import cubyz.rendering.Graphics;

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
	public void render(long nvg, int x, int y) {
		Graphics.setColor(0xff0000);
		Graphics.fillRect(x, y, (width / maxValue) * value, height);
		Graphics.setColor(0x000000);
		Graphics.drawRect(x, y, width, height);
	}

}
