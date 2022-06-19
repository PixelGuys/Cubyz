package cubyz.command;

import cubyz.api.Resource;
import cubyz.multiplayer.Protocols;
import cubyz.multiplayer.server.User;

/**
 * Clears the inventory of the local player.
 */

public class ClearCommand extends CommandBase {

	{
		name = "/clear";
		expectedArgs = new String[0];
	}
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "clear");
	}

	@Override
	public void commandExecute(CommandSource source, String[] args) {
		if (!(source instanceof User)) {
			source.feedback("'clear' must be executed by a player");
			return;
		}
		User user = (User)source;
		Protocols.GENERIC_UPDATE.clearInventory(user);
	}

}
