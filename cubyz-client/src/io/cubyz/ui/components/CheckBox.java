package io.cubyz.ui.components;

import io.cubyz.Logger;
import io.cubyz.client.GameLauncher;
import io.cubyz.rendering.Window;
import io.cubyz.translate.TextKey;
import io.cubyz.ui.Component;
import io.cubyz.ui.NGraphics;

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
	}
	
	public void setLabel(String label) {
		this.label = new Label(label);
	}
	
	public void setLabel(TextKey label) {
		this.label = new Label(label);
	}
	
	public Label getLabel() {
		return label;
	}
	
	public void setOnAction(Runnable onAction) {
		this.onAction = onAction;
	}
	
	private boolean canRepress = true;

	@Override
	public void render(long nvg, Window src, int x, int y) {
		NGraphics.setColor(0, 0, 0);
		NGraphics.drawRect(x, y, width, height);
		if (GameLauncher.input.mouse.isLeftButtonPressed() && isInside(GameLauncher.input.mouse.getCurrentPos())) {
			if (canRepress) {
				selected = !selected;
				canRepress = false;
				if (onAction != null) {
					try {
						onAction.run();
					} catch(Exception e) {
						Logger.throwable(e);
					}
				}
			}
		} else {
			canRepress = true;
		}
		if (selected) {
			NGraphics.setColor(50, 200, 50);
			NGraphics.fillRect(x + 2, y + 2, width - 5, height - 5);
		}
		if (label != null) {
			label.render(nvg, src, x + width + 5, y + 10);
		}
	}
}
