package cubyz.command;

import java.util.Objects;

/**
 * Permission class
 * 
 * @author zenith391
 */

public class Permission {

	int level = 0;
	String name;
	
	public Permission(String name) {
		Objects.requireNonNull(name, "name");
		this.name = name;
		if (name.equals("*")) {
			level = Integer.MAX_VALUE;
		}
	}
	
	public String getPermission() {
		return name;
	}
	
	public boolean isHigherThan(Permission perm) {
		return level > perm.level;
	}
	
	public boolean equals(Object other) {
		if (other instanceof Permission) {
			Permission perm = (Permission) other;
			return level == perm.level && name.equals(perm.name);
		}
		return super.equals(other);
	}
	
}
