# My Pico-8 Carts Repository

This repository contains PICO-8 cartridges and related assets. It is organized to keep carts (`*.p8`) together with backups, exported images, and tools useful for development.

- My Lexaloffle profile: https://www.lexaloffle.com/bbs/?uid=137807

Repository layout:

- `carts/` — main PICO-8 cartridges (`*.p8`)
- `backup/` — backups and exported carts
- `cdata/`, `cstore/`, `plates/` — project-specific data and assets
- `tools/` — utilities and scripts for building/exporting carts

Quick start

1. Install PICO-8 (download from https://www.lexaloffle.com/pico-8.php).
2. Open a cart in the PICO-8 application: File → Open → select `carts/your_cart.p8`.
3. Or run from command line (if `pico8` CLI is available):

```powershell
pico8 -run carts\your_cart.p8
```

## VS Code setup for PICO-8 development

Recommended extensions

- Lua (Lua Language Server) — provides language features for editing PICO-8 carts (`*.p8`) when associated with Lua.
- PICO-8 / Pico-8 syntax highlighting — search the Marketplace for "PICO-8" to get syntax coloring for carts.
- Code Runner — run commands or run the current file from the editor.

Workspace settings (create `.vscode/settings.json`)

```json
{
	"files.associations": {
		"*.p8": "lua"
	},
	"files.eol": "\n",
	"editor.tabSize": 2,
	"editor.insertSpaces": true,
	"editor.formatOnSave": false
}
```

Example tasks (create `.vscode/tasks.json`) — adjust `pico8Path` for your system:

```json
{
	"version": "2.0.0",
	"tasks": [
		{
			"label": "Run current cart in PICO-8",
			"type": "shell",
			"command": "C:\\path\\to\\pico8.exe",
			"args": ["-run", "${file}"],
			"presentation": { "reveal": "always" }
		}
	]
}
```

Notes

- Replace `C:\\path\\to\\pico8.exe` with your PICO-8 executable path (on Windows, e.g., `C:\\Program Files (x86)\\PICO-8\\pico8.exe`).
- If you use a CLI wrapper or have `pico8` on your PATH, you can set `"command": "pico8"`.
- There is no official debugging adapter for PICO-8; use logs and visual debugging inside the cart.

Optional: add a `.vscode/launch.json` if you want quick Run/Task bindings, or define keyboard shortcuts for the task in VS Code.

