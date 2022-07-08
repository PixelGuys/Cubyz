package cubyz.command;

import cubyz.api.Registry;
import cubyz.api.Resource;
import cubyz.multiplayer.Protocols;
import cubyz.multiplayer.server.Server;
import cubyz.multiplayer.server.User;
import cubyz.world.items.Item;
import cubyz.world.items.ItemStack;

/**
 * Gives a certain item to the local player.
 */

public class GiveCommand extends CommandBase {

	{
		name = "/give";
		expectedArgs = new String[2];
		expectedArgs[0] = "<item id>";
		expectedArgs[1] = "<optional: amount>";
	}
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "give");
	}

	@Override
	public void commandExecute(CommandSource source, String[] args) {
		
		Registry<Item> items = Server.world.getCurrentRegistries().itemRegistry;
		if (args.length < 2) {
			source.feedback("Usage: give <item id> [amount]");
			return;
		}
		// Append the game id in the begging if the source doesn't supply the game id
		if (!args[1].contains(":")) {
			args[1] = "cubyz:".concat(args[1]);
		}
		if (items.getByID(args[1]) == null) {
			source.feedback("No such item: " + args[1]);
			return;
		}
		if (!(source instanceof User)) {
			source.feedback("'give' must be executed by a player");
			return;
		}
		User user = (User)source;
		int amount = 1;
		if (args.length > 2) {
			try {
				amount = Integer.parseInt(args[2]);
			} catch (NumberFormatException e) {
				source.feedback("Error: invalid number " + args[2]);
				return;
			}
		}
		ItemStack stack = new ItemStack(items.getByID(args[1]), amount);
		Protocols.GENERIC_UPDATE.itemStackCollect(user, stack);
	}
	
}
