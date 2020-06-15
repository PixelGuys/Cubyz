package io.cubyz.ui.components;

import io.cubyz.client.Cubyz;
import io.cubyz.ui.Component;
import io.cubyz.ui.NGraphics;
import io.jungle.MouseInput;
import io.jungle.Window;

public class Slider extends Component {
	
	private static final int initialXOffset = 5, yOffset = 5; // How far away the slider is from the borders.
	
	private int minValue, maxValue, curValue;
	private int xOffset;
	private Runnable run;
	String text = "";
	private float fontSize = 12.0f;
	
	public Slider(int min, int max, int cur) {
		minValue = min;
		maxValue = max;
		curValue = cur;
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
	public void setSize(int width, int height) {
		super.setSize(width, height);
		xOffset = (int)(initialXOffset + height/2 - fontSize/2 - yOffset);
	}

	@Override
	public void render(long nvg, Window src) {
		MouseInput mouse = Cubyz.mouse;
		if (mouse.isLeftButtonPressed() && isInside(mouse.getCurrentPos())) {
			double dx = mouse.getCurrentPos().x - super.x;
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
		NGraphics.drawText(x + initialXOffset, y + yOffset, text + curValue);
	}
}
