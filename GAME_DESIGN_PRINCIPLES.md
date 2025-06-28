# Game Design Principles
This document is intended for contributors and may contain spoilers.

## Cubyz is a Sandbox Game, not a Survival Game
The goal of this project is to create a game about exploration, adventure, and building. There is no looming threat of hunger or monsters; the player should be able to build in peace and choose how they would like to play. 

### Avoid Unavoidable Threats
A player should have to create or approach a threat on their own terms, rather than the threat approach them. This should allow the player to interact with whatever they want without feeling forced to.

**Examples:**
- A player will not be attacked by monsters at night. They have to actively approach a monster-infested place such as a structure or cave. This is so they have free reign to do activites during the night without being interrupted or frustrated.
- A player has lost much health, and must risk what little life they have left to gather food. Note that the player cannot heal unless they have an accessory that consumes their energy. This is a situation the player has to face because of their own skill level.
- A player summons an event that spawns waves of enemies to their base.
- A player can claim a naturally generated structure by killing all monsters monsters in the area. Note that monsters do not respawn naturally.

### Progression = Risk
In order to progress in the game, the player must take risks. The player is otherwise free to stay where they are in terms of progression.

**Examples:**
- The deeper the player goes into the world's caves, the more valuables they can find, but consequentially, the more monsters they'll come across.
- The player must defeat an enemy, boss, or event to obtain an item that helps them progress.
- In a multiplayer world, a player could attack an enemy player to rise up in power.

## Break the Cycle
### No Dimensions
Instead of creating seperate dimensions, we can fit these places physically into Cubyz' massive world to allow the player to come across them on their own.

### No Teleportation
To immerse the player and let them feel the sense of scale the world of Cubyz has, teleportation is not allowed, as the player will see less of the world that way.

### No Automation
Instead of staying in one place and farming everything, the player should have to take advantage of the infinite nature of the world to gain resources, meaning that a majority of resources are non-renewable.

### Mobs Don't Respawn
To prevent farming, mobs will not respawn naturally once killed. This will also make the player more aware that killing has long-term consequences in the area it occurs in.

### No Passive Animals
Instead of animals standing by to let you kill them, they will run from the player, attack back, and use defense mechanisms. This should make hunting and taming much more engaging.

### No Unbreakable Tools
In Minecraft, a tool is an investment you can make. You can enchant the tool, rename it, make it your own; there's an incentive to make it last forever with the use of mending. In Cubyz though, you are not creating an investment, but rather a tool to use until it breaks. If a player gets too attached to their tool, then they won't want to make other types of tools, and lower-tier materials will see less use as they will never be used in tool-making.

### Avoid Clutter
Inventories will often fill up with random items that the player does not want, making their inventory hard to manage. To mitigate this, try finding uses for existing items before adding new ones, and find ways to prevent items from finding their way into a player's inventory when they don't want it.

## Player Engagement
### "How would the player feel?"
This is a very important part of game design in general. When a player encounters and re-encounters a mechanic or feature, put yourself in the player's shoes and ask "how would the player feel?" The goal is to make the player feel what you want them to feel, whether that be satisfaction, frustration, excitement, fear, or all of the above! It also helps to ask for feedback from players and asking how they feel about your addition.

### Depth in Simplicity
Cubyz' special sauce is its simplicity; keeping everything simple on the surface makes the game approachable for beginners, while the hidden depth keeps it interesting for skilled players. Avoid features that would add unnecessary tedium to the player's experience. Always think about how it would effect the player's first impressions of the game.

### Fuel the Player's Curiosity
The world is filled with secrets, and we want the player to find these secrets on their own without any outside help or guide.

### Problems have Multiple Solutions
Problems faced in a particular age of progression should have multiple solutions, instead of just one solution for everything.
For example, in the "Pre-Caves Age," the player will not have access to coal, as coal spawns low in the world and is shrouded in darkness. There's many solutions to this, however:
- Find a dim, above ground light source.
- Search for a cave with exposed coal.
- Wander into the darkness to find a cave that's bright enough to mine in.
- Find an above-ground structure that can grant the player coal.
- Dig straight down until you find coal.

Of course, this problem is completely solved as soon as the player gets coal, as they can now explore caves to find more coal with their newfound torches, but it's important that the player has these options in the first place to prevent them from getting stuck on a seemingly insurmountable barrier. This also gives them more freedom in how they can approach the game. Not one option is better or easier than the other, and if one turns out to be, then it should be allowed to be adjusted to encourage other methods.

### Explain when Needed
If something progress-related has no obvious explanation, the player will have to rely on a wiki to find out how to progress. One example is the bellows; players won't know to place it next to a furnace and jump on it repeatedly. The issue can be fixed by adding a tooltip that tells them how it works, while leaving out details they can intuitively find out themselves.

Having a mechanic that isn't explained or illuded to makes it an "Invisible Mechanic." These can only be found out through looking at the game's code, wiki reading, or asking a developer, thus giving a disadvantage to casual players. It's best to avoid these at all costs.

### Micro Moments
These are tiny things the player does in between larger events; examples include:
- Travelling
- Parkour
- Mining
- Building
- Crafting
- Managing inventory
- Fighting

These moments are extremely important as they let the player mentally rest, so making sure they're as satisfying and consistent as possible is a must.

### Make the World Feel Alive
To add immersion to the game, creatures should perform behaviors outside of player input, such as hunting, playing, migrating, eating, or sleeping.

## Balancing
When balancing the game, keep in mind how players might interact with the world, the wildlife, and each other.

### 2OP4ME
At no point should the player be extremely hard to kill. Armor, tools, accessories, and buffs should be designed around aiding the player in skill-based encounters, not letting them win regardless of skill.

### Trade-offs
If the player is given something to aid them, then it should have an appropriate take-away to balance it.

**Examples:**
- Using rare resources to create a strong tool.
- An accessory that heals the player, but takes away energy or some other resource.
- Enemies have strengths and weaknesses towards particular damage types

## Little Details

### Big Trees vs Small Trees
There are two categories of trees, big and small. Big trees are designed to be built upon or left as decoration, whereas small trees are designed to be chopped down.

### Vegetation
Vegetation should always fit the biome's climate. For example, Toadstools prefer humid areas, while Boletes prefer nutritious areas. Think about how a plant would fit into a biome or structure.

### Caves are Creepy and Mysterious
As the player goes deeper into Cubyz, they'll find that the music gets scarier, the monsters get harder and more disturbing, and the cave generation becomes an utter spectacle. We want the player to feel uneasy and stressed as they go down because it makes finding underground resources feel more rewarding.
