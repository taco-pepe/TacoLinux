import shutil
import subprocess
from pathlib import Path

PREP = Path("/mnt/prep")


def run(command):
    return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT).strip()


def get_uuid(dev):
    return run(["blkid", "-s", "UUID", "-o", "value", dev])


print("=== TacoLinux install ===")

root_dev = input("Root partition: ").strip()
boot_dev = input("Boot partition: ").strip()
swap_dev = input("Swap partition: ").strip()
disk = input("Target disk (e.g. /dev/sda): ").strip()

root_uuid = get_uuid(root_dev)
boot_uuid = get_uuid(boot_dev)

# Check that the boot partition is mounted.
if not Path("/mnt/prep/boot").is_dir():
    raise SystemExit("ERROR: /mnt/prep/boot does not exist!")

# import subprocess

# sync rootfs with disk.
subprocess.run(["rsync", "-aHAX", "--", "./rootfs/", "/mnt/prep/"], check=True)

# Generate GRUB configuration.
grub_config = f"""\
set timeout=3
set default=0

menuentry "TacoLinux :D (release)" {{
    echo "we in"
    echo "bootin your system :D"
    search --no-floppy --fs-uuid --set=root {boot_uuid}
    linux /bzImage root=UUID={root_uuid} rw rootfstype=ext4 console=tty0 console=tty0,115200
    initrd /initramfs.img
}}
"""

grub_dir = PREP / "boot/grub"
grub_dir.mkdir(parents=True, exist_ok=True)
(grub_dir / "grub.cfg").write_text(grub_config)

# Generate systemd swap unit.
swap_unit = run(["systemd-escape", "--path", "--suffix=swap", swap_dev])
print("rootfs Synced!")

swap_config = f"""\
[Unit]
Description=TacoLinux Swap

[Swap]
What={swap_dev}

[Install]
WantedBy=swap.target
"""

systemd_dir = PREP / "etc/systemd/system"
systemd_dir.mkdir(parents=True, exist_ok=True)

(systemd_dir / swap_unit).write_text(swap_config)

# Enable swap unit in the installed system.
wants = systemd_dir / "swap.target.wants"
wants.mkdir(parents=True, exist_ok=True)

link = wants / swap_unit
if not link.exists():
    link.symlink_to(f"../{swap_unit}")

# Install BIOS GRUB to the target disk.
subprocess.run(
    ["grub-install", "--target=i386-pc", f"--boot-directory={PREP}/boot", disk],
    check=True,
)

print("TacoLinux GRUB configuration generated!")
print("Swap unit installed!")
print("GRUB installed successfully!")

# Copy the kernel and initramfs into the installed boot partition.
for name in ("bzImage", "initramfs.img"):
    shutil.copy2(Path("bootstrap") / name, PREP / "boot" / name)
print("kernel and initramfs copied!")
