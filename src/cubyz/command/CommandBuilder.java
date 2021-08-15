package cubyz.command;

import java.util.Objects;
import java.util.function.BiConsumer;

import cubyz.api.Resource;

public class CommandBuilder {

	private String name;
	private BiConsumer<CommandSource, String[]> executor;
	
	public static CommandBuilder newBuilder() {
		return new CommandBuilder();
	}
	
	public CommandBuilder() {}
	
	public CommandBuilder setName(String name) {
		Objects.requireNonNull(name, "name");
		this.name = name;
		return this;
	}
	
	public CommandBuilder setExecutor(BiConsumer<CommandSource, String[]> executor) {
		this.executor = executor;
		return this;
	}
	
	public CommandBase build(Resource id) {
		Objects.requireNonNull(name, "command name");
		CommandBase base = new CommandBase() {

			@Override
			public void commandExecute(CommandSource source, String[] args) {
				if (executor != null) {
					executor.accept(source, args);
				}
			}

			@Override
			public Resource getRegistryID() {
				return id;
			}
		};
		base.name = name;
		return base;
	}
	
}
