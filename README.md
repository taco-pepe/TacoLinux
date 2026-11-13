# tacolinux

the worlds worst distro of linux.

> [!WARNING]
> TacoLinux isn't a joke. it needs real Linux exp. do not use it as a first distro.
---------

## install

tacolinux is not like normal distros.  
you need to know how to build and package a root file system into a drive  
or dd the image we provide to a drive (this erases all data on disk)  

be sure to run  

```sh
lsblk
```

to see devices you have OR  

```sh
fdisk -l
```

Both should work.  

### formating the drive

to format a drive and prepare it for install we recommend fdisk.  
also a reminder:
Do not use the tacolinux setup image TO install tacolinux.
it wont work. most utils are not install by default.

i recommend using the cfdisk util.  

```sh
cfdisk /dev/DEV
```

replace DEV with device name shown to you in lsblk or fdisk -l.  
MOST importently. USE THE GPT LAYOUT!  

make a partition layout like this on a 50GB disk:  

| Partition | Size | Type |
| ----------- | ------- | -------- |
| /dev/DEV1 | 40GB | Linux |
| /dev/DEV2 | 9GB | Linux Swap |
| /dev/DEV3 | 1GB | Linux |
| /dev/DEV4 | 2MiB | BIOS boot |

here is an explanation of the layout.  

- /dev/DEV1 - Meant to be the root storage of distro  
- /dev/DEV2 - Meant to be the Swap of distro  
- /dev/DEV3 - Meant to be the Uefi or Bios /boot partition storing all of the files needed for boot
- /dev/DEV4 - grub boot partition Meant to be for booting on Bios systems.

> [!IMPORTANT]
> In `cfdisk`, set the type of ``/dev/DEV4`` to **BIOS boot** (partition type
> code ``EF02``), not "Linux". GRUB's ``i386-pc`` target embeds ``core.img``
> into this partition on a GPT disk, and it will not boot without it.
> Do **not** run ``mkfs`` on ``/dev/DEV4`` — it holds raw GRUB data, not a
> filesystem.

Now we need to format a filesystem for them.  

```sh
mkfs.ext4 /dev/DEV1
mkswap /dev/DEV2
mkfs.vfat -F32 /dev/DEV3
```

after this should be ready for the next step.

### installing the distro Rootfs

first for this step you need a machine connected to the internet and it should  
have the util named ``git`` we need it to clone the repo.  

first run

```sh
mkdir /mnt/prep
mount /dev/DEV1 /mnt/prep
mkdir /mnt/prep/boot
swapon /dev/DEV2
mount /dev/DEV3 /mnt/prep/boot
```

this preps ``/mnt/prep`` for installation.  
then do. on the dir you are in.  

```sh
git clone https://github.com/taco-pepe/TacoLinux
cd TacoLinux
```

this operation will take a bit of time depending on network speed.  
once its done do:  

```sh
cp bootstrap/grubstrap.py .
python3 grubstrap.py
```

this is the main setup. you should see:  

```shout
Root partition: 
```

enter in the root partition. (/dev/DEV1)  

after that you should see:  

```
Boot partition: 
```

enter in the boot part (/dev/DEV3)

after that:

```
Swap partition: 
```

enter in the swap partition (/dev/DEV2)

after that:

```
Target disk (e.g. /dev/sda): 
```

enter in the Target disk for grub to be installed to (/dev/DEV4)

after this the script will do its job setting up the env for boot.

---------

## prebuilt images

`scripts/build-vm-image.sh` packs the current `rootfs/` into a bootable disk.
It needs root for loop devices and mount:

```sh
sudo ./scripts/build-vm-image.sh

# useful knobs
sudo ROOTFS=./rootfs IMG_SIZE=8G COMPRESS=zstd ./scripts/build-vm-image.sh
```

Outputs land in `dist/`:

| File | Use |
| --- | --- |
| `tacolinux-<ver>-x86_64.qcow2` | run it directly in QEMU/KVM |
| `tacolinux-<ver>-x86_64.img.zst` | `zstd -dc <file> \| sudo dd of=/dev/sdX bs=4M status=progress` |
| `SHA256SUMS` | verify the downloads |

Disk layout (GPT):

| Partition | Size | Contents |
| --- | --- | --- |
| `p1` | 2 MiB | BIOS boot: raw GRUB `core.img`, no filesystem, never `mkfs` it |
| `p2` | rest | ext4 root, including `/boot` with `bzImage` and `initramfs.img` |

GRUB is installed to the *disk* (`--target=i386-pc`), with
`--boot-directory` pointing at `<root>/boot`. No swap partition is created;
add one or use zram if you want swap.

CI: `.github/workflows/build-image.yml` builds on `v*` tags (and manually) and
attaches the images plus `SHA256SUMS` to the GitHub release. GitHub caps
release assets at 2 GiB, so larger files are split into `.partNN` chunks; put
them back together with `cat name.part* > name` and verify with
`sha256sum -c SHA256SUMS`. The Forgejo mirror has the same workflow in
`.forgejo/workflows/build-image.yml`, but it needs a self-hosted runner with
loop/mount privileges: Codeberg's hosted runners are containers and cannot do
this.

### why not .qcow / .qcow2.gz / .img.gz?

- `.qcow` is QEMU's ancient v1 format. qcow2 is what every tool reads today.
- compressing qcow2 throws away sparse clusters and random access, which is the
  whole point of qcow2. It is already sparse; ship it as-is.
- gzip is slower and compresses worse than zstd on disk images. `COMPRESS=xz`
  (smaller, slower) and `COMPRESS=gzip` (compatibility) are still available.

