package io.spacycubyd.command;

import java.util.Objects;
import java.util.function.BiConsumer;

public class CommandBuilder {

	private String name;
	private BiConsumer<ICommandSource, String[]> executor;
	
	public static CommandBuilder newBuilder() {
		return new CommandBuilder();
	}
	
	public CommandBuilder() {}
	
	public CommandBuilder setName(String name) {
		Objects.requireNonNull(name, "name");
		this.name = name;
		return this;
	}
	
	public CommandBuilder setExecutor(BiConsumer<ICommandSource, String[]> executor) {
		this.executor = executor;
		return this;
	}
	
	public CommandBase build() {
		Objects.requireNonNull(name, "command name");
		CommandBase base = new CommandBase() {

			@Override
			public void commandExecute(ICommandSource source, String[] args) {
				if (executor != null) {
					executor.accept(source, args);
				}
			}
			
		};
		base.name = name;
		return base;
	}
	
}
