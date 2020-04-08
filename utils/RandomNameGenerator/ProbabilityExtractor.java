import java.io.*;

// Searches through the mineral names and generates a table of probabilities for every 3 char combination.

public class ProbabilityExtractor {
	static int getIndex(char c) {
		if(c == ' ') return 0;
		if('a' <= c && c <= 'z') return 1+c-'a';
		if('A' <= c && c <= 'Z') return 1+c-'A';
		System.err.println("Unknown \'"+c+"\'"+" "+(int)c);
		System.exit(1);
		return 0;
	}
	static char getChar(int i) {
		if(i == 0) return ' ';
		if(i <= 26) return (char)('a'+i-1);
		System.err.println("Unknown "+i);
		System.exit(1);
		return '0';
	}
	public static void main(String[] args) throws IOException {
		int[] number = new int[27*27*27];
		try (BufferedReader br = new BufferedReader(new FileReader("./minerals.txt"))) {
			String line;
			while ((line = br.readLine()) != null) {
				char c1 = ' ', c2 = ' ', c3 = ' ';
				for(char c : line.toCharArray()) {
					c1 = c2;
					c2 = c3;
					c3 = c;
					number[getIndex(c1)*27*27+getIndex(c2)*27+getIndex(c3)]++;
				}
				number[getIndex(c2)*27*27+getIndex(c3)*27]++;
				number[getIndex(c3)*27*27]++;
			}
		} catch(Exception e) {}
		DataOutputStream os = new DataOutputStream(new BufferedOutputStream(new FileOutputStream("./custom_ore_names.dat")));
		//System.out.print("	public static char[][] chars = {");
		for(int i = 0; i < 27; i++) {
			for(int j = 0; j < 27; j++) {
				//System.out.print("{");
				int n = 0;
				String str = "";
				for(int k = 0; k < 27; k++) {
					if(number[i*27*27 + j*27 + k] != 0) {
						//if(n != 0) System.out.print(",");
						//System.out.print("\'"+getChar(k)+"\'");
						str += getChar(k);
						n++;
					}
				}
				//System.out.print("},");
				os.writeUTF(str);
			}
		}
		//System.out.println("};");
		//System.out.print("	public static float[][] probabilities = {");
		for(int i = 0; i < 27; i++) {
			for(int j = 0; j < 27; j++) {
				//System.out.print("{");
				int total = 0;
				for(int k = 0; k < 27; k++) {
					total += number[i*27*27 + j*27 + k];
				}
				int n = 0;
				for(int k = 0; k < 27; k++) { // pre-loop to get the length
					if(number[i*27*27 + j*27 + k] != 0) {
						//if(n != 0) System.out.print(",");
						n++;
					}
				}
				os.writeInt(n);
				n = 0;
				for(int k = 0; k < 27; k++) {
					if(number[i*27*27 + j*27 + k] != 0) {
						//if(n != 0) System.out.print(",");
						//System.out.print((number[i*27*27 + j*27 + k]/(float)total)+"f");
						os.writeFloat(number[i*27*27 + j*27 + k]/(float)total);
						n++;
					}
				}
				//System.out.print("},");
			}
		}
		//System.out.println("};");
		os.close();
	}
}
