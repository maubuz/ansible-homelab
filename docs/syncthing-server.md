# Syncthing on servers

Terms (**system instance**, **personal instance**, **service account**, **admin
user**, **consuming user**, **synced folder**) are defined in
[GLOSSARY.md](../GLOSSARY.md). The decision behind this layout is
[ADR 0001](adr/0001-syncthing-instance-per-user-on-servers.md). The role is
`roles/server_syncthing`; the workstation `syncthing` role (a systemd *user*
service) is separate and unchanged.

The role manages only the operating-system side: accounts, directories, systemd
units and three network settings. **Devices and folders are never configured by
Ansible.** You set them up by hand in each instance's GUI.

## The model

```
                    server
  ┌──────────────────────────────────────────────────────────┐
  │  syncthing@syncthing      runs as: syncthing (no login)  │
  │    data   /srv/syncthing          0750 syncthing:syncthing│
  │    GUI    /run/syncthing-syncthing/gui.sock  (group)      │
  │    listens 22000                                          │
  │         ▲ tcp://127.0.0.1:22000                           │
  │         │                                                 │
  │  syncthing@alice          runs as: alice                  │
  │    data   ~alice/...      GUI /run/syncthing-alice/gui.sock│
  │  syncthing@bob            runs as: bob                    │
  │    data   ~bob/...        GUI /run/syncthing-bob/gui.sock  │
  └──────────────────────────────────────────────────────────┘
```

- The **system instance** is a mirror of another node or the central replica
  other nodes sync to. The admin user decides, in its GUI, which folders each
  consuming user's device receives.
- A **personal instance** exists for every user in `server_syncthing_users`. It
  has its own devices, folders and GUI, and syncs with the system instance over
  `tcp://127.0.0.1:22000` (no network involved) or with some other node.
- Personal instances keep Syncthing's defaults. On the system instance the role
  turns global discovery, relays and NAT traversal off. Local discovery stays on,
  which is how a phone on the home network finds the server.
- The system instance is sandboxed (`ProtectHome`, `ProtectSystem=strict`,
  dropped capabilities, and more; `systemd-analyze security` scores it 2.8).
  Personal instances keep the packaged unit's hardening only (score 8.3), because
  `ProtectHome` would break them. A compromised personal instance is a
  compromise of that user, as on a desktop.

## Reaching a GUI

Every instance serves its GUI on a **Unix socket**: a file that programs connect
to instead of a network port. Who can open the file decides who can use the GUI.
Nothing listens on `8384` or any other GUI port. `tailscale serve` cannot proxy
to a socket, so use an SSH tunnel; OpenSSH 6.7 or newer can forward to one.

In `~/.ssh/config` on your own machine:

```
Host myserver-st
    HostName myserver.lan            # or the MagicDNS name over Tailscale
    User mau
    LocalForward 8384 /run/syncthing-syncthing/gui.sock
    # a personal instance: /run/syncthing-<user>/gui.sock
```

```sh
ssh -N myserver-st        # leave it running
# browse http://localhost:8384
```

Only the owner of an instance (and, for the system instance, members of group
`syncthing`) can open its socket. Anyone who *can* open it can administer the
instance: the socket permissions are the access control, the GUI password is not.

Scripts and `cli` calls: `syncthing cli` reads the API key from the instance's
`config.xml`, so run it as the instance's user and give the socket through the
environment:

```sh
sudo -u alice env STGUIADDRESS=unix:///run/syncthing-alice/gui.sock syncthing cli config options relays-enabled get
```

On Syncthing 1.29.5 (Ubuntu 26.04) `syncthing cli --gui-address=unix://...`
fails to parse the address; the environment variable works. Plain `curl
--unix-socket` needs the `X-API-Key` header from `config.xml` (or a CSRF token
from a first `GET /`); without either it gets `403 CSRF Error`.

## Pair a personal instance with the system instance

1. Open the personal instance's GUI. *Actions → Show ID* and copy the device ID.
2. In the same GUI: *Add Remote Device*, paste the system instance's ID
   (*Actions → Show ID* in the system GUI), and under *Advanced* set Addresses to
   `tcp://127.0.0.1:22000`.
3. Open the system instance's GUI. A notice offers the new device; accept it and
   name it (`alice`). Do not tick *Auto Accept* or *Introducer*.
4. In the system GUI, edit each folder the user should get, and tick the user's
   device under *Sharing*.
5. The personal instance shows a notice for each shared folder. Accept it,
   choose a path in the user's home and, for read-only, set *Folder Type* to
   **Receive Only** before saving.

## Folders, read-only and read-write

Choose per folder, in the system GUI, what each consuming user's device gets.
Share only what that user needs; a folder shared with nobody is invisible to
them.

Syncthing has no per-device write permission. **Read-only is therefore
self-enforced**: it is a Receive Only folder on the consuming user's side, set by
whoever configures that side. A peer with a Send & Receive share can push edits
and deletions into the system instance's folder. Two backstops:

- Give the system instance's folders **versioning** (Trash Can or Staggered), so
  a bad delete lands in `.stversions` instead of vanishing. Tested: a deletion
  from a personal instance in a Send & Receive share was kept in `.stversions`.
- Make a pure mirror folder **Send Only** on the system instance. That blocks
  changes from every peer.

A Receive Only folder shows local changes as "locally changed" and does not send
them back (tested). Folders under `/srv/syncthing` are readable only by the
system instance and the admins.

## Granting and revoking admin

The admin user is `server_admin_user`. Admin is membership of group `syncthing`,
which can open the system instance's GUI socket and read `/srv/syncthing`. The
role makes membership **exclusive**: the members are exactly `server_admin_user`.

```sh
sudo gpasswd -a <user> syncthing     # grant; takes effect in a new login session
sudo gpasswd -d <user> syncthing     # revoke
```

A grant lasts until someone removes it or the next role run, whichever comes
first. Admin access means full control of every folder and device on the system
instance and read access to everything in `/srv/syncthing`. It does not reach
personal instances.

## Adding and removing a consuming user

Add the user (who must already exist) to `server_syncthing_users` in
`group_vars/all.yml` and run the server playbook. The role starts
`syncthing@<user>`; its first start creates the config under
`~<user>/.local/state/syncthing` and picks free ports, which is why the system
instance is always started first. Then pair it as above.

Removing a user from the list stops and disables their instance on the next run.
It **never deletes** their config, identity or synced files, so adding the user
back restores everything. The same cleanup stops any other enabled `syncthing@*`
unit, such as the old `syncthing@<admin>` from before this layout; its data
stays where it was.

A service that needs files gets its own account in the list. There are no
direct-file readers.

## Phone (Android)

The phone keeps using Tailscale. Set the server's address explicitly in the
phone's device entry, `tcp://<server>.<tailnet>.ts.net:22000`, because global
discovery and relays are off on the system instance. At home, local discovery
finds the server on its own. Not tested here: there is no Tailscale or phone in
the VM.

## Why the GUI is not a loopback port

A GUI on `127.0.0.1:8384` is reachable by every local user. On a default instance
with no GUI password, fetching the page returns a CSRF token, and with only that
token `GET /rest/system/config` and `POST` calls succeed. So any local user
could administer the instance and, on a personal one, add `~/.ssh` as a folder
and sync it out. Protecting every instance with a GUI password would be more to
manage than a socket. Please do not "simplify" this back to a port.

## Known limits

- No per-device write permission (above); read-only is self-enforced.
- Compromising the system instance exposes all its folders.
- The firewall is out of scope. Syncthing listens on `22000` (system instance)
  and on a random port per personal instance, on all interfaces, plus `21027`
  local discovery. Restrict them on the host if the network is not trusted.
- Discovery: the system instance holds IPv4 `21027`; the personal instances share
  the IPv6 one. The journal shows no "address already in use" errors, even after
  a reboot.
- Tested on Syncthing 1.29.5. The three `cli` options the role sets
  (`global-ann-enabled`, `relays-enabled`, `natenabled`) must keep these names on
  a newer major version.
- Not testable in the VM: Tailscale access, pairing the phone, a real pull on a
  physical server.
