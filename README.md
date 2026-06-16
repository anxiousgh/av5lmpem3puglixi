# av5lmpem3puglixi

Roblox script hub. Public repo, loaded with a plain `game:HttpGet` (no key).

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/anxiousgh/av5lmpem3puglixi/main/loader.lua"))()
```

## Status

**Foundation only.** This currently just boots the vendored UI library and shows
a small test GUI. The feature backend and per-game UI modes are added later.

## Layout

```
loader.lua          entry point: single-instance guard, commit-SHA pin,
                    loads the vendored library, builds the (test) GUI
version.txt         current version string
lib/
  Mentality.lua     VENDORED copy of the Mentality UI library so we control
                    and can modify it (source: sametexe001/sametlibs)
games/              per-game UI modes (one file per PlaceId) -- added later
```

## UI library

We use a vendored copy of **Mentality** (`lib/Mentality.lua`) instead of fetching
it from upstream, so changes are always under our control. To pull upstream
updates, re-download:

```
https://raw.githubusercontent.com/sametexe001/sametlibs/main/Mentality/Library.lua
```

and review the diff before committing.

## Roadmap

- [x] Repo + vendored UI library + test GUI
- [ ] Core engine (`core.lua`): services, util, config, feature backends
- [ ] Shared UI pages (`ui.lua`)
- [ ] Per-game UI modes under `games/` (MM2, Prison Life, Hood Customs, ...)
