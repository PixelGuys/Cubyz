package io.cubyz.ui.components;

import org.lwjgl.glfw.GLFW;

import io.cubyz.client.Cubyz;
import io.cubyz.ui.Component;
import io.cubyz.ui.NGraphics;
import io.jungle.Keyboard;
import io.jungle.Window;
import io.jungle.hud.Font;

/**
 * Just a text field.<br>
 * TODO: In most utilities you will start writing multiple characters, after pressing a key for longer time(the exact timing is defined in the OS), you will write more characters.
 */

public class TextInput extends Component {

	private Font font = new Font("Default", 12.f);
	public String text = "";
	private boolean focused;
	
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
	
	private boolean hasPressed;
	private boolean cursorVisible;
	private int cursorCounter;

	@Override
	public void render(long nvg, Window src) {
		NGraphics.setColor(127, 127, 127);
		NGraphics.fillRect(x - 3, y - 3, width + 6, height + 6);
		
		if (focused)
			NGraphics.setColor(200, 200, 200);
		else
			NGraphics.setColor(255, 255, 255);
		NGraphics.fillRect(x, y, width, height);
		NGraphics.setColor(0, 0, 0);
		NGraphics.setFont(font);
		float textWidth = NGraphics.getTextWidth(text);
		float textHeight = NGraphics.getTextAscent(text);
		NGraphics.drawText(x + 2, y + height/2 - textHeight, text);
		
		if (Cubyz.mouse.isLeftButtonPressed() && !hasPressed) {
			hasPressed = true;
		} else if (!Cubyz.mouse.isLeftButtonPressed()) {
			if (hasPressed) { // just released left button
				if (isInside(Cubyz.mouse.getCurrentPos())) {
					focused = true;
				} else {
					focused = false;
				}
			}
			hasPressed = false;
		}
		
		if (focused) {
			if (Keyboard.hasCharSequence()) {
				text = text + Keyboard.getCharSequence();
				cursorVisible = true;
			}
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_BACKSPACE)) {
				if (text.length() > 0) {
					text = text.substring(0, text.length() - 1);
				}
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_BACKSPACE, false);
				cursorVisible = true;
			}
			
			if (cursorVisible) {
				NGraphics.setColor(0, 0, 0);
				NGraphics.drawText(x + 2 + textWidth, y + height/2 - textHeight, "_");
			}
			
			if (cursorCounter >= 30) {
				cursorVisible = !cursorVisible;
				cursorCounter = 0;
			}
			cursorCounter++;
		}
	}
	
}
