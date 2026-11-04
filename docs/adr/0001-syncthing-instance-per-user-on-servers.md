# Syncthing on servers: a system instance plus one instance per user

Servers run `syncthing@syncthing` as a dedicated **service account**, plus a
`syncthing@<user>` **personal instance** for each user in `server_syncthing_users`.
Every instance serves its GUI on a private Unix socket, never a TCP port. This
replaces a single `syncthing@<admin>` that ran with the admin's full file access.

## Why

On a multi-user server, `syncthing@mau` gave the daemon all of `mau`'s files
(including `~/.ssh`), kept its identity where anything running as `mau` could
impersonate the device, and exposed a GUI on `127.0.0.1:8384`. That GUI is
administrable by any local user: fetching the page returns a CSRF token, and with
only that token the REST API answers `GET /rest/system/config` and `POST`.
Separate instances give each user's files their own process and their own
identity, and the sockets make file permissions the access control.

## Considered options

- **Keep `syncthing@<admin>`.** Rejected: the exposure above.
- **One instance with per-folder POSIX groups and ACLs**, so users read and write
  different folders of one replica. Rejected: much more to configure and keep in
  step with Ansible (a folder list, groups, ACLs, `ignore-perms`), and it drifts
  from a default Syncthing install.
- **A loopback GUI port with a password on every instance.** Rejected: more to
  manage than a socket, and a single missing password is a local takeover.

## Consequences

- Read-only is self-enforced. Syncthing has no per-device write permission, so
  a consuming user's side must be Receive Only; versioning on the system
  instance is the backstop.
- Admin is membership of group `syncthing`, managed exclusively by the role, so a
  temporary grant lapses on the next run.
- The role manages only the OS side; devices and folders are set by hand in each
  GUI. See [docs/syncthing-server.md](../syncthing-server.md).
- No firewall is configured.
