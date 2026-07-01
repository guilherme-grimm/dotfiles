#!/bin/sh
# setup.sh — install dotfiles via symlinks (POSIX sh, any unix)
#
# Usage:
#   ./setup.sh            link everything (back up any pre-existing files)
#   ./setup.sh -f         relink even if an existing symlink points elsewhere
#   ./setup.sh --dry-run  print what would happen, change nothing
#
# Cloning on a fresh machine:
#   git clone <dotfiles> ~/dotfiles && ~/dotfiles/setup.sh
#
# After linking, open nvim once so lazy.nvim bootstraps plugins:
#   nvim --headless "+Lazy! sync" +qa   (optional)

set -u

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
FORCE=0
DRY=0

for arg in "$@"; do
	case "$arg" in
		-f|--force)  FORCE=1 ;;
		--dry-run|-n) DRY=1 ;;
		-h|--help)
			sed -n '2,12p' "$0"; exit 0 ;;
		*) printf 'unknown arg: %s\n' "$arg" >&2; exit 2 ;;
	esac
done

TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/.dotfiles-backup-$TS"

# link <source_in_dotfiles> <link_path_in_home>
link() {
	src=$1
	dst=$2

	if [ ! -e "$src" ] && [ ! -L "$src" ]; then
		printf '  skip (source missing): %s\n' "$src"
		return 0
	fi

	mkdir -p "$(dirname "$dst")"

	if [ -L "$dst" ]; then
		cur=$(readlink "$dst")
		# normalize: resolve to absolute for comparison
		case "$cur" in
			/*) : ;;
			*) cur="$(cd "$(dirname "$dst")" && cd "$(dirname "$cur")" && pwd)/$(basename "$cur")" ;;
		esac
		if [ "$cur" = "$src" ] && [ "$FORCE" -eq 0 ]; then
			printf '  ok:   %s -> %s\n' "$dst" "$src"
			return 0
		fi
		[ "$DRY" -eq 1 ] || rm "$dst"
		printf '  relink: %s (was -> %s)\n' "$dst" "$cur"
	elif [ -e "$dst" ]; then
		[ "$DRY" -eq 1 ] || { mkdir -p "$BACKUP_DIR"; mv "$dst" "$BACKUP_DIR/"; }
		printf '  backup: %s -> %s\n' "$dst" "$BACKUP_DIR"
	fi

	[ "$DRY" -eq 1 ] || ln -s "$src" "$dst"
	printf '  link: %s -> %s\n' "$dst" "$src"
}

printf '== dotfiles setup ==\n'
printf 'repo:   %s\n' "$DOTFILES"
[ "$DRY" -eq 1 ]    && printf 'mode:   DRY-RUN (no changes)\n'
[ "$FORCE" -eq 1 ]  && printf 'mode:   force relink\n'
printf '\n[hypr]\n'
link "$DOTFILES/hypr" "$HOME/.config/hypr"

printf '\n[waybar]\n'
link "$DOTFILES/waybar" "$HOME/.config/waybar"

printf '\n[nvim]\n'
link "$DOTFILES/nvim" "$HOME/.config/nvim"

printf '\n[pi: config]\n'
link "$DOTFILES/pi/AGENTS.md"        "$HOME/.pi/agent/AGENTS.md"
link "$DOTFILES/pi/settings.json"   "$HOME/.pi/agent/settings.json"
link "$DOTFILES/pi/web-search.json" "$HOME/.pi/web-search.json"

printf '\n[pi: extensions]\n'
link "$DOTFILES/pi/extensions/teacher-mode.ts"      "$HOME/.pi/agent/extensions/teacher-mode.ts"
link "$DOTFILES/pi/extensions/local-web-search.ts"  "$HOME/.pi/agent/extensions/local-web-search.ts"
link "$DOTFILES/pi/extensions/task-modes"            "$HOME/.pi/agent/extensions/task-modes"

printf '\n== done ==\n'
if [ "$DRY" -eq 0 ]; then
	if [ -d "$BACKUP_DIR" ]; then
		printf 'pre-existing files backed up to: %s\n' "$BACKUP_DIR"
	fi
	printf 'Tip: open nvim once to let lazy.nvim install plugins:\n'
	printf '  nvim --headless "+Lazy! sync" +qa\n'
fi
