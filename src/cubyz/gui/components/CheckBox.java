package cubyz.gui.components;

import cubyz.utils.Logger;
import cubyz.gui.input.Mouse;
import cubyz.rendering.Graphics;
import cubyz.utils.translate.TextKey;

import static cubyz.client.ClientSettings.GUI_SCALE;

/**
 * A simple checkbox which fires an event on change.
 */

public class CheckBox extends Component {
	private boolean selected = false;
	private Label label;
	private Runnable onAction;
	
	public CheckBox() {
		width = 32;
		height = 32;
	}
	
	public boolean isSelected() {
		return selected;
	}
	
	public void setSelected(boolean selected) {
		this.selected = selected;
	}
	
	public void setLabel(Label label) {
		this.label = label;
		this.label.setTextAlign(ALIGN_LEFT);
	}
	
	public void setLabel(String label) {
		this.label = new Label(label);
		this.label.setTextAlign(ALIGN_LEFT);
	}
	
	public void setLabel(TextKey label) {
		this.label = new Label(label);
		this.label.setTextAlign(ALIGN_LEFT);
	}
	
	public Label getLabel() {
		return label;
	}
	
	public void setOnAction(Runnable onAction) {
		this.onAction = onAction;
	}
	
	private boolean canRepress = true;

	@Override
	public void render(int x, int y) {
		Graphics.setColor(0x000000);
		Graphics.drawRect(x, y, width, height);
		if (Mouse.isLeftButtonPressed() && isInside(Mouse.getCurrentPos())) {
			if (canRepress) {
				selected = !selected;
				canRepress = false;
				if (onAction != null) {
					try {
						onAction.run();
					} catch(Exception e) {
						Logger.error(e);
					}
				}
			}
		} else {
			canRepress = true;
		}
		if (selected) {
			Graphics.setColor(0x32A832);
			Graphics.fillRect(x + 2 * GUI_SCALE, y + 2 * GUI_SCALE, width - 4 * GUI_SCALE, height - 4 * GUI_SCALE);
		}
		if (label != null) {
			label.render(x + width + 4 * GUI_SCALE + 1, y + height/2);
		}
	}
}
