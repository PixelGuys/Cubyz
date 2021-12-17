package cubyz.gui.components;

import java.util.ArrayList;
import java.util.List;

import org.joml.Vector4i;

import cubyz.rendering.Graphics;
import cubyz.rendering.Window;

/**
 * A Component that contains other Components.
 */

public abstract class Container extends Component {

	protected ArrayList<Component> children;
	
	public Container() {
		children = new ArrayList<>();
	}
	
	public void add(Component comp) {
		if (comp == this) throw new IllegalArgumentException("comp == this");
		children.add(comp);
	}
	
	public void remove(Component comp) {
		children.remove(comp);
	}
	
	public void remove(int index) {
		children.remove(index);
	}

	public void clear() {
		children.clear();
	}

	@Override
	public void render(int x, int y) {
		Vector4i oldClip = Graphics.setClip(new Vector4i(x, Window.getHeight() - y - height, width, height));
		for (Component child : children) {
			child.renderInContainer(x, y, width, height);
		}
		Graphics.restoreClip(oldClip);
	}

	public List<Component> getChildren() {
		return children;
	}
}
