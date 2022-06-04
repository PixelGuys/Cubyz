package cubyz.modding.base;

import cubyz.api.ClientRegistries;
import cubyz.api.CubyzRegistries;
import cubyz.client.BlockMeshes;
import cubyz.gui.game.inventory.CreativeGUI;
import cubyz.gui.game.inventory.WorkbenchGUI;
import cubyz.rendering.models.CubeModel;
import cubyz.rendering.rotation.*;

/**
 * Registers objects that are only available on the client.
 */

public class ClientProxy extends CommonProxy {

	public void init() {
		super.init();
		ClientRegistries.GUIS.register(new WorkbenchGUI());
		ClientRegistries.GUIS.register(new CreativeGUI());
	}
	
	public void preInit() {
		CubeModel.registerCubeModels();

		CubyzRegistries.BLOCK_REGISTRIES.register(new BlockMeshes());

		CubyzRegistries.BLOCK_REGISTRIES.register((MultiTexture)CubyzRegistries.ROTATION_MODE_REGISTRY.getByID("cubyz:multi_texture"));
	}
	
}
