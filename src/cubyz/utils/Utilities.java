package cubyz.utils;

import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.lang.reflect.Field;
import java.util.HashMap;

/**
 * Contains functions that don't really fit anywhere else.
 */

public class Utilities {

	public static String capitalize(String str) {
		char[] chars = str.toCharArray();
		for (int i = 0; i < chars.length; i++) {
			if ((i == 0 || chars[i - 1] == ' ') && chars[i] >= 'a' && chars[i] <= 'z') {
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
	
	public static void writeFile(File file, String content) throws IOException {
		file.getParentFile().mkdirs();
		FileWriter writer = new FileWriter(file);
		writer.write(content);
		writer.close();
	}

	@SuppressWarnings({ "rawtypes", "unchecked" })
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
			Logger.error(e);
		}
		return null;
	}
	
	// A simple hash function. I don't want to use String.hashCode() because it could create compatibility issues with future versions of java.
	// Uses jenkins hash function.
	public static long hash(String input) {
		long hash = input.length();
		for(int i = 0; i < input.length(); i++) {
			hash += input.charAt(i);
			hash += hash << 10;
			hash ^= hash >> 6;
		}
		hash += hash << 3;
		hash ^= hash >> 11;
		return hash + (hash << 15);
	}

	// Doesn't do any range checks. Do not give it empty arrays!
	public static void fillArray(Object[] array, Object value) {
		int len = array.length;
		array[0] = value;
		for (int i = 1; i < len; i <<= 1) {
			System.arraycopy(array, 0, array, i, ((len - i) < i) ? (len - i) : i);
		}
	}
	// Doesn't do any range checks. Do not give it empty arrays!
	public static void fillArray(int[] array, int value) {
		int len = array.length;
		array[0] = value;
		for (int i = 1; i < len; i <<= 1) {
			System.arraycopy(array, 0, array, i, ((len - i) < i) ? (len - i) : i);
		}
	}
}
