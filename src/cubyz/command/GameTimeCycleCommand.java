package cubyz.command;

import cubyz.api.Resource;
import cubyz.multiplayer.server.Server;

/**
 * Changes if the world should do the time cycle.
 */

public class GameTimeCycleCommand extends CommandBase {

	public GameTimeCycleCommand() {
		name = "/doGameTimeCycle";
		expectedArgs = new String[1];
		expectedArgs[0] = "<true/false>";
	}
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "doGameTimeCycle");
	}

	@Override
	public void commandExecute(CommandSource source, String[] args) {
		if (args.length == 1) {
			source.feedback(String.valueOf(Server.world.shouldDoGameTimeCycle()));
		} else {
			Server.world.setGameTimeCycle(Boolean.parseBoolean(args[1]));
			source.feedback("doGameTimeCycle set to " + args[1]);
		}
	}

}
