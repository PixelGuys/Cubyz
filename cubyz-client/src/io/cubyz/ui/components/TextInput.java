package io.cubyz.ui.components;

import org.jungle.Keyboard;
import org.jungle.Window;
import org.jungle.hud.Font;
import org.lwjgl.glfw.GLFW;

import io.cubyz.ui.Component;
import io.cubyz.ui.NGraphics;

public class TextInput extends Component {

	private Font font = new Font("OpenSans Bold", 12.f);
	public String text = "";
	
	public String getText() {
		return text;
	}

	public void setText(String text) {
		this.text = text;
	}

	public Font getFont() {
		return font;
	}
	
	public void setFont(Font font) {
		this.font = font;
	}

	@Override
	public void render(long nvg, Window src) {
		NGraphics.setColor(255, 255, 255);
		NGraphics.fillRect(x, y, width, height);
		NGraphics.setColor(0, 0, 0);
		NGraphics.setFont(font);
		NGraphics.drawText(x, y, text);
		if (Keyboard.hasCodePoint()) {
			text = text + Keyboard.getCodePoint();
		}
		if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_BACKSPACE)) {
			if (text.length() > 0) {
				text = text.substring(0, text.length()-1);
			}
			Keyboard.setKeyPressed(GLFW.GLFW_KEY_BACKSPACE, false);
		}
	}
	
}
