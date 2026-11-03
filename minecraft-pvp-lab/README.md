# PvP Lab — Fabric 1.20.4

PvP Lab is a 50-agent Minecraft training arena. It runs 25 pairs of visible humanoid villager agents in parallel and trains a shared reinforcement-learning policy for defensive movement, spacing, evasive navigation, and target tracking.

## What's included

- 50 visible agents with iron armor, arranged as 25 training pairs.
- Parallel self-play: all agents collect observations and contribute reward feedback to a shared Q-learning policy.
- Eight learned movement actions: orbiting, lateral repositioning, retreating, changing distance, and jumping.
- Generation-based evaluation with an elite checkpoint. The best policy is retained; weaker generations restore the champion and perturb the policy.
- Automatic snapshots: \`latest.json\` after every generation and \`champion.json\` whenever a new best fitness is recorded.
- Manual save/load for named models.
- A single training-partner mode that observes player movement and practises spacing.
- Press **K** to open the GUI.

Agents are training avatars, not real player connections. This build focuses on movement and defensive positioning; it does not implement weapon use, attacks, explosions, crystal PvP, or automated player control.

## Commands

\`\`\`
/pvplab train             # 50 agents, 5 minutes
/pvplab train 900         # 50 agents, 15 minutes (60–3600 seconds)
/pvplab challenge         # one movement-training partner
/pvplab status
/pvplab stop
/pvplab save champion
/pvplab load champion
\`\`\`

Each generation lasts 60 seconds. The default five-minute session therefore evaluates five generations. The arena is created around the player; use a reasonably open area.

## Model files

\`\`\`
.minecraft/config/pvplab/models/latest.json
.minecraft/config/pvplab/models/champion.json
\`\`\`

Model format 2 stores the current Q-table, elite table, exploration rate, generation counter, update count, and best fitness. Format 1 snapshots from the earlier prototype remain loadable.

## Build and install

Requirements: JDK 17 and Gradle 8.7.

\`\`\`sh
gradle build
\`\`\`

Install Fabric Loader and Fabric API for Minecraft 1.20.4, then put \`pvplab-1.0.0.jar\` into \`.minecraft/mods/\`. Open the GUI with **K** or use the commands above. For server play, install the mod on the server and on clients that need the GUI.
