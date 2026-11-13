# Nix package manager environment
if [ -d /nix/store ]; then
	export NIX_CONFIG="experimental-features = nix-command flakes"
	export NIX_PROFILES="/nix/var/nix/profiles/per-user/${USER:-root} /nix/var/nix/profiles/desktop /nix/var/nix/profiles/default"
	export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/desktop/bin:/nix/var/nix/profiles/default/bin:$PATH"
	# Make XFCE (and any future DE) find its .desktop entries and icons.
	export XDG_DATA_DIRS="/nix/var/nix/profiles/desktop/share:/usr/local/share:/usr/share${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
	export NIX_SSHOPTS=
fi
