package cubyz.gui.components;

import cubyz.utils.Logger;
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
	private Runnable onAction;
	private Label textLabel = new Label(Fonts.PIXEL_FONT, 240);

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
	public void render(int x, int y) {
		boolean hovered = isInside(Mouse.getCurrentPos());
		boolean toggled = Mouse.isLeftButtonPressed() != pressed;
		pressed = pressed ^ toggled;
		if (!pressed && toggled && hovered) {
			if (onAction != null) {
				try {
					onAction.run();
				} catch(Exception e) {
					Logger.error(e);
				}
			}
		}
		if (hovered) {
			if (pressed) {
				drawTexture(buttonPressed, x, y);
			} else {
				drawTexture(buttonHovered, x, y);
			}
		} else{
			drawTexture(button, x, y);
		}
		textLabel.render(x + width/2, y + height/2);
	}

}