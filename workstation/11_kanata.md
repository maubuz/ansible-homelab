# kanata

Keyboard remapper — replaces kmonad. Runs **without root** as a manually-started
systemd *user* service, remapping the ThinkPad's built-in keyboard (caps→esc,
home-row mods, a space-held arrows layer).

Installed by [`11_kanata.sh`](./11_kanata.sh). Ubuntu 24.04+, GNOME/Wayland.

## Where things live

| What | Path |
| --- | --- |
| Binary | `/usr/local/bin/kanata` (GitHub release, root-owned) |
| Config | `~/.dotfiles/kanata/kanata/mauMap.kanata.kbd` → stowed to `~/.config/kanata/` |
| Unit | `~/.config/systemd/user/kanata.service` |
| udev rule | `/etc/udev/rules.d/70-kanata.rules` |

The installer deliberately does **not** place the config — that comes from the
dotfiles repo via stow.

## Install

```sh
./11_kanata.sh                      # pinned version; KANATA_VERSION=latest to track newest
# log out and back in — input/uinput group membership only applies to a new session
cd ~/.dotfiles && stow -vt ~/.config kanata
systemctl --user start kanata.service
```

To verify the download, pass the expected hash: `KANATA_SHA256=<sha256> ./11_kanata.sh`.

### What the script does

1. Downloads `linux-binaries-x64.zip` from the kanata release and installs the
   binary to `/usr/local/bin/kanata` (skips if the pinned version is already there).
2. Creates the `uinput` group and adds you to `input` and `uinput`.
3. Writes `/etc/modules-load.d/uinput.conf` and loads the module.
4. Installs a udev rule giving the `uinput` group access to `/dev/uinput` — this
   is what makes running without root possible.
5. Writes the systemd user unit and reloads the daemon.
6. Appends `compose:menu` to the GNOME xkb options (see [Compose key](#compose-key)).

Re-running is idempotent.

## Daily use

```sh
systemctl --user start|stop|status kanata.service
journalctl --user -u kanata.service -f
kanata --cfg ~/.config/kanata/mauMap.kanata.kbd --check   # validate before restarting
```

**Panic chord:** hold Left Ctrl + Space + Escape (physical keys, pre-remap) to make
kanata exit if a config leaves the keyboard unusable.

The unit is `static` — started by hand, not at login, so a bad config can never
lock you out of a fresh session. To autostart anyway, uncomment `WantedBy=default.target`
in the unit and run `systemctl --user enable kanata.service`.

`--no-wait` in `ExecStart` skips kanata's "Press enter to exit" prompt on a fatal
error. The unit only survives without it because `StandardInput` defaults to `null`
and the prompt reads EOF immediately; give the service any real stdin and it would
hang forever instead of exiting, so `Restart=on-failure` would never fire. Upstream
recommends the flag for service use.

### Verify a fresh install

```sh
groups | grep -E '\b(input|uinput)\b'                          # both present
ls -l /dev/uinput                                              # crw-rw---- root uinput
ls -l /dev/input/by-path/platform-i8042-serio-0-event-kbd      # the mapped keyboard
```

Then, with the service running: `caps` → Esc; hold `a`/`;` → Meta; hold `f`/`j` →
Shift; hold `spc` → arrows layer (`h j k l` → ←↓↑→, `f1`–`f12` on the number row).

## Config notes

Two layers: `homeMods` (base) and `arrows` (held-space). Home-row mods use
`tap-hold-release TAP-TIME HOLD-TIME TAP HOLD`, 130–180 ms depending on finger —
kmonad's `tap-hold-next-release` took a single timeout, so both values are set the same.

**Every `deflayer` must have exactly as many tokens as `defsrc` — 50 here.** Editing
`defsrc` means editing every layer. Function keys are lowercase (`f1`, not `F1`).

### Compose key

kmonad ran `setxkbmap -option compose:ralt` from its `uinput-sink`; kanata has no
equivalent, so the xkb option must be set out of band. The arrows layer emits `cmps`
(`KEY_COMPOSE`), but that keycode is aliased to `<MENU>`, which the default layout
binds to `Menu` — **not** `Multi_key`. Without an xkb option it silently does nothing.

Step 6 of the script therefore appends `compose:menu`. It uses `compose:menu` rather
than `compose:ralt` so that an existing `lv3:ralt_alt` (Right Alt as level-3 shift for
accented characters) keeps working:

```sh
gsettings get org.gnome.desktop.input-sources xkb-options
# ['lv3:ralt_alt', 'compose:menu']
```

Test: hold space, tap the `cmps` position (the `y` key), then `'` `e` → `é`.
Note that `setxkbmap` appears to work but GNOME Wayland reverts it — use `gsettings`.

## Troubleshooting

Capture the real error first — run in the foreground for fast feedback, or read the
journal. Kanata's parser gives line-numbered errors.

```sh
kanata --cfg ~/.config/kanata/mauMap.kanata.kbd     # foreground
journalctl --user -u kanata.service -n 200 --no-pager
```

The simulator at <https://jtroo.github.io> checks a config and simulates keypresses
without installing anything.

| Symptom | Cause / fix |
| --- | --- |
| `deflayer X has Y keys but defsrc has Z keys` | Token counts must match exactly — 50 per layer. |
| `unknown key name: <name>` | Check [`keys/mod.rs`](https://github.com/jtroo/kanata/blob/main/parser/src/keys/mod.rs). Usually function-key casing. |
| `could not open device` / `Permission denied` | Group membership not applied — `groups` must show `input` and `uinput`; log out and back in. |
| `uinput: No such file or directory` | Module not loaded: `sudo modprobe uinput`, check `/etc/modules-load.d/uinput.conf`. |
| Device path missing after a replug or kernel update | Re-check `ls /dev/input/by-path/ /dev/input/by-id/` and update `linux-dev`. |
| Keys do nothing / wrong keys | Kanata grabbed the wrong device — cross-check `cat /proc/bus/input/devices` against `linux-dev`. External keyboards not listed there just pass through. |
| `status=218/CAPABILITIES` | A hardening directive requiring root crept into the unit. **User-mode systemd cannot set capabilities or create namespaces** — see below. |

### Unit hardening

The unit enables only directives that work without root. Anything requiring
capability manipulation or kernel-namespace setup fails the whole unit with
`218/CAPABILITIES`, which is how it failed the first time. Deliberately omitted:
`CapabilityBoundingSet`, `AmbientCapabilities`, `RestrictSUIDSGID`,
`ProtectKernel{Tunables,Modules,Logs}`, `ProtectControlGroups`, `ProtectClock`,
`ProtectHostname`, `ProtectProc`, `PrivateNetwork`, `DeviceAllow`, `DevicePolicy`.

Check with `systemd-analyze --user security kanata.service`. If something needs
relaxing, drop in this order: `MemoryDenyWriteExecute` → the `SystemCallFilter=~…`
deny list → `RestrictAddressFamilies` .

`ProtectHome=read-only` still permits reads, so config live-reload (`lrld`) works.

### Wayland tooling

| To… | X11 | Wayland |
| --- | --- | --- |
| See what keysym a keypress produces | `xev` | `wev` |
| See raw evdev events | `xinput test` | `evtest` (needs `input` group) |
| Type Unicode from a script | `xdotool type` | `wtype` |
| Set xkb options persistently | `setxkbmap` | `gsettings set org.gnome.desktop.input-sources xkb-options …` |

`wev` is the most useful tool for "the wrong character came out" problems — it shows
what the compositor actually received.

## References

- [Config guide](https://github.com/jtroo/kanata/blob/main/docs/config.adoc) ·
  [Linux setup](https://github.com/jtroo/kanata/blob/main/docs/setup-linux.md) ·
  [Avoid using sudo on Linux](https://github.com/jtroo/kanata/wiki/Avoid-using-sudo-on-Linux)
- [All-features sample](https://github.com/jtroo/kanata/blob/main/cfg_samples/kanata.kbd) ·
  [home-row mods sample](https://github.com/jtroo/kanata/blob/main/cfg_samples/home-row-mod-advanced.kbd)
- [Platform known issues](https://github.com/jtroo/kanata/blob/main/docs/platform-known-issues.adoc)
- `man systemd.exec` for the hardening directives
- Original kmonad config: [maubuz/mau-kmonad](https://github.com/maubuz/mau-kmonad/blob/main/user/mauedu/mauMap.kbd)
