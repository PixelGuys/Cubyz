package io.cubyz;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.text.DateFormat;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;
import java.util.logging.Handler;
import java.util.logging.Level;
import java.util.logging.LogRecord;
import java.util.logging.Logger;

public class CubyzLogger extends Logger {

	public static boolean useDefaultHandler = false;
	/**
	 * Same as <code>instance</code>
	 */
	public static CubyzLogger i; // instance
	public static CubyzLogger instance;
	
	static {
		new CubyzLogger();
	}
	
	protected CubyzLogger() {
		super("Cubz", null);
		setUseParentHandlers(true);
		this.setParent(Logger.getGlobal());
		this.setLevel(Level.ALL);
		this.setFilter(null);
		
		File logs = new File("logs");
		if (!logs.exists()) {
			logs.mkdir();
		}
		if (!useDefaultHandler) {
			setUseParentHandlers(false);
			this.addHandler(new Handler() {
				
				DateFormat format = new SimpleDateFormat("EEE, dd/MM/yy HH:mm:ss");
				DateFormat logFormat = new SimpleDateFormat("YYYY-MM-dd-HH-mm-ss");
				
				FileOutputStream latestLogOutput;
				
				{
					try {
						latestLogOutput = new FileOutputStream("logs/latest.log");
					} catch (Exception e) {
						e.printStackTrace();
					}
				}
				
				@Override
				public void close() throws SecurityException {
					try {
						if (latestLogOutput != null)
							latestLogOutput.close();
						Files.copy(Paths.get("logs/latest.log"), Paths.get("logs/" + logFormat.format(Calendar.getInstance().getTime()) + ".log"));
						latestLogOutput = null;
					} catch (Exception e) {
						System.err.println(e);
						throw new SecurityException(e);
					}
				}
	
				@Override
				public void flush() {
					System.out.flush();
					try {
						if (latestLogOutput != null) {
							latestLogOutput.flush();
						}
					} catch (Exception e) {
						throwing("CubzLogger", "flush", e);
					}
				}
	
				@Override
				public void publish(LogRecord log) {
					Date date = new Date(log.getMillis());
					
					StringBuilder sb = new StringBuilder();
					
					sb.append("[" + format.format(date) + " | " + log.getLevel() + "] ");
					sb.append(log.getMessage() + "\n");
					
					System.out.print(sb.toString());
					
					if (latestLogOutput != null) {
						try {
							latestLogOutput.write(sb.toString().getBytes("UTF-8"));
						} catch (Exception e) {
							throw new Error(e);
						}
					}
				}
				
			});
		}
		instance = this;
		i = this;
	}

}
