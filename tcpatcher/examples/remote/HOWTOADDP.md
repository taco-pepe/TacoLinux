# Example patch remote

A remote is a git repository with a `remote.cfg` at the top level. Every
subdirectory containing a `patch.cfg` is a patch that `tcpatch apply REMOTE`
will pick up.

```
example_remote/
├── remote.cfg
├── HOWTOADDP.md
└── hello-world/
    ├── patch.cfg
    ├── remove.list
    └── usr/local/bin/hello-teto
```

Publish it, then subscribe from TacoLinux:

```sh
tcpatch subscribe git@example.org:you/example_remote.git
tcpatch apply example_remote:hello-world
```
