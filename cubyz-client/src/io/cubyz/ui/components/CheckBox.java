package io.cubyz.ui.components;

import io.cubyz.client.Cubyz;
import io.cubyz.translate.TextKey;
import io.cubyz.ui.Component;
import io.cubyz.ui.NGraphics;
import io.jungle.Window;

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
	
	public void setOnAction(Runnable onAction) {
		this.onAction = onAction;
	}
	
	private boolean canRepress = true;

	@Override
	public void render(long nvg, Window src) {
		NGraphics.setColor(0, 0, 0);
		NGraphics.drawRect(x, y, width, height);
		if (Cubyz.mouse.isLeftButtonPressed() && isInside(Cubyz.mouse.getCurrentPos())) {
			if (canRepress) {
				selected = !selected;
				canRepress = false;
				if (onAction != null) {
					onAction.run();
				}
			}
		} else {
			canRepress = true;
		}
		if (selected) {
			NGraphics.setColor(50, 200, 50);
			NGraphics.fillRect(x+2, y+2, width-5, height-5);
		}
		if (label != null) {
			label.setPosition(x + width + 5, y + 10);
			label.render(nvg, src);
		}
	}
}
