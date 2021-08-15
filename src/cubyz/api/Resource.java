package cubyz.api;

/**
 * Resource IDs are used for registering. The general recommended format is "mod:name".
 */

public class Resource {

	public static final Resource EMPTY = new Resource("empty:empty");
	private String mod;
	private String identifier;
	
	public Resource(String mod, String identifier) {
		this.mod = mod;
		this.identifier = identifier;
	}
	
	public Resource(String text) {
		if (text.contains(":")) { // not containing separator
			String[] split = text.split(":", 2);
			mod = split[0];
			identifier = split[1];
		} else {
			throw new IllegalArgumentException("text (" + text + ")");
		}
	}
	
	public boolean equals(Object o) {
		if (o instanceof Resource) {
			Resource r = (Resource) o;
			return r.getID().equals(identifier) && r.getMod().equals(mod);
		}
		return false;
	}
	
	public int hashCode() {
		return mod.hashCode() + identifier.hashCode();
	}
	
	public String getMod() {
		return mod;
	}
	
	public String getID() {
		return identifier;
	}
	
	public String toString() {
		return mod + ":" + identifier;
	}
	
}
