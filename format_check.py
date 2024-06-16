import os

import sys

directory = os.fsencode(".")

fails = 0

for subdir, dirs, files in os.walk("."):
	for file in files:
		#print os.path.join(subdir, file)
		filepath = subdir + os.sep + file
		if filepath.startswith("./compiler"): continue
		if filepath.startswith("./saves"): continue
		if filepath.startswith("./serverAssets"): continue
		if filepath.startswith("./zig-cache"): continue
		if filepath.startswith("./.zig-cache"): continue

		if filepath.endswith(".json") or filepath.endswith(".zig") or filepath.endswith(".py") or filepath.endswith(".zon") or filepath.endswith(".vs") or filepath.endswith(".fs") or filepath.endswith(".glsl"):
			with open(filepath, "r", newline = '') as f:
				string = f.read()
				line = 1
				lineStart = True
				for i, c in enumerate(string):
					if(c == '\r'):
						print("Incorrect line ending \\r in file ", filepath, " in line ", line, ". Please configure your editor to use LF instead of CRLF.")
						fails += 1
					elif(c == '\n'):
						line += 1
						lineStart = True
					elif(c == ' '):
						if(lineStart):
							print("Incorrect indentation in file ", filepath, " in line ", line, ". Please use tabs instead of spaces.")
							fails += 1
							lineStart = False # avoid repeating this error multiple times
					elif(c == '\t'):
						continue
					elif(lineStart):
						lineStart = False
					else:
						continue
if(fails != 0):
	sys.exit(1)
sys.exit(0)
