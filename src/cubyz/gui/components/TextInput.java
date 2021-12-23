package cubyz.gui.components;

import cubyz.gui.input.Keyboard;
import cubyz.gui.input.Mouse;
import cubyz.rendering.Graphics;
import cubyz.rendering.text.CubyzFont;
import cubyz.rendering.text.Fonts;
import cubyz.rendering.text.TextLine;

/**
 * Just a text field.
 */

public class TextInput extends Component {

	public TextLine textLine = new TextLine(Fonts.PIXEL_FONT, "", 16, true);
	private boolean focused;
	private boolean hasPressed;
	
	
	public String getText() {
		return textLine.getText();
	}

	public void setText(String text) {
		textLine.updateText(text);
	}

	public void setFocused(boolean focused) {
		this.focused = focused;
		this.hasPressed = true;
	}
	
	public void setFontSize(float fontSize) {
		setFont(this.textLine.font, fontSize);
	}

	public void setFont(CubyzFont font, float fontSize) {
		textLine = new TextLine(font, textLine.getText(), fontSize, true);
	}

	@Override
	public void render(int x, int y) {
		Graphics.setColor(0x7F7F7F);
		Graphics.fillRect(x - 3, y - 3, width + 6, height + 6);
		
		if (focused)
			Graphics.setColor(0xC8C8C8);
		else
			Graphics.setColor(0xffffff);
		Graphics.fillRect(x, y, width, height);
		Graphics.setColor(0x000000);
		Graphics.setFont(Fonts.PIXEL_FONT, 16);
		
		if (Mouse.isLeftButtonPressed()) {
			if (isInside(Mouse.getCurrentPos()) || hasPressed) {
				if (!hasPressed) { // Started pressing
					hasPressed = true;
					textLine.startSelection((float)Mouse.getX() - x);
				} else { // Is pressing
					textLine.changeSelection((float)Mouse.getX() - x);
				}
			} else {
				textLine.unselect();
			}
		} else if (!Mouse.isLeftButtonPressed()) {
			if (hasPressed) { // just released left button
				focused = true;
				hasPressed = false;
				textLine.endSelection((float)Mouse.getX() - x);
			}
		}
		
		textLine.render(x + 2, y);
		
		if (focused) {
			if (Keyboard.hasCharSequence()) {
				char[] chars = Keyboard.getCharSequence();
				textLine.addText(new String(chars));
			}
		}
	}
	
}
