package io.cubyz;

import java.util.HashMap;
import java.util.Map;

import io.cubyz.CubyzLogger;

public class Profiler {
	
	private static long start;
	private static Map<String, Long> profileAverages = new HashMap<String, Long>();
	
	public static void startProfiling() {
		start = System.nanoTime();
	}
	
	public static long getProfileTime() {
		return System.nanoTime() - start;
	}
	
	private static int i;
	
	public static void printProfileTime(String name) {
		CubyzLogger.i.info("Profile \"" + name + "\" took " + getProfileTime() + "ns (" + getProfileTime()/1000000 + "ms)");
		if (!profileAverages.containsKey(name)) {
			profileAverages.put(name, getProfileTime());
		}
		i++;
		profileAverages.put(name, (profileAverages.get(name) + getProfileTime()) / 2);
		if (i % 10 == 0) {
			CubyzLogger.i.info("Average (" + name + "): " + profileAverages.get(name) + "ns (" + profileAverages.get(name)/1000000 + "ms)");
		}
	}
	
}
