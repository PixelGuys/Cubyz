package cubyz.command;

import cubyz.api.RegistryElement;

/**
 * Abstract class for all game commands.
 * @author zenith391
 */

public abstract class CommandBase implements RegistryElement {

	protected String name;
	protected String[] expectedArgs;
	
	public abstract void commandExecute(CommandSource source, String[] args);
	
	/**
	 * Returns the name of the Command
	 * @return command name
	 */
	public String getCommandName() {
		return name;
	}

	public String[] getExpectedArgs() {
		return expectedArgs;
	}
	
}