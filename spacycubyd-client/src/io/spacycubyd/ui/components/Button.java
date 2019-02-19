package io.spacycubyd.ui.components;

import org.jungle.MouseInput;
import org.jungle.Window;

import io.spacycubyd.client.SpacyCubyd;
import io.spacycubyd.ui.Component;
import io.spacycubyd.ui.NGraphics;
import io.spacycubyd.ui.UISystem;

public class Button extends Component {

	private boolean pressed;
	private boolean canRepress = true;
	private Runnable run;
	private float fontSize = 12f;
	private String text = "";
	
	public String getText() {
		return text;
	}

	public void setText(String text) {
		this.text = text;
	}

	public void setOnAction(Runnable run) {
		this.run = run;
	}
	
	public float getFontSize() {
		return fontSize;
	}

	public void setFontSize(float fontSize) {
		this.fontSize = fontSize;
	}

	@Override
	public void render(long nvg, Window src) {
		MouseInput mouse = SpacyCubyd.mouse;
		if (mouse.isLeftButtonPressed() && canRepress && isInside(mouse.getCurrentPos())) {
			pressed = true;
			canRepress = false;
		}
		if (!canRepress && !mouse.isLeftButtonPressed()) {
			pressed = false;
			canRepress = true;
			if (isInside(mouse.getCurrentPos())) {
				if (run != null) {
					run.run();
				}
			}
		}
		if (pressed) {
			NGraphics.setColor(200, 200, 200);
		} else {
			NGraphics.setColor(150, 150, 150);
		}
		NGraphics.fillRect(x, y, width, height);
		NGraphics.setColor(255, 255, 255);
		NGraphics.setFont(UISystem.OPENSANS, fontSize);
		
		NGraphics.drawText(x + (width / 2) - ((text.length() * 5) / 2), (int) (y + (height / 2) - fontSize / 2), text);
		//int ascent = NGraphics.getAscent("ahh");
	}

}
