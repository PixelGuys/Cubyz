package cubyz.gui.components;

import cubyz.gui.input.Mouse;
import cubyz.rendering.Graphics;
import cubyz.rendering.text.Fonts;

import static cubyz.client.ClientSettings.GUI_SCALE;

/**
 * A slider.
 */

public class Slider extends Component {
	
	private static final int initialXOffset = 1, yOffset = 1; // How far away the slider is from the borders.
	
	private int minValue, maxValue, curValue;
	private int xOffset;
	private Runnable run;
	String text = "";
	private float fontSize = 16.0f;
	private String[] customValues = null; // The slider doesn't always deal with evenly spaced integer values.
	
	/**
	 * Creates a slider for evenly spaced integer values.
	 * @param min left-most value of the slider
	 * @param max right-most value of the slider
	 * @param startingValue
	 */
	public Slider(int min, int max, int startingValue) {
		if (min > max) throw new IllegalArgumentException("min has to be smaller than max!");
		minValue = min;
		maxValue = max;
		curValue = startingValue;
		if (curValue < min) curValue = min;
		if (curValue > max) curValue = max;
	}
	
	/**
	 * Creates a slider for custom values
	 * @param startingValue
	 * @param customValues
	 */
	public Slider(int startingValue, String[] customValues) {
		this(0, customValues.length - 1, startingValue);
		this.customValues = customValues;
	}
	
	public void setText(String text) {
		this.text = text;
	}

	public void setFontSize(float fontSize) {
		this.fontSize = fontSize;
		xOffset = (int)(initialXOffset*GUI_SCALE + height/2 - fontSize/2 - yOffset*GUI_SCALE);
	}

	public void setOnAction(Runnable run) {
		this.run = run;
	}
	
	public int getValue() {
		return curValue;
	}
	
	@Override
	public void setBounds(int x, int y, int width, int height, byte align) {
		super.setBounds(x, y, width, height, align);
		xOffset = (int)(initialXOffset*GUI_SCALE + height/2 - fontSize/2 - yOffset*GUI_SCALE);
	}

	@Override
	public void render(int x, int y) {
		if (Mouse.isLeftButtonPressed() && isInside(Mouse.getCurrentPos())) {
			double dx = Mouse.getCurrentPos().x - x;
			dx -= xOffset;
			dx = dx/(super.width - 2*xOffset);
			dx *= maxValue - minValue;
			dx += minValue;
			int newValue = (int)dx;
			if (curValue != newValue) {
				curValue = newValue;
				if (curValue < minValue) curValue = minValue;
				if (curValue > maxValue) curValue = maxValue;
				run.run();
			}
		}

		Graphics.setColor(0x7F7FA0);
		Graphics.fillRect(x, y, width, height);
		Graphics.setColor(0xA0A0C8);
		Graphics.fillRect(x + initialXOffset*GUI_SCALE, y + yOffset*GUI_SCALE + fontSize, width - 2*initialXOffset*GUI_SCALE, height - 2*yOffset*GUI_SCALE - fontSize);
		Graphics.setColor(0xC8C8F0);
		Graphics.fillCircle(x + xOffset + (float)(curValue - minValue)/(maxValue-minValue)*(width - 2*xOffset), y + height/2 + fontSize/2, height/2 - fontSize/2 - yOffset*GUI_SCALE);
		Graphics.setColor(0xffffff);
		Graphics.setFont(Fonts.PIXEL_FONT, fontSize);
		Graphics.drawText(x + initialXOffset*GUI_SCALE, y + yOffset*GUI_SCALE, text + (customValues != null ? customValues[curValue] : curValue));
	}
}
