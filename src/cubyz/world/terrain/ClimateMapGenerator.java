package cubyz.world.terrain;

import cubyz.api.RegistryElement;

public interface ClimateMapGenerator extends RegistryElement {
	abstract void generateMapFragment(ClimateMapFragment fragment);
}