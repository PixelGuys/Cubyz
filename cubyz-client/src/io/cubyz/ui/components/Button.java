package io.cubyz.ui.components;

import org.jungle.MouseInput;
import org.jungle.Window;

import io.cubyz.client.Cubyz;
import io.cubyz.translate.TextKey;
import io.cubyz.ui.Component;
import io.cubyz.ui.NGraphics;
import io.cubyz.ui.UISystem;

public class Button extends Component {

	private boolean pressed;
	private boolean canRepress = true;
	private Runnable run;
	private float fontSize = 12f;
	private TextKey text;
	
	public TextKey getText() {
		return text;
	}

	public void setText(String text) {
		this.text = new TextKey(text);
	}
	
	public void setText(TextKey text) {
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
		MouseInput mouse = Cubyz.mouse;
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
		NGraphics.setFont("OpenSans Bold", fontSize);
		NGraphics.drawText(x + (width / 2) - ((text.getTranslation(Cubyz.lang).length() * 5) / 2), (int) (y + (height / 2) - fontSize / 2), text.getTranslation(Cubyz.lang));
		//int ascent = NGraphics.getAscent("ahh");
	}
	
}