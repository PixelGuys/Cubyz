package cubyz.gui.components;

import cubyz.Logger;
import cubyz.gui.Component;
import cubyz.gui.input.Mouse;
import cubyz.rendering.Graphics;
import cubyz.utils.translate.TextKey;

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
	public void render(long nvg, int x, int y) {
		Graphics.setColor(0x000000);
		Graphics.drawRect(x, y, width, height);
		if(Mouse.isLeftButtonPressed() && isInside(Mouse.getCurrentPos())) {
			if(canRepress) {
				selected = !selected;
				canRepress = false;
				if(onAction != null) {
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
			Graphics.setColor(0x32A832);
			Graphics.fillRect(x + 3, y + 3, width - 6, height - 6);
		}
		if (label != null) {
			label.render(nvg, x + width + 5, y + height/2);
		}
	}
}
