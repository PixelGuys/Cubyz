package cubyz.gui.components;

import cubyz.client.GameLauncher;
import cubyz.client.rendering.Window;
import cubyz.gui.Component;
import cubyz.gui.NGraphics;
import cubyz.gui.input.MouseInput;

/**
 * A slider.
 */

public class Slider extends Component {
	
	private static final int initialXOffset = 5, yOffset = 5; // How far away the slider is from the borders.
	
	private int minValue, maxValue, curValue;
	private int xOffset;
	private Runnable run;
	String text = "";
	private float fontSize = 12.0f;
	private String[] customValues = null; // The slider doesn't always deal with evenly spaced integer values.
	
	/**
	 * Creates a slider for evenly spaced integer values.
	 * @param min left-most value of the slider
	 * @param max right-most value of the slider
	 * @param startingValue
	 */
	public Slider(int min, int max, int startingValue) {
		if(min > max) throw new IllegalArgumentException("min has to be smaller than max!");
		minValue = min;
		maxValue = max;
		curValue = startingValue;
		if(curValue < min) curValue = min;
		if(curValue > max) curValue = max;
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
		xOffset = (int)(initialXOffset + height/2 - fontSize/2 - yOffset);
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
		xOffset = (int)(initialXOffset + height/2 - fontSize/2 - yOffset);
	}

	@Override
	public void render(long nvg, Window src, int x, int y) {
		MouseInput mouse = GameLauncher.input.mouse;
		if (mouse.isLeftButtonPressed() && isInside(mouse.getCurrentPos())) {
			double dx = mouse.getCurrentPos().x - x;
			dx -= xOffset;
			dx = dx/(super.width - 2*xOffset);
			dx *= maxValue - minValue;
			dx += minValue;
			int newValue = (int)dx;
			if(curValue != newValue) {
				curValue = newValue;
				if(curValue < minValue) curValue = minValue;
				if(curValue > maxValue) curValue = maxValue;
				run.run();
			}
		}

		NGraphics.setColor(127, 127, 160);
		NGraphics.fillRect(x, y, width, height);
		NGraphics.setColor(160, 160, 200);
		NGraphics.fillRect(x + initialXOffset, y + yOffset + fontSize, width - 2*initialXOffset, height - 2*yOffset - fontSize);
		NGraphics.setColor(200, 200, 240);
		NGraphics.fillCircle((int)(x + xOffset + (float)(curValue - minValue)/(maxValue-minValue)*(width - 2*xOffset)), y + height/2 + fontSize/2, (int)(height/2 - fontSize/2 - yOffset));
		NGraphics.setColor(255, 255, 255);
		NGraphics.setFont("Default", fontSize);
		NGraphics.drawText(x + initialXOffset, y + yOffset, text + (customValues != null ? customValues[curValue] : curValue));
	}
}
