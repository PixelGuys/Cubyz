package io.cubyz.translate;

public class ContextualTextKey extends TextKey {

	protected Object[] args;
	
	public ContextualTextKey(String key, int argc) {
		super(key);
		args = new Object[argc];
	}
	
	public int getArgumentListSize() {
		return args.length;
	}
	
	public void setArgument(int i, Object val) {
		args[i] = val;
	}
	
	@Override
	public String translationOverride(Language lang) {
		if (lang.get(key) != null) {
			String val = lang.get(key);
			for (int i = 0; i < args.length; i++) {
				val = val.replaceAll("{" + i + "}", args[i].toString());
			}
			return val;
		} else {
			return key;
		}
	}
	
}
