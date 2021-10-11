package cubyz.command;

import java.util.ArrayList;
import java.util.List;

import cubyz.api.RegistryElement;

/**
 * Abstract class for all game commands.
 * @author zenith391
 */

public abstract class CommandBase implements RegistryElement {

	protected String name;
	protected String[] expectedArgs;
	protected List<Permission> perms = new ArrayList<>();
	
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

	public Permission[] getRequiredPermissions() {
		return perms.toArray(new Permission[perms.size()]); // convert list to an array
	}
	
}