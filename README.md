# Immersive Controller UI

Immersive Controller UI (ICUI) is a World of Warcraft addon that keeps the
gamepad experience focused by fading interface elements until they are needed.

## Features

- Fades the core HUD based on combat, target, and controller input.
- Reveals the full interface while both triggers are held, with configurable
  behavior for revealing it outside combat.
- Optionally fades the minimap, chat, quest tracker, experience bar, micro menu,
  and bags.
- Reveals the interface temporarily when the mouse moves in gamepad mode.
- Provides configurable fade timing, soft-target opacity, and visibility tests.

## Requirements

- World of Warcraft client with interface version 16001 or compatible.
- Gamepad mode enabled for controller-specific behavior.

## Installation

1. Download or clone this project.
2. Place the `ImmersiveControllerUI` folder in the game's `Interface\AddOns`
   directory.
3. Enable **Immersive Controller UI** from the AddOns list at character select.

## Usage

Open the addon's settings from **Options → AddOns → Immersive Controller UI**,
or use these chat commands:

| Command | Description |
| --- | --- |
| `/icui options` | Open the addon's settings. |
| `/icui status` | Show current settings and visibility state. |
| `/icui reset` | Restore default settings. |
| `/icui test idle` | Test with the HUD hidden. |
| `/icui test soft` | Test with the HUD at soft-target opacity. |
| `/icui test full` | Test with the HUD fully visible. |
| `/icui test real` | Return to visibility based on game conditions. |

Settings are saved in the `ImmersiveControllerUIDB` saved variable.

## Project files

- `Core.lua` — defaults, saved settings, and chat commands.
- `Visibility.lua` — visibility conditions and controller/mouse-driven reveals.
- `Controller.lua` — controller state and button handling.
- `UI.lua` — interface frame opacity and fade handling.
- `Settings.lua` — in-game options panel.
- `ImmersiveControllerUI.toc` — addon metadata and load order.
