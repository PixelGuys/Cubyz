package io.cubyz.ui.components;

import io.cubyz.client.GameLauncher;
import io.cubyz.input.MouseInput;
import io.cubyz.rendering.Window;
import io.cubyz.translate.TextKey;
import io.cubyz.ui.Component;
import io.cubyz.ui.NGraphics;

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
	private float fontSize = 12f;
	private TextKey text;
	private Object userObject;
	
	public Button() {}
	
	public Button(TextKey key) {
		setText(key);
	}
	
	public Button(String text) {
		setText(text);
	}
	
	public TextKey getText() {
		return text;
	}
	
	public Object getUserObject() {
		return userObject;
	}
	
	public void setUserObject(Object obj) {
		userObject = obj;
	}

	public void setText(String text) {
		this.text = TextKey.createTextKey(text);
	}
	
	public void setText(TextKey text) {
		this.text = text;
	}

	public void setOnAction(Runnable onAction) {
		this.onAction = onAction;
	}
	
	public float getFontSize() {
		return fontSize;
	}

	public void setFontSize(float fontSize) {
		this.fontSize = fontSize;
	}
	
	private void drawTexture(int[] texture, int x, int y) {
		NGraphics.setColor(texture[0], texture[1], texture[2]);
		NGraphics.fillRect(x+5, y+5, width-10, height-10);
		NGraphics.setColor(texture[3], texture[4], texture[5]);
		for(int i = 0; i < 5; i++)
			NGraphics.fillRect(x+i+1, y+i, width-2*i-1, 1);
		NGraphics.setColor(texture[6], texture[7], texture[8]);
		for(int i = 0; i < 5; i++)
			NGraphics.fillRect(x+width-i-1, y+i+1, 1, height-2*i-1);
		NGraphics.setColor(texture[9], texture[10], texture[11]);
		for(int i = 0; i < 5; i++)
			NGraphics.fillRect(x+i, y+height-i-1, width-2*i-1, 1);
		NGraphics.setColor(texture[12], texture[13], texture[14]);
		for(int i = 0; i < 5; i++)
			NGraphics.fillRect(x+i, y+i, 1, height-2*i-1);
	}

	@Override
	public void render(long nvg, Window src, int x, int y) {
		MouseInput mouse = GameLauncher.input.mouse;
		if (mouse.isLeftButtonPressed() && canRepress && isInside(mouse.getCurrentPos())) {
			pressed = true;
			canRepress = false;
		} else if (isInside(mouse.getCurrentPos())) {
			hovered = true;
		} else {
			hovered = false;
		}
		if (!canRepress && !mouse.isLeftButtonPressed()) {
			pressed = false;
			canRepress = true;
			if (isInside(mouse.getCurrentPos())) {
				if (onAction != null) {
					onAction.run();
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
		NGraphics.setColor(255, 255, 255);
		NGraphics.setFont("Default", fontSize);
		NGraphics.drawText(x + (width / 2) - ((text.getTranslation().length() * 5) / 2), (int) (y + (height / 2) - fontSize / 2), text.getTranslation());
		//int ascent = NGraphics.getAscent("ahh");
	}
	
}