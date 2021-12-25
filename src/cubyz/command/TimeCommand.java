package cubyz.command;

import cubyz.api.Resource;

import java.util.Objects;

/**
 * Changes the world time.
 */

public class TimeCommand extends CommandBase {

	public TimeCommand() {
		name = "time";
		expectedArgs = new String[1];
		expectedArgs[0] = "<time: time | day | night>";
	}

	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "time");
	}

	@Override
	public void commandExecute(CommandSource source, String[] args) {
		if (args.length == 1) {
			source.feedback(String.valueOf(source.getWorld().getGameTime()));
		} else {
			try {
				if (Objects.equals(args[1], "day")){
					source.getWorld().setGameTime(0); //Set Day Time
				}
				else if (Objects.equals(args[1], "night")) {
					source.getWorld().setGameTime(52000); //Set Night Time
				} else {
					source.getWorld().setGameTime(Integer.parseInt(args[1])); //Parse Input as time
				}
				source.feedback("Time set to " + args[1]);
			} catch (NumberFormatException e) {
				source.feedback(args[1] + " is not an integer between " + Integer.MIN_VALUE + " and " + Integer.MAX_VALUE);
			}
		}
	}

}
