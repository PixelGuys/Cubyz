import java.io.BufferedInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.lang.ProcessBuilder.Redirect;
import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * A simple utility that handles packaging the game and it's assets, so it's easier to publish them on github.
 * It also does some code optimizations:
 * - remove assert statements (they can prevent inlining when left in the code)
 */
public class PackageForRelease {
	public static void zipDir(File folder, File zip) throws Exception {
		try (ZipOutputStream zipOutputStream = new ZipOutputStream(Files.newOutputStream(zip.toPath()))) {
			if (Files.isDirectory(folder.toPath())) {
				Files.walk(folder.toPath()).filter(path -> !Files.isDirectory(path)).forEach(path -> {
					ZipEntry zipEntry = new ZipEntry(folder.toPath().relativize(path).toString());
					try {
						zipOutputStream.putNextEntry(zipEntry);
						if (Files.isRegularFile(path)) {
							Files.copy(path, zipOutputStream);
						}
						zipOutputStream.closeEntry();
					} catch (Exception e) {
						e.printStackTrace();
					}
				});
			}
		}
	}

	public static void copy(Path source, Path dest) throws Exception {
		Files.copy(source, dest);
	}

	public static String filterAssertion(String text) {
		char[] array = text.toCharArray();
		char[] result = new char[array.length];
		// Assertions start with a single "assert" keyword that's outside a string or variable name.
		// Assertions may contain pieces of code that may contain semicolons.
		// Assertions end with a semicolon.
		boolean isString = false;
		boolean isAssert = false;
		int curlyBracketDepth = 0;
		int normalBracketDepth = 0;
		int squareBracketDepth = 0;
		int curlyBracketDepthOfLastAssert = -1;
		int normalBracketDepthOfLastAssert = -1;
		int squareBracketDepthOfLastAssert = -1;
		int resultSize = 0;
		for(int i = 0; i < array.length; i++) {
			switch(array[i]) {
				case '"':
					isString = !isString;
					break;
				case '{':
					if(!isString)
						curlyBracketDepth++;
					break;
				case '(':
					if(!isString)
						normalBracketDepth++;
					break;
				case '[':
					if(!isString)
						squareBracketDepth++;
					break;
				case '}':
					if(!isString)
						curlyBracketDepth--;
					break;
				case ')':
					if(!isString)
						normalBracketDepth--;
					break;
				case ']':
					if(!isString)
						squareBracketDepth--;
					break;
				case 'a':
					// Start the assertion:
					if((i == 0 || !Character.isAlphabetic(array[i-1])) // Make sure the assert isn't in the middle of a variable or function name.
					    && array[i+1] == 's'
					    && array[i+2] == 's'
					    && array[i+3] == 'e'
					    && array[i+4] == 'r'
					    && array[i+5] == 't'
					    && !Character.isAlphabetic(array[i+6])) { // Make sure the assert isn't in the middle of a variable or function name.

						if(!isString && !isAssert) {
							isAssert = true;
							curlyBracketDepthOfLastAssert = curlyBracketDepth;
							normalBracketDepthOfLastAssert = normalBracketDepth;
							squareBracketDepthOfLastAssert = squareBracketDepth;
						}
					}
					break;
				case ';':
					if(isAssert) {
						if(curlyBracketDepthOfLastAssert == curlyBracketDepth
						   && normalBracketDepthOfLastAssert == normalBracketDepth
						   && squareBracketDepthOfLastAssert == squareBracketDepth) {

							isAssert = false;
							continue;
						}
					}
					break;
				default:
					break;
			}
			if(!isAssert)
				result[resultSize++] = array[i];
		}
		return new String(result, 0, resultSize);
	}

	public static void copyAndRemoveAssertions(File src, File destSrc) throws Exception {
		if (Files.isDirectory(src.toPath())) {
			Files.walk(src.toPath()).filter(path -> !Files.isDirectory(path)).forEach(path -> {
				try {
					String text = Files.readString(path);
					text = filterAssertion(text);

					Path outPath = destSrc.toPath().resolve(src.toPath().relativize(path));
					Files.createDirectories(outPath.getParent());
					Files.writeString(outPath, text);
				} catch (Exception e) {
					e.printStackTrace();
				}
			});
		}
	}
	
	public static void deleteDir(File file) {
		File[] contents = file.listFiles();
		if (contents != null) {
			for (File f : contents) {
				deleteDir(f);
			}
		}
		file.delete();
	}

	public static void mavenCompilePackage(File dir) throws Exception {
		ProcessBuilder pb = new ProcessBuilder("mvn", "compile", "package");
		pb.directory(dir);
		pb.redirectOutput(Redirect.INHERIT);
		Process p = pb.start();
		p.waitFor();
	}

	public static void main(String[] args) throws Exception {
		File output = new File("release");
		deleteDir(output);
		output.mkdirs();
		zipDir(new File("assets"), new File("release/assets.zip"));
		copy(Path.of("pom.xml"), Path.of("release/pom.xml"));
		copyAndRemoveAssertions(new File("src"), new File("release/src")); // Removes assertions from release code because they may cause performance problems.
		mavenCompilePackage(output);
		copy(Path.of("release/target/Cubyz.jar"), Path.of("release/Cubyz.jar"));
	}
}
