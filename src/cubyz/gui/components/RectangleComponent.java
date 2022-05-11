package cubyz.gui.components;

import cubyz.rendering.Graphics;

public class RectangleComponent extends Component {

	private final int color;

	public RectangleComponent(int color) {
		this.color = color;
	}

	@Override
	public void render(int x, int y) {
		Graphics.setColor(color);
		Graphics.fillRect(x, y, width, height);
	}

}
