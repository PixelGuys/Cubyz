package io.cubyz;

import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.lang.reflect.Field;
import java.util.HashMap;

public class Utilities {

	public static String capitalize(String str) {
		char[] chars = str.toCharArray();
		for (int i = 0; i < chars.length; i++) {
			if(chars[i] >= 'a' && chars[i] <= 'z') {
				chars[i] += 'A'-'a';
			}
		}
		return new String(chars);
	}
	
	public static String readFile(File file) throws IOException {
		String txt = "";
		FileReader reader = new FileReader(file);
		while (reader.ready()) {
			txt += (char) reader.read();
		}
		reader.close();
		return txt;
	}
	
	public static Object copyIfNull(Object dest, Object value) {
		try {
			Class<?> cl = value.getClass();
			for (Field field : cl.getFields()) {
				Class<?> fcl = field.getType();
				if (fcl.equals(HashMap.class)) {
					if (field.get(dest) != null && field.get(value) != null) {
						HashMap dst = (HashMap) field.get(dest);
						HashMap org = (HashMap) field.get(value);
						for (Object key : org.keySet()) {
							if (!dst.containsKey(key)) {
								dst.put(key, org.get(key));
							} else {
								dst.put(key, Utilities.copyIfNull(dst.get(key), org.get(key)));
							}
						}
					}
				} else {
					if (field.get(dest) == null && field.get(value) != null) {
						field.set(dest, field.get(value));
					}
				}
			}
			return dest;
		} catch (Exception e) {
			e.printStackTrace();
		}
		return null;
	}
	
}
