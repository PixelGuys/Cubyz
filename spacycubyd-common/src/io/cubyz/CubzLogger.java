package io.cubyz;

import java.text.DateFormat;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.logging.Handler;
import java.util.logging.LogRecord;
import java.util.logging.Logger;

public class CubzLogger extends Logger {

	public static boolean useDefaultHandler = false;
	public static CubzLogger i; // instance
	
	static {
		new CubzLogger();
	}
	
	protected CubzLogger() {
		super("Cubz", null);
		setUseParentHandlers(true);
		this.setParent(Logger.getGlobal());
		if (!useDefaultHandler) {
			setUseParentHandlers(false);
			this.addHandler(new Handler() {
				
				DateFormat format = new SimpleDateFormat("EEE, dd/MM/yy HH:mm:ss");
				
				@Override
				public void close() throws SecurityException {
					
				}
	
				@Override
				public void flush() {
					
				}
	
				@Override
				public void publish(LogRecord log) {
					Date date = new Date(log.getMillis());
					
					System.out.print("[" + format.format(date) + " | " + log.getLevel() + "] ");
					System.out.println(log.getMessage());
					System.out.flush();
				}
				
			});
		}
		i = this;
	}

}
