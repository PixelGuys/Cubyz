package cubyz.utils.translate;

/**
 * Text key that allows defining order of translational elements.
 */

public class ContextualTextKey extends TextKey {
	TextKey grammar;
	
	protected TextKey[] arguments;
	
	public ContextualTextKey(String grammar, String... args) {
		super(grammar);
		this.grammar = TextKey.createTextKey(grammar);
		arguments = new TextKey[args.length];
		for(int i = 0; i < args.length; i++) {
			arguments[i] = TextKey.createTextKey(args[i]);
		}
	}
	
	@Override
	public String getTranslation() {
		String translation = grammar.getTranslation();
		for (int i = 0; i < arguments.length; i++) {
			translation = translation.replace("{" + i + "}", arguments[i].getTranslation());
		}
		return translation;
	}
	
}
