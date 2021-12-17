package cubyz.utils;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.text.DateFormat;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;

/**
 * A simple Logger, that logs to a file and to the console.
 * Uses ANSI-codes if possible.
 */

public class Logger {
	private static DateFormat format = new SimpleDateFormat("dd/MM/yy HH:mm:ss");
	private static DateFormat logFileFormat = new SimpleDateFormat("YYYY-MM-dd-HH-mm-ss");
	
	private static FileOutputStream latestLogOutput, currentLogOutput;

	private static boolean supportsANSI = System.console() != null && System.getenv().get("TERM") != null;

	static {
		try {
			File logsFolder = new File("logs");
			if (!logsFolder.exists()) {
				logsFolder.mkdirs();
			}
			
			latestLogOutput = new FileOutputStream("logs/latest.log");
			currentLogOutput = new FileOutputStream("logs/" + logFileFormat.format(Calendar.getInstance().getTime()) + ".log");
		} catch (FileNotFoundException e) {
			e.printStackTrace();
		}
	}
	
	
	/**
	 * [{@code time}|debug|{@code thread}] {@code object}
	 * Will be drawn in blue, if possible.
	 * @param object
	 */
	public static void debug(Object object) {
		log("debug", object, "\033[37;44m");
	}
	
	/**
	 * [{@code time}|info|{@code thread}] {@code object}
	 * @param object
	 */
	public static void info(Object object) {
		log("info", object);
	}

	/**
	 * [{@code time}|warning|{@code thread}] {@code object}
	 * Will be drawn in yellow, if possible.
	 * @param object
	 */
	public static void warning(Object object) {
		log("warning", object, "\033[33m");
	}

	/**
	 * [{@code time}|error|{@code thread}] {@code object}
	 * Will be drawn in red, if possible.
	 * @param object
	 */
	public static void error(Object object) {
		log("error", object, "\033[31m");
	}

	/**
	 * [{@code time}|crash|{@code thread}] {@code object}
	 * Will be drawn in bold red, if possible.
	 * @param object
	 */
	public static void crash(Object object) {
		log("crash", object, "\033[1;4;31m");
	}
	
	/**
	 * [{@code time}|{@code prefix}|{@code thread}] {@code object}
	 * @param prefix
	 * @param object
	 */
	public static void log(String prefix, Object object) {
		log(prefix, object, "");
	}
	
	/**
	 * [{@code time}|{@code prefix}|{@code thread}] {@code object}
	 * Uses the ANSI color codes, when available.
	 * If the message is yellow or red, the message will be printed in the error stream.
	 * @param prefix
	 * @param object
	 * @param ANSIColor
	 */
	public static void log(String prefix, Object object, String ANSIColor) {
		Date date = new Date(System.currentTimeMillis());
		StringBuilder sb = new StringBuilder();
		sb.append("[" + format.format(date) + " | " + prefix + " | " + Thread.currentThread().getName() + "] ");
		sb.append(toString(object) + "\n");
	
		
		if (latestLogOutput != null) {
			try {
				latestLogOutput.write(sb.toString().getBytes("UTF-8"));
			} catch (Exception e) {
				throw new Error(e);
			}
		}
		if (currentLogOutput != null) {
			try {
				currentLogOutput.write(sb.toString().getBytes("UTF-8"));
			} catch (Exception e) {
				throw new Error(e);
			}
		}

		ANSIColor = "\033[0m" + ANSIColor;
		if (supportsANSI) sb.insert(0, ANSIColor);

		if (ANSIColor.contains("31") || ANSIColor.contains("33"))
			System.err.print(sb.toString());
		else
			System.out.print(sb.toString());
	}
	
	
	private static String toString(Object object) {
		if (object instanceof Throwable) {

			StringWriter sw = new StringWriter();
			PrintWriter pw = new PrintWriter(sw);
			((Throwable)object).printStackTrace(pw);
			return sw.toString();
		}
		return object.toString();
	}
}
