# MiniMenu for KOReader

Create small popup menus you can open from a tap, gesture, a key, a profile or another
plugin.

## Install

Copy `minimenu.koplugin` into KOReader's `plugins/` folder and restart.

## Usage

1. **Tools › MiniMenu › New menu…** creates a new menu.
2. Open the menu's page and choose **Edit items…** to add, remove and
   arrange items.
3. Bind it in **Settings › Taps and gestures › Gesture manager** under
   **General › MiniMenu: <name>**.

## Development

**Run integration tests**
```sh
KOREADER_DIR=<emulator>/koreader spec/integration/run.sh
```
