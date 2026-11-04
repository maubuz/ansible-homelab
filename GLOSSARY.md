# Homelab

Ansible configuration for a personal homelab of desktops, servers and single-board computers. This glossary covers the vocabulary of file synchronisation on servers.

## Language

**Synced folder**:
A directory whose contents Syncthing keeps in step with other devices.
_Avoid_: Share, sync dir, data dir

**Service account**:
The unprivileged account the system instance runs as. It exists only for Syncthing, has no login, and is not a person.
_Avoid_: Syncthing user, daemon user

**Admin user**:
The person who administers a server and its system instance. A human account, distinct from the service account.
_Avoid_: Owner, operator

**System instance**:
The one Syncthing instance on a server that runs as the service account and is configured by the admin user through its GUI. It is either a mirror of another node or the central replica that other nodes sync to.
_Avoid_: Central instance, server instance, system-wide service

**Personal instance**:
A Syncthing instance on a server that runs as an ordinary user, with its own devices, folders and GUI. It syncs with the system instance or with some other node.
_Avoid_: User service, client, second instance

**Consuming user**:
A user on a server who has a personal instance.
_Avoid_: Consumer, second user
