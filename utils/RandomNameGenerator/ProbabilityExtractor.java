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
		int[] number = new int[27*27*27*27];
		try (BufferedReader br = new BufferedReader(new FileReader("./minerals.txt"))) {
			String line;
			while ((line = br.readLine()) != null) {
				char c1 = ' ', c2 = ' ', c3 = ' ', c4 = ' ';
				for(char c : line.toCharArray()) {
					c1 = c2;
					c2 = c3;
					c3 = c4;
					c4 = c;
					number[getIndex(c1)*27*27*27 + getIndex(c2)*27*27 + getIndex(c3)*27 + getIndex(c4)]++;
				}
				number[getIndex(c2)*27*27*27 + getIndex(c3)*27*27 + getIndex(c4)*27]++;
				number[getIndex(c3)*27*27*27 + getIndex(c4)*27*27]++;
				number[getIndex(c4)*27*27*27]++;
			}
		} catch(Exception e) {}
		DataOutputStream os = new DataOutputStream(new BufferedOutputStream(new FileOutputStream("./custom_ore_names.dat")));
		for(int i = 0; i < 27; i++) {
			for(int j = 0; j < 27; j++) {
				for(int k = 0; k < 27; k++) {
					byte n = 0;
					for(int l = 0; l < 27; l++) { // pre-loop to get the length
						if(number[i*27*27*27 + j*27*27 + k*27 + l] != 0) {
							n++;
						}
					}
					os.writeByte(n);
					for(byte l = 0; l < 27; l++) {
						if(number[i*27*27*27 + j*27*27 + k*27 + l] != 0) {
							os.writeByte(l);
						}
					}
				}
			}
		}
		for(int i = 0; i < 27; i++) {
			for(int j = 0; j < 27; j++) {
				for(int k = 0; k < 27; k++) {
					int total = 0;
					for(int l = 0; l < 27; l++) {
						total += number[i*27*27*27 + j*27*27 + k*27 + l];
					}
					byte n = 0;
					for(int l = 0; l < 27; l++) { // pre-loop to get the length
						if(number[i*27*27*27 + j*27*27 + k*27 + l] != 0) {
							n++;
						}
					}
					os.writeByte(n);
					for(int l = 0; l < 27; l++) {
						if(number[i*27*27*27 + j*27*27 + k*27 + l] != 0) {
							os.writeFloat(number[i*27*27*27 + j*27*27 + k*27 + l]/(float)total);
						}
					}
				}
			}
		}
		os.close();
	}
}
