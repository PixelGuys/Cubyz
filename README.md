[![Java](https://img.shields.io/badge/language-java-orange.svg?style=flat
)](https://java.com)
[![License](https://img.shields.io/badge/license-bsd3-blue.svg?style=flat
)](https://github.com/PixelGuys/Cubz/blob/master/LICENSE)
# Cubyz
Cubyz is a sandbox 3D voxel video game. It offers a native mod API and is currently half experiment to train with LWJGL 3 and Java, half video game with potential.

Cubyz can easily be forked to create a new game with 3D sandbox aspect.
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
- The development started on August 22, 2018. Cubyz is already 1 year old!
- Cubyz haves [Jungle Engine](https://github.com/zenith391/Jungle-Engine) under the hood!
- This game is under BSD-3-Clause license for more details please check the [LICENSE](https://github.com/PixelGuys/Cubz/blob/master/LICENSE) file.
- You can receive announcements about Cubyz on [discord](https://discord.gg/XtqCRRG) server.

### Donations
If you'd like to donate, first thanks you, second, it will only serve for servers and some other things. And third, here if you really want, the [donation link](https://www.paypal.me/thxforthedonationbud)
