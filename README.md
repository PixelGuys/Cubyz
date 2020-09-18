[![Java](https://img.shields.io/badge/language-java-orange.svg?style=flat
)](https://java.com)
[![License](https://img.shields.io/badge/license-bsd3-blue.svg?style=flat
)](https://github.com/PixelGuys/Cubz/blob/master/LICENSE)
# Cubyz
Cubyz is a sandbox 3D voxel video game. It offers a native mod API and is different to most other voxel games due to the fact that it uses procedural content generation to make every single world unique many some ways(including ores, materials and tools).

Cubyz can easily be forked to create a new game with 3D sandbox aspect.

# Run Cubyz
## Run latest release:
1. Install [java 8](https://www.oracle.com/Java/technologies/Javase-jre8-downloads.html) or later.
2. Download the latest release(for your OS) from https://zenith391.itch.io/cubyz
3. unzip it somewhere and double-click the jar.
## Compile from source:
Cubyz is tested to compile and run with maven and eclipse.
### maven
0. Install `git` and `maven`.
1. Clone Cubyz from github:
- Either run `git clone https://github.com/PixelGuys/Cubyz`
- Or [download](https://github.com/PixelGuys/Cubyz/archive/master.zip) and unzip Cubyz master branch from github.
2. `cd` to the directory you want to compile(Cubyz/cubyz-client or Cubyz/cubyz-server).
3. Run `mvn clean compile` to compile Cubyz.
4. Run `mvn exec:java` to run Cubyz after compilation.
### eclipse
1. Install and open eclipse.
2. Import the project from github:
- Select(in the menu bar) File/import/Git/"Projects from Git"
- Select clone URI
- Copy `https://github.com/PixelGuys/Cubyz` into the field URI
- Press next a couple times and maybe choose a custom Destination Directory.
3. Wait some time for eclipse to download the project. If the source code shows any errors try refreshing the project(right click on project, refresh).
4. Run `GameLauncher` in `cubyz-client` to start the game.
## Requirements
Windows:

Type | Minimum | Recommended
-----|---------|------------
OS | Windows XP | Windows 7 or later
RAM | 3 GB | 4 GB or more
GPU | Any OpenGL 3.0 compatible | OpenGL 3.3+

Linux based / Mac:

Type | Minimum | Recommended
-----|---------|------------
RAM | 2 GB | 4 GB or more
GPU | Any OpenGL 3.0 compatible | OpenGL 3.3+

Those recommendations are system wide and required for Cubyz.

The exception is RAM, as Cubyz RAM usage varies. When gave little memory (256MB or less), due to how the GC works it will
get executed more often.
Meaning Cubyz won't crash for Out of Memory, but will have slow down due to GC pauses (unlikely to be visible with some GCs).
However with more memory the GC will make less pauses, and be trickier to free heap. Which will result in Cubyz having allocated
~900/1024MB but actually using 400/1024MB when shown in the debug menu.

Basically for the end user, this means Cubyz requires **minimum** around **128MB** of free RAM.
And is best played (**recommended**) with around **512MB** of free RAM.

## About
- [Cristea Andrei Flavian](https://github.com/CristeaAndreiFlavian), [zenith391](https://github.com/zenith391) and [IntegratedQuantum](https://github.com/IntegratedQuantum) who all contributed to the game and made everything possible!
- The development started on August 22, 2018. Cubyz is already over 1 year old!
- Cubyz has [Jungle Engine](https://github.com/zenith391/Jungle-Engine) under the hood!
- This game is under BSD-3-Clause license for more details please check the [LICENSE](https://github.com/PixelGuys/Cubz/blob/master/LICENSE) file.
- You can receive announcements about Cubyz on our [discord](https://discord.gg/XtqCRRG) server.

### Donations
If you'd like to donate, first thank you, second, it will only serve for servers and some other things. And third, here if you really want, the [donation link](https://www.paypal.me/thxforthedonationbud)
