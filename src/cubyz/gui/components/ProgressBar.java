package cubyz.gui.components;

import cubyz.rendering.Graphics;

/**
 * A bar that shows progress :P<br>
 * TODO: Custom color.
 */

public class ProgressBar extends Component {
	private int value;
	private int maxValue;
	private int alpha = 255;

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
	
	public void setColorAlpha(int alpha) {
		this.alpha = alpha;
	}
	
	public int getColorAlpha() {
		return alpha;
	}

	@Override
	public void render(int x, int y) {
		Graphics.setColor(0xff0000, alpha);
		Graphics.fillRect(x, y, (width / maxValue) * value, height);
		Graphics.setColor(0x000000, alpha);
		Graphics.drawRect(x, y, width, height);
	}

}
