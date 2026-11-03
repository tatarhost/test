# PvP Lab — Fabric 1.20.4

A Fabric mod with unarmed sparring bots, self-play training, a tabular Q-learning policy, an in-game control screen, and named model snapshots.

## Features

- Two bots spar against each other.
- Self-play runs a configurable number of rounds and respawns the pair between rounds.
- The shared Q-table learns movement choices with reward feedback: damage dealt, damage received, and spacing.
- Challenge mode spawns one bot that spars against the player.
- Press **K** to open the GUI.
- Save/load learned models as JSON in `config/pvplab/models/`.
- Server-side commands work in singleplayer and on a Fabric server with the mod installed.

Bots are intentionally unarmed. Their movement policy is learned by Q-learning; Minecraft's regular mob AI handles close-range contact.

## Commands

```
/pvplab duel
/pvplab challenge
/pvplab train 500
/pvplab stop
/pvplab save default
/pvplab load default
```

The GUI has buttons for the same actions. The model name field accepts letters, digits, underscores, and hyphens.

## Build

Requirements: JDK 17 and Gradle 8.7.

```sh
gradle build
```

The remapped mod JAR is created in `build/libs/`.

## Install

1. Install Fabric Loader for Minecraft Java 1.20.4.
2. Put the matching Fabric API 1.20.4 JAR in the `mods` folder.
3. Put `pvplab-1.0.0.jar` in the same `mods` folder.
4. Start a world, press **K**, or run one of the commands.

For multiplayer, install the mod on the server and on clients that need the GUI. The training and model state run on the server.

## Model files

Use **Сохранить модель** / **Загрузить модель** in the GUI or the matching commands. JSON snapshots are stored in:

```
.minecraft/config/pvplab/models/
```

Copy a JSON snapshot into that folder to import it by name. Existing snapshots are not overwritten unless you save again with the same name.
