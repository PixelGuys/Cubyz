[![Java](https://img.shields.io/badge/language-java-orange.svg?style=flat
)](https://www.oracle.com/java/technologies/javase-downloads.html)
[![License](https://img.shields.io/badge/license-GPLv3-blue.svg?style=flat
)](https://github.com/PixelGuys/Cubyz/blob/master/LICENSE)
# Cubyz
Cubyz is a sandbox 3D voxel video game(aka minecraft clone). It is different to most other voxel games because it uses procedural content generation to make every single world unique in many ways(including ores, materials and tools).

Cubyz can easily be forked or modded to create a new game with 3D sandbox aspect.

## About
### Developers
- <img src="https://avatars.githubusercontent.com/u/39484479" width="20" height="20">[ZaUserA](https://github.com/ZaUserA)
- <img src="https://avatars.githubusercontent.com/u/39484230" width="20" height="20">[zenith391](https://github.com/zenith391)
- <img src="https://avatars.githubusercontent.com/u/43880493" width="20" height="20">[IntegratedQuantum](https://github.com/IntegratedQuantum)
- <img src="https://avatars.githubusercontent.com/u/26800463" width="20" height="20">[tillpp](https://github.com/tillpp)
### other Contributors
- <img src="https://avatars.githubusercontent.com/u/32070620" width="20" height="20">[evegit](https://github.com/evelithgit) - translation to spanisch
- <img src="https://avatars.githubusercontent.com/u/66124969" width="20" height="20">[D I O](https://github.com/AverageCompHead) - graphics
- Shakalacka - graphics
### The game
- The development started on August 22, 2018. Back then it was called "Cubz".
- Cubyz runs on lwjgl and uses its own voxel engine.
- This game is under GPLv3 license for more details check the [LICENSE](https://github.com/PixelGuys/Cubz/blob/master/LICENSE) file.
- You can receive announcements about Cubyz on our [discord](https://discord.gg/XtqCRRG) server.

# Run Cubyz
## Run latest release:
1. Install [java 14 or higher](https://www.oracle.com/java/technologies/javase-downloads.html).
2. Download the latest release from https://zenith391.itch.io/cubyz
3. double-click the jar.
## Compile from source:
Cubyz is tested to compile and run with maven and eclipse.
### maven
0. Install `git` and `maven`.
1. Clone Cubyz from github:
- Either run `git clone https://github.com/PixelGuys/Cubyz`
- Or [download](https://github.com/PixelGuys/Cubyz/archive/master.zip) and unzip Cubyz master branch from github.
2. Go into the directory: `cd Cubyz`
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
4. Run `Main` to start the game.
## Requirements
Vary a lot depending on your render distance.
All you need is a computer that runs java.

# Contributing
## Textures
If you want to add new textures, make sure they fit the style of the game.
If any of the following points are ignored, your texture will be rejected:
1. The size of block and item textures must be 16×16 Pixels.
2. There must be at most 16 different colors in the entire texture.
3. Textures should be shaded with hue shifting instead of darkening only.\
If you are not sure how to use hue shifting, [here](https://www.youtube.com/watch?v=PNtMAxYaGyg) is a good video explaining it.
