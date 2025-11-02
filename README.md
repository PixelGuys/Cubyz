# Cubyz
Cubyz is a 3D voxel sandbox game (inspired by Minecraft).

Cubyz has a bunch of interesting/unique features such as:
- Level of Detail (→ This enables far view distances.)
- 3D Chunks (→ There is no height or depth limit.)
- Procedural Crafting (→ You can craft anything you want, and the game will figure out what kind of tool you tried to make.)

# About
Cubyz is written in <img src="https://github.com/PixelGuys/Cubyz/assets/43880493/04dc89ca-3ef2-4167-9e1a-e23f25feb67c" width="20" height="20">
[Zig](https://ziglang.org/), a rather small language with some cool features and a focus on readability.

Windows and Linux are supported. Mac is not supported, as it does not have OpenGL 4.3.

Check out the [Discord server](https://discord.gg/XtqCRRG) for more information and announcements.

There are also some devlogs on [YouTube](https://www.youtube.com/playlist?list=PLYi_o2N3ImLb3SIUpTS_AFPWe0MUTk2Lf).

### History
Until recently (the Zig rewrite was started in August 2022) Cubyz was written in Java. You can still see the code in the [Cubyz-Java](https://github.com/PixelGuys/Cubyz-Java) repository and play it using the [Java Launcher](https://github.com/PixelGuys/Cubyz-Launcher/releases). `// TODO: Move this over to a separate repository`

Originally Cubyz was created on August 22, 2018 by <img src="https://avatars.githubusercontent.com/u/39484230" width="20" height="20">[zenith391](https://github.com/zenith391) and <img src="https://avatars.githubusercontent.com/u/39484479" width="20" height="20">[ZaUserA](https://github.com/ZaUserA). Back then, it was called "Cubz".

However, both of them lost interest at some point, and now Cubyz is maintained by <img src="https://avatars.githubusercontent.com/u/43880493" width="20" height="20">[IntegratedQuantum](https://github.com/IntegratedQuantum).


# Run Cubyz
### This section is about compiling a dev version, if you just want a precompiled version, go to [releases](https://github.com/PixelGuys/Cubyz/releases)
## The Easy Way (no tools needed)
1. Download the latest [source code](https://codeload.github.com/PixelGuys/Cubyz/zip/refs/heads/master)
2. Extract the zip file
3. Go into the extraced folder and double click the `run_linux.sh` or `run_windows.bat` depending on your operating system.
4. Congratulations: You just compiled your first program!

### It doesn't work?
- If it doesn't work and keeps running for more than 10 minutes without doing anything it can help to kill and restart the process. A few people seem to experience this, and I have not found the cause. It might also help to delete the `zig-cache` folder.
- If you see an error message in the terminal, please report it in the [Issues](https://github.com/PixelGuys/Cubyz/issues) tab or on the [Discord server](https://discord.gg/XtqCRRG).
- Otherwise you can always ask for help on the Discord server. If you are unable to get it compiling on your machine, you can also ask on the Discord server and we may compile a release for you.

## The Better Way
1. Install Git
2. Clone this repository `git clone https://github.com/pixelguys/Cubyz`
3. Run `run_linux.sh` or `run_windows.bat`, if you already have Zig installed on your computer (it must be a compatible version) you can also just use `zig build run`
4. When you want to update your local version you can use `git pull`. This keeps everything in one place, avoiding repeatedly downloading the compiler on every update.

# Contributing
### Code
Check out the [Contributing Guidelines](https://github.com/PixelGuys/Cubyz/blob/master/docs/CONTRIBUTING.md)

### Gameplay Additions
Check out the [Game Design Principles](https://github.com/PixelGuys/Cubyz/blob/master/docs/GAME_DESIGN_PRINCIPLES.md)

### Textures
If you want to add new textures, make sure they fit the style of the game. It's recommended that you have baseline skills in pixel art before attempting to make textures. A great collection of tutorials can be found [here](https://lospec.com/pixel-art-tutorials)

If any of the following points are ignored, your texture will be rejected:
1. Resolution is 16 x 16
2. Lighting direction is top-left for items and blocks.
3. Keep colour palettes small. Do not use near-duplicate colours, do not use noise, filters, or brushes that create unnecessary amounts of colours. Most blocks can be textured with ~4-6 colours.
4. Reference other block textures to see how colours & contrast is used. Test your textures ingame alongside other blocks.
5. Blocks should tile smoothly. Avoid creating seams or repetitive patterns.
6. Use hue shifting conservatively. Take the material into account when choosing colours.
7. Items have full, coloured, 1-pixel outlines. It should be shaded so that the side in light (top left) is brighter, while the side in shadow (bottom right) is darker.
8. Items should have higher contrast than their block counterparts.

Your texture may be edited or replaced to ensure a consistent art style throughout the game.

For further information, ask <img src="https://avatars.githubusercontent.com/u/122191047" width="20" height="20">[careeoki](https://github.com/careeoki) on [Discord](https://discord.gg/XtqCRRG). She has made a majority of the art for Cubyz.
