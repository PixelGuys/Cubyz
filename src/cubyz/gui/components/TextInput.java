package cubyz.gui.components;

import cubyz.client.GameLauncher;
import cubyz.client.rendering.Font;
import cubyz.client.rendering.Window;
import cubyz.gui.Component;
import cubyz.gui.NGraphics;
import cubyz.gui.input.Keyboard;

/**
 * Just a text field.
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
	public void render(long nvg, Window src, int x, int y) {
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
		
		if (GameLauncher.input.mouse.isLeftButtonPressed() && !hasPressed) {
			hasPressed = true;
		} else if (!GameLauncher.input.mouse.isLeftButtonPressed()) {
			if (hasPressed) { // just released left button
				if (isInside(GameLauncher.input.mouse.getCurrentPos())) {
					focused = true;
				} else {
					focused = false;
				}
			}
			hasPressed = false;
		}
		
		if (focused) {
			if (Keyboard.hasCharSequence()) {
				char[] chars = Keyboard.getCharSequence();
				for(int i = 0; i < chars.length; i++) {
					if(chars[i] == '\0') { // Backspace.
						if(text.length() > 0)
							text = text.substring(0, text.length() - 1);
					} else {
						text += chars[i];
					}
				}
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
