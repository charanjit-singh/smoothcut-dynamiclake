# SmoothCut for DynamicLake

Shows [SmoothCut](https://smoothcut.studio) in the notch: a live activity while you record
(a recording indicator and a running timer, with Pause / Resume and Stop in the sneak peek), and
progress then a "Show in Finder" shortcut while you export.

## Requirements

- macOS with [DynamicLake](https://dynamiclake.com) (Pro or Playground).
- [SmoothCut](https://smoothcut.studio/download) 1.18 or later. SmoothCut is free to download and use.

## Use it

1. In SmoothCut: Settings, AI assistants tab, Notch, turn on **Show in the notch**.
2. In DynamicLake: Settings, Plugins, Install Local, and choose this `.dynamiclakeplugin` folder
   (SmoothCut's **Add to DynamicLake** button saves it to Downloads for you).

When SmoothCut is not running, or the switch is off, the plugin waits quietly and shows nothing.

## How it works

`smoothcut-dynamiclake.pl` is a relay and nothing else. DynamicLake starts it with
`DYNAMICLAKE_JSON_SOCKET`; once SmoothCut's local socket is there (only while the setting above is
on), it connects to both, sends SmoothCut a one-line hello that carries
`DYNAMICLAKE_PLUGIN_FEATURES`, and copies bytes both ways. The framing and the JSON
(`create` / `update` / `dismiss`, `action` callbacks) are SmoothCut's side of the conversation.

DynamicLake only trusts messages from the process it launched, so the script holds both
connections itself rather than handing them to a helper. It is Perl because every Mac ships
`/usr/bin/perl` and it can do that; there is no Python or Node to rely on, and it uses only modules
that come with macOS.

- The plugin only ever relays; it cannot make SmoothCut do anything except what SmoothCut itself
  answers to: pause, resume, stop, and reveal the file just exported.
- It never writes anywhere: no temporary files, nothing inside the installed package.
- No network access. SmoothCut's socket is in its own data folder, readable by you only.

## Package it

This repository is the plugin package. To make the folder DynamicLake installs and the Market
archive from it:

```sh
mkdir -p dist && rsync -a --exclude dist --exclude .git ./ dist/SmoothCut.dynamiclakeplugin/
cd dist && ditto -c -k --keepParent SmoothCut.dynamiclakeplugin SmoothCut-1.0.0.zip
shasum -a 256 SmoothCut-1.0.0.zip
```

SmoothCut's own **Add to DynamicLake** button writes the same package to your Downloads folder.

## Licence

Copyright (c) 2026 Charanjit Singh. GPL-3.0, see `LICENSE`: you may study, change and share this
plugin, and anything built from it must be released under the same licence, with this notice kept.
