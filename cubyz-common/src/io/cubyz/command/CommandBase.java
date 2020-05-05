package io.cubyz.command;

import java.util.ArrayList;
import java.util.List;

import io.cubyz.api.IRegistryElement;

/**
 * Abstract class for all game commands.
 * @author zenith391
 */
public abstract class CommandBase implements IRegistryElement {

	protected String name;
	protected List<Permission> perms = new ArrayList<>();
	
	public abstract void commandExecute(ICommandSource source, String[] args);
	
	@Override
	public void setID(int ID) {
		throw new UnsupportedOperationException();
	}
	
	/**
	 * Returns the name of the Command
	 * @return command name
	 */
	public String getCommandName() {
		return name;
	}
	
	public Permission[] getRequiredPermissions() {
		return perms.toArray(new Permission[perms.size()]); // convert list to an array
	}
	
}