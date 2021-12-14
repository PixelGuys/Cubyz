package cubyz.world.terrain;

import cubyz.api.RegistryElement;

public interface MapGenerator extends RegistryElement {
	abstract void generateMapFragment(MapFragment fragment);
}
