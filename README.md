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
Until recently (the Zig rewrite was started in August 2022) Cubyz was written in Java. You can still see the code over on the [cubyz-java](https://github.com/PixelGuys/Cubyz/tree/cubyz-java) branch and play it using the [Java Launcher](https://github.com/PixelGuys/Cubyz-Launcher/releases). `// TODO: Move this over to a separate repository`

Originally Cubyz was created on August 22, 2018 by <img src="https://avatars.githubusercontent.com/u/39484230" width="20" height="20">[zenith391](https://github.com/zenith391) and <img src="https://avatars.githubusercontent.com/u/39484479" width="20" height="20">[ZaUserA](https://github.com/ZaUserA). Back then, it was called "Cubz".

However, both of them lost interest at some point, and now Cubyz is maintained by <img src="https://avatars.githubusercontent.com/u/43880493" width="20" height="20">[IntegratedQuantum](https://github.com/IntegratedQuantum).


# Run Cubyz
Sorry, the zig version isn't there yet. You can test the old Java version or ask on the Discord server and I may compile a test release for you.

Otherwise, you can do the following:
### Compile Cubyz from Source
1. Install Git
2. Clone this repository `git clone https://github.com/pixelguys/Cubyz`
3. Run `run_release.sh` (Linux) or `run_release.bat` (Windows)
#### Note for Linux Users:
I also had to install a few `-dev` packages for the compilation to work:
```
sudo apt install libgl-dev libasound2-dev libx11-dev libxcursor-dev libxrandr-dev libxinerama-dev libxext-dev libxi-dev
```

# Contributing
### Code
Try to follow the style of the existing code. `// TODO: Add a style guide` <br>
If you have any more questions, you can ask them over on [Discord](https://discord.gg/XtqCRRG).
### Textures
If you want to add new textures, make sure they fit the style of the game.
If any of the following points are ignored, your texture will be rejected:
1. The size of block and item textures must be 16×16 Pixels.
2. There must be at most 16 different colors in the entire texture.
3. Textures should be shaded with hue shifting, rather than with darkening only.\
If you are not sure how to use hue shifting, [here](https://www.youtube.com/watch?v=PNtMAxYaGyg&t=11) is a video that explains it well.
