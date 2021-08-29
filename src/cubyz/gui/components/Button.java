package cubyz.gui.components;

import cubyz.Logger;
import cubyz.gui.Component;
import cubyz.gui.input.Mouse;
import cubyz.rendering.Graphics;
import cubyz.rendering.text.Fonts;
import cubyz.utils.translate.TextKey;

/**
 * A pressable button which fires an event on press.<br>
 * TODO: Custom texture.
 */

public class Button extends Component {
	
	private static final int[] button = {
		156, 166, 191, // center
		166, 176, 204, // top
		160, 170, 196, // right
		145, 154, 179, // bottom
		151, 161, 186, // left
	};
	
	private static final int[] buttonPressed = {
		146, 154, 179, // center
		135, 143, 166, // top
		142, 150, 173, // right
		156, 165, 191, // bottom
		150, 159, 184, // left
	};
	
	private static final int[] buttonHovered = {
		156, 166, 221, // center
		166, 176, 234, // top
		160, 170, 226, // right
		145, 154, 209, // bottom
		151, 161, 216, // left
	};

	private boolean pressed;
	private boolean hovered;
	private boolean canRepress = true;
	private Runnable onAction;
	private Label textLabel = new Label(Fonts.PIXEL_FONT, 240);
	private Object userObject;
	
	public Button() {}
	
	public Button(TextKey key) {
		setText(key);
	}
	
	public Button(String text) {
		setText(text);
	}
	
	public TextKey getText() {
		return textLabel.getText();
	}
	
	public Object getUserObject() {
		return userObject;
	}
	
	public void setUserObject(Object obj) {
		userObject = obj;
	}

	public void setText(String text) {
		textLabel.setText(text);
	}
	
	public void setText(TextKey text) {
		textLabel.setText(text);
	}

	public void setOnAction(Runnable onAction) {
		this.onAction = onAction;
	}
	
	public float getFontSize() {
		return textLabel.getHeight();
	}

	public void setFontSize(float fontSize) {
		textLabel.setFontSize(fontSize);
	}
	
	private void drawTexture(int[] texture, int x, int y) {
		Graphics.setColor(texture[0]<<16 | texture[1]<<8 | texture[2]);
		Graphics.fillRect(x+5, y+5, width-10, height-10);
		Graphics.setColor(texture[3]<<16 | texture[4]<<8 | texture[5]);
		for(int i = 0; i < 5; i++)
			Graphics.fillRect(x+i+1, y+i, width-2*i-1, 1);
		Graphics.setColor(texture[6]<<16 | texture[7]<<8 | texture[8]);
		for(int i = 0; i < 5; i++)
			Graphics.fillRect(x+width-i-1, y+i+1, 1, height-2*i-1);
		Graphics.setColor(texture[9]<<16 | texture[10]<<8 | texture[11]);
		for(int i = 0; i < 5; i++)
			Graphics.fillRect(x+i, y+height-i-1, width-2*i-1, 1);
		Graphics.setColor(texture[12]<<16 | texture[13]<<8 | texture[14]);
		for(int i = 0; i < 5; i++)
			Graphics.fillRect(x+i, y+i, 1, height-2*i-1);
	}

	@Override
	public void render(long nvg, int x, int y) {
		if (Mouse.isLeftButtonPressed() && canRepress && isInside(Mouse.getCurrentPos())) {
			pressed = true;
			canRepress = false;
		} else if (isInside(Mouse.getCurrentPos())) {
			hovered = true;
		} else {
			hovered = false;
		}
		if (!canRepress && !Mouse.isLeftButtonPressed()) {
			pressed = false;
			canRepress = true;
			if (isInside(Mouse.getCurrentPos())) {
				if (onAction != null) {
					try {
						onAction.run();
					} catch(Exception e) {
						Logger.throwable(e);
					}
				}
			}
		}
		if (pressed) {
			drawTexture(buttonPressed, x, y);
		} else {
			if (hovered) {
				drawTexture(buttonHovered, x, y);
			} else {
				drawTexture(button, x, y);
			}
		}
		textLabel.render(nvg, x + width/2, y + height/2);
	}
	
}