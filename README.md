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
| /dev/DEV4 | 2Mib | grub_boot |

here is an explanation of the layout.  

- /dev/DEV1 - Meant to be the root storage of distro  
- /dev/DEV2 - Meant to be the Swap of distro  
- /dev/DEV3 - Meant to be the Uefi or Bios /boot partition storing all of the files needed for boot
- /dev/DEV4 - grub boot partition Meant to be for booting on Bios systems.

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
