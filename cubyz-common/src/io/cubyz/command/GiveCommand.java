package io.cubyz.command;

import io.cubyz.api.Registry;
import io.cubyz.api.Resource;
import io.cubyz.entity.Player;
import io.cubyz.items.Inventory;
import io.cubyz.items.Item;

/**
 * Gives a certain item to the local player.
 */

public class GiveCommand extends CommandBase {

	{
		name = "give";
	}
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "give");
	}

	@Override
	public void commandExecute(CommandSource source, String[] args) {
		
		Registry<Item> items = source.getWorld().getCurrentTorus().getCurrentRegistries().itemRegistry;
		if (args.length < 2) {
			source.feedback("Usage: give <item id> [amount]");
			return;
		}
		if (items.getByID(args[1]) == null) {
			source.feedback("No such item: " + args[1]);
			return;
		}
		if (!(source instanceof Player)) {
			source.feedback("'give' must be executed by a player");
			return;
		}
		Player local = source.getWorld().getLocalPlayer();
		Inventory inv = local.getInventory();
		int amount = 1;
		if (args.length > 2) {
			try {
				amount = Integer.parseInt(args[2]);
			} catch (NumberFormatException e) {
				source.feedback("Error: invalid number " + args[2]);
				return;
			}
		}
		inv.addItem(items.getByID(args[1]), amount);
	}
	
}
