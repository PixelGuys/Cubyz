## We do not accept low-effort content suggestions

It is easy to suggest something, but often it's much harder to implement and check if it fits the game.
So, before making a suggestion here on github (you can of course freely discuss ideas on the community discord server), please do the following steps:

- check if it follows the [Game Design Principles](https://github.com/PixelGuys/Cubyz/blob/master/docs/GAME_DESIGN_PRINCIPLES.md)
- make a reference implementation in the form of an addon, mod or fork of Cubyz (no content from other games)
- make sure it follows the requirements listed below, if applicable
- create a pull request with the suggested changes or make an issue using the blank issue template, don't forget to add some screenshots

## Requirements

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

### Structure Building Blocks (SBBs)

- the underground matters, often structures will generate on a slope or above a cave, exposing its underside, so make sure the structure continues underground and contains roots where applicable
- make sure you fill your structures with `cubyz:void` blocks before saving them, unless you actually want it to replace surrounding terrain with air blocks
- for trees and other structures with degradable blocks like leaves and branches, make sure all the blocks are converted to degradable variants using the `/toggledecay` command
- always capture the smallest volume possible, these structures are not cheap
- if your structure appears in bulk, try to split it into multiple randomized parts to avoid clearly visible repetition
- rare fun variants are encouraged (e.g. take inspiration from the bolete mushroom base)
