# Cubyz
Cubyz is a 3D voxel sandbox game(aka minecraft clone).

Cubyz has a bunch of interesting/unique features such as
- level of detail (→ big view distances)
- 3d chunks (→ no height/depth limit)
- procedural crafting (→ you can craft anything you want, and the game will figure out what kind of tool you made)

# About
Cubyz is written in <img src="https://github.com/PixelGuys/Cubyz/assets/43880493/04dc89ca-3ef2-4167-9e1a-e23f25feb67c" width="20" height="20">
[zig](https://ziglang.org/), a rather small language with some cool features and a focus on readability.

Windows and Linux are supported. Mac is not supported because it doesn't have OpenGL 4.3.

Check out the [discord server](https://discord.gg/XtqCRRG) for more information and announcements.

There are also some devlogs on [youtube](https://www.youtube.com/playlist?list=PLYi_o2N3ImLb3SIUpTS_AFPWe0MUTk2Lf).

### History
Until recently(the zig rewrite was started in August 2022) Cubyz was written in java. You can still see the code over on the [cubyz-java](https://github.com/PixelGuys/Cubyz/tree/cubyz-java) branch and play it using the [Java Launcher](https://github.com/PixelGuys/Cubyz-Launcher/releases). `// TODO: Move this over to a separate repository`

Originally Cubyz was created on August 22, 2018 by <img src="https://avatars.githubusercontent.com/u/39484230" width="20" height="20">[zenith391](https://github.com/zenith391) and <img src="https://avatars.githubusercontent.com/u/39484479" width="20" height="20">[ZaUserA](https://github.com/ZaUserA). Back then it was called "Cubz"

However both of them lost interest at some point and now Cubyz is maintained by <img src="https://avatars.githubusercontent.com/u/43880493" width="20" height="20">[IntegratedQuantum](https://github.com/IntegratedQuantum).


# Run Cubyz
Sorry, the zig version isn't there yet. You can test the old java version or ask on the discord server and I may compile a test release for you.

Otherwise you can
### Compile Cubyz from source
1. Install git and zig (latest master release)
2. Clone this repository `git clone --recurse-submodules https://github.com/pixelguys/Cubyz` <br>
If you forgot the `--recurse-submodules` flag you may need to run `git submodule update --init --recursive`
3. Go into the folder `cd Cubyz`
4. Run zig `zig build run`
5. If it's too slow, run it in release: `zig build run -Doptimize=ReleaseFast`

# Contributing
### Code
Try to follow the style of the existing code. `// TODO: Add a style guide` <br>
If you have any more questions, you can ask them over on discord.
### Textures
If you want to add new textures, make sure they fit the style of the game.
If any of the following points are ignored, your texture will be rejected:
1. The size of block and item textures must be 16×16 Pixels.
2. There must be at most 16 different colors in the entire texture.
3. Textures should be shaded with hue shifting instead of darkening only.\
If you are not sure how to use hue shifting, [here](https://www.youtube.com/watch?v=PNtMAxYaGyg) is a good video explaining it.
