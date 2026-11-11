# Nix package manager environment
if [ -d /nix/store ]; then
	export NIX_CONFIG="experimental-features = nix-command flakes"
	export NIX_PROFILES="/nix/var/nix/profiles/per-user/${USER:-root} /nix/var/nix/profiles/default"
	export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
	export NIX_SSHOPTS=
fi