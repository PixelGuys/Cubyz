package cubyz.command;

import cubyz.api.Resource;

/**
 * Changes if the world should do the time cycle.
 */

public class GameTimeCycleCommand extends CommandBase {

	public GameTimeCycleCommand() {
		name = "doGameTimeCycle";
		expectedArgs = new String[1];
		expectedArgs[0] = "<Dont know what this is>";
	}
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "doGameTimeCycle");
	}

	@Override
	public void commandExecute(CommandSource source, String[] args) {
		if (args.length == 1) {
			source.feedback(String.valueOf(source.getWorld().shouldDoGameTimeCycle()));
		} else {
			source.getWorld().setGameTimeCycle(Boolean.valueOf(args[1]));
			source.feedback("doGameTimeCycle set to " + args[1]);
		}
	}

}
