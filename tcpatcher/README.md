# TcPatcher - the update system for tacolinux

A tacolinux System cannot naturaly be updated.  
this utility allows the system to take .tcpatch files and apply the patches.  

# The arch of a .tcpatch file

it will be something like:

```tree
tcpatch
├── folders_or_files_to_be_merged_with_root_dir
└── path.cfg
```

in the root put the files you want to be merged with the root(/) folder of tacolinux.  
inside a patch.cfg you can put:

```cfg
NAME="Example_Patch" # name of patch
DES="An example patch for tacolinux" # discription of patch.
PVER=1.0 # patch version
TVER=2.0.0 # tacolinux version
PERM=keep # file permissions. keep or allroot or alluser.
L=gplv3-only # license
```

# The cli

tcpatcher has a cli named ``tcpatch`` the usage is simple.  

```sh
tcpath apply --local path/to/patch.tcpatch # apply a patch from a local file.
tcpatch subscribe https://remote.git/user/patchrepo # subscribe to a patch repo. read the section Remotes for more info
tcpatch apply all # apply all patches from all repos. only applys ones that havent been applyed.
tcpatch apply REMOTE # apply alll patches from ONE remote 
tcpatch apply REMOTE:patch_name # apply a spesific patch from a remote.
tcpatch update # same as apply all.
tcpatch new patch_name # makes a new patch project
tcpatch build . # builds the current directorys patch. makes a dist/patch_name-PVER.tcpatch
tcpatch update --dry-run # a dry run. of update
tcpatch remotes # list all remotes.
tcpatch remotes make remote_name # makes a git repo with a HOWTOADDP.md guiding on how to add patches.
tcpatch status # shows status.
```

# The Remotes

a remote will look like:  

```
remote
├── example_package
│   ├── files_to_be_merged_with_root_dir
│   └── patch.cfg
└── remote.cfg
```

a remote.cfg should be something like:  

```cfg
REMOTE_NAME="example_remote" # the remote name
STATUS_REMOTE="up" # down for well.. down. up for up and unmaintained for no longer having new packages.
RP="ssh" # remote protocal. will be used to fetch patches from the repo. git is standerd git. http is the http protocal. for repos that are private ssh is recommended
RVER=1.0.0 # remote version.
```

# How patches are applyed

by rsyncing the files to the / dir of tacolinux. simple and easy.  

also all patches data are stored under  
/usr/tcpatch/db.json  
a json database that looks something like:  

```json
{
  "patch_name": {
    "VER": 1.0.0,
    "DES": "An example patch",
    "TLVER": "1.0.0-tclinux"
  }
}
```

the tacolinux version is found in:  
/usr/distro/version.cfg  

and looks like:

```cfg
VER=1.0.0
```

for example.

# choices of design

if a patch wants to remove a file we ask:  

```sh
patch_name wants to remove {PATH_TO_File} allow? 
```

answer should be yes or no. or just a y or n.  
if y or n is capital. for example Y and N. all the other choices will be the same.  

and the download looks like:  

```sh
$ tcpatch apply REMOTE:update1
Are you sure you want to apply update1 from REMOTE? y
update1:
      File1 -> /path/to/file [-----------------|------] 71.1% ETA=12s # | is where the download is currently at ETA is the ETA
Reloading systemd deamon.
Adding patch to database.
Done. nothing else to do :D
$
```

# Implementation notes

The CLI lives in `tcpatch` (bash) with helpers under `lib/`. TacoLinux ships
bash, `jq`, `git`, `rsync`, `zstd`, `wget` and coreutils as static binaries, so
the patcher needs no Python or interpreter packages. Config files are parsed,
never sourced, so a remote's `patch.cfg` cannot execute shell code.

Install into a root tree with:

```sh
./install.sh /path/to/rootfs   # or plain ./install.sh for the running system
```

`install.sh` also seeds `/usr/distro/version.cfg` from `/etc/os-release` when
that file is missing (current TacoLinux images only have `os-release`).

A `patch.cfg` can additionally list files to delete in a `remove.list` next to
it, one path per line. Every deletion is confirmed individually, defaulting to
no. `PERM=keep` preserves modes; `allroot` sets root ownership with 755 dirs and
644 files (executable bits kept); `alluser` uses uid/gid 1000.

`tcpatch build` produces a single-file `.tcpatch`: a simple `TCPATCH1` text
format with base64 payloads, optionally wrapped in a zstd frame. It needs no
`tar` or `gzip`, neither of which exists inside TacoLinux.

## Testing

```sh
./tests/run-tests.sh
```

The suite uses `--root` sandboxes under `/tmp/opencode/tcpatch-tests` and
covers new/build/apply, archives, dry-run, removals, remotes, status and config
injection. It was also run successfully inside a booted TacoLinux VM.

For safe testing against a system image, use `--root` and/or `--home`:

```sh
tcpatch apply --local patch.tcpatch --root /tmp/fakeroot --dry-run
```

Note: paths in a `.tcpatch` may not contain tabs (the internal format is
tab-delimited). Everything else is fine.
