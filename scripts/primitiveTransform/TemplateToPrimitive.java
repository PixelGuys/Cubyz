import java.io.BufferedReader;
import java.io.FileReader;
import java.io.BufferedWriter;
import java.io.FileWriter;
import java.nio.file.Paths;
import java.nio.file.Path;

/**
 * Used to transform classes that need templates for usage with primitives instead.
 * Usage:
 * java TemplateToPrimitive <source code of the class> <name of primitive type>
 * Output: ./<Primitive><filename> (class name will be automatically renamed!)
 * This is a really limited implementation. It won't work in many cases.
 * This program was designed for converting the FastList to primitive types and should work for it with only smaller problems.
 */
public class TemplateToPrimitive {
	public static void main(String[] args) {
		if (args.length < 2) {
			System.out.println("Usage: \njava TemplateToPrimitive <file> <primitive>");
			System.exit(1);
		}
		String primitive = args[1];
		String file = "";
		try (BufferedReader br = new BufferedReader(new FileReader(args[0]))) {
			String line;
			while ((line = br.readLine()) != null) {
				file += line+"\n";
			}
		} catch(Exception e) {}
		file = file.replace("<>", "");
		file = file.replace("<T>", "");
		file = file.replace("(T)", "");
		file = file.replace("T ", primitive+" ");
		file = file.replace("T[", primitive+"[");
        Path path = Paths.get(args[0]); 
        // Get filename and remove extension to get class name:
        String className = path.getFileName().toString().replaceFirst("[.][^.]+$", "");
        String newClassName = primitive.substring(0, 1).toUpperCase() + primitive.substring(1) + className;
        file = file.replace(className, newClassName);
        file = removeAnnoyingStuff(file, primitive);
		try {
			BufferedWriter writer = new BufferedWriter(new FileWriter("./"+newClassName+".java"));
			writer.write(file);
			writer.close();
		} catch(Exception e) {}
	}
	
	// Hardcoded one specific function of the FastList.
	public static String removeAnnoyingStuff(String file, String primitive) {
		while (file.contains("Array.newInstance(")) {
			int index = file.indexOf("Array.newInstance(");
			int depth = 0;
			boolean through = false;
			boolean inRegion = false;
			char[] chars = file.toCharArray();
			file = file.substring(0, index);
			file += "new "+primitive+"[";
			for(int i = index; i < chars.length; i++) {
				if (through) {
					file += chars[i];
				} else {
					if (chars[i] == ')') {
						depth--;
						if (depth == 0) {
							file += "]";
							through = true;
							inRegion = false;
						}
					}
					if (inRegion) {
						file += chars[i];
					}
					if (chars[i] == '(') {
						depth++;
					} else if (chars[i] == ',' && depth == 1) {
						inRegion = true;
					}
				}
			}
		}
		return file;
	}
}
