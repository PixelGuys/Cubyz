package cubyz.command;

import cubyz.api.Resource;
import cubyz.world.entity.Player;
import cubyz.world.items.Inventory;
import cubyz.world.items.ItemStack;

/**
 * Clears the inventory of the local player.
 */

public class ClearCommand extends CommandBase {

	{
		name = "clear";
		expectedArgs = new String[0];
	}
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "clear");
	}

	@Override
	public void commandExecute(CommandSource source, String[] args) {
		if (!(source instanceof Player)) {
			source.feedback("'clear' must be executed by a player");
			return;
		}
		Player player = (Player)source;
		Inventory inv = player.getInventory();
		for (int i = 0; i < inv.getCapacity(); i++) {
			if (inv.hasStack(i)) {
				inv.setStack(i, new ItemStack());
			}
		}
	}

}
