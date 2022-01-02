package cubyz.utils;

import java.io.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;

public class Zipper {
	public static void pack(String sourceDirPath, OutputStream outputstream){
		try (ZipOutputStream zipoutput = new ZipOutputStream(outputstream)) {
			Path path = Paths.get(sourceDirPath);
			Files.walk(path)
					.filter(p -> !Files.isDirectory(p)) // potential bug
					.forEach(p -> {
						ZipEntry zipEntry = new ZipEntry(path.relativize(p).toString());
						try {
							zipoutput.putNextEntry(zipEntry);
							Files.copy(p, zipoutput);
							zipoutput.closeEntry();
						} catch (IOException e) {
							Logger.error(e);
						}
					});
		}catch(IOException exception){
			Logger.error(exception);
		}
	}
	public static void unpack(String outputFolderPath, InputStream inputStream){
		try {
			File outputFolder = new File(outputFolderPath);
			if (!outputFolder.exists()) {
				outputFolder.mkdir();
			}
			ZipInputStream zipIn = new ZipInputStream(inputStream);
			ZipEntry entry = zipIn.getNextEntry();
			// iterates over entries in the zip file
			while (entry != null) {
				String filePath = outputFolder.getAbsolutePath() + File.separator + entry.getName();
				if (!entry.isDirectory()) {
					// if the entry is a file, extract it
					new File(filePath).getParentFile().mkdirs();
					BufferedOutputStream bos = new BufferedOutputStream(new FileOutputStream(filePath));
					byte[] bytesIn = new byte[4096];
					int read = 0;
					while ((read = zipIn.read(bytesIn)) != -1) {
						bos.write(bytesIn, 0, read);
					}
					bos.close();
				} else {
					// if the entry is a directory, make the directory
					File dir = new File(filePath);
					dir.mkdirs();
				}
				zipIn.closeEntry();
				entry = zipIn.getNextEntry();
			}
			zipIn.close();
		}catch (Exception e){
			Logger.error(e);
		}
	}
}
