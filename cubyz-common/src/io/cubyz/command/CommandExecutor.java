package io.cubyz.command;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.RegistryElement;
import io.cubyz.api.Registry;

public class CommandExecutor {

	public static void execute(String cmd, ICommandSource source) {
		Registry<CommandBase> commandRegistry = CubyzRegistries.COMMAND_REGISTRY;
		String[] split = cmd.split(" ");
		if (split.length < 1) {
			return;
		}
		String name = split[0];
		
		if (name.equals("?")) {
			source.feedback("Command list:");
			for (RegistryElement elem : commandRegistry.registered()) {
				CommandBase base = (CommandBase) elem;
				source.feedback(base.name);
			}
			return;
		}
		
		for (RegistryElement elem : commandRegistry.registered()) {
			CommandBase base = (CommandBase) elem;
			if (base.name.equals(name)) {
				base.commandExecute(source, split);
				return;
			}
		}
		source.feedback("Invalid command: " + name);
	}
	
}
