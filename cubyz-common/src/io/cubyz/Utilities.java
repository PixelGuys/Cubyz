package io.cubyz;

public class Utilities {

	public static String capitalize(String str) {
		String[] split = str.split(" ");
		StringBuilder sb = new StringBuilder();
		for (int i = 0; i < split.length; i++) {
			String a = split[i];
			char[] ca = a.toCharArray();
			if (ca.length > 0) {
				char c = ca[0];
				c = Character.toUpperCase(c);
				ca[0] = c;
				a = new String(ca);
			}
			
			sb.append(a);
			if (i < split.length-1) {
				sb.append(" ");
			}
		}
		return sb.toString();
	}
	
}
