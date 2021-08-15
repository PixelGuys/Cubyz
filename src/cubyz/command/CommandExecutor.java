package cubyz.command;

import cubyz.api.CubyzRegistries;
import cubyz.api.Registry;

public class CommandExecutor {

	public static void execute(String cmd, CommandSource source) {
		Registry<CommandBase> commandRegistry = CubyzRegistries.COMMAND_REGISTRY;
		String[] split = cmd.split("(\\s)+");
		if (split.length < 1) {
			return;
		}
		String name = split[0];
		
		if (name.equals("?")) {
			source.feedback("Command list:");
			for (CommandBase base : commandRegistry.registered(new CommandBase[0])) {
				source.feedback(base.name);
			}
			return;
		}
		
		for (CommandBase base : commandRegistry.registered(new CommandBase[0])) {
			if (base.name.equals(name)) {
				base.commandExecute(source, split);
				return;
			}
		}
		source.feedback("Invalid command: " + name);
	}
	
}
