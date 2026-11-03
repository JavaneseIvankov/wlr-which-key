#!/usr/bin/env bash
# Build this checkout of wlr-which-key and install the binary onto the system.
#
#   ./install.sh                          # release build -> ~/.local/bin/wlr-which-key
#   ./install.sh --no-build               # install the existing target/release binary
#   ./install.sh --dest /usr/local/bin    # system-wide (sudo is used when needed)
#   ./install.sh --debug                  # install the debug build instead
#   ./install.sh --uninstall              # remove the installed binary
set -euo pipefail

src_dir="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
dest_dir="${WLK_DEST:-$HOME/.local/bin}"
profile=release
do_build=1
do_uninstall=0

usage() {
  sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; /^$/d'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dest)      dest_dir="${2:?--dest requires a directory}"; shift 2 ;;
    --dest=*)    dest_dir="${1#*=}"; shift ;;
    --no-build)  do_build=0; shift ;;
    --debug)     profile=debug; shift ;;
    --uninstall) do_uninstall=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) printf 'error: unknown argument: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

dest="$dest_dir/wlr-which-key"

# True when the directory (or its closest existing ancestor) is writable by us.
dir_writable() {
  local d="$1"
  while [ ! -e "$d" ]; do d="$(dirname -- "$d")"; done
  [ -w "$d" ]
}

# Run a command as root only when the destination is not writable by the user.
as_root() {
  local dir="$1"
  shift
  if dir_writable "$dir"; then "$@"; else sudo "$@"; fi
}

if [ "$do_uninstall" = 1 ]; then
  if [ ! -e "$dest" ]; then
    printf '==> %s is not installed, nothing to do\n' "$dest"
    exit 0
  fi
  as_root "$dest_dir" rm -f -- "$dest"
  printf '==> removed %s\n' "$dest"
  exit 0
fi

if [ ! -f "$src_dir/Cargo.toml" ]; then
  printf 'error: no Cargo.toml in %s\n' "$src_dir" >&2
  exit 1
fi

bin="$src_dir/target/$profile/wlr-which-key"

if [ "$do_build" = 1 ]; then
  command -v cargo >/dev/null || { printf 'error: cargo not found in PATH\n' >&2; exit 1; }
  printf '==> building (%s)\n' "$profile"
  if [ "$profile" = release ]; then
    (cd "$src_dir" && cargo build --release --locked)
  else
    (cd "$src_dir" && cargo build --locked)
  fi
elif [ ! -x "$bin" ]; then
  printf 'error: %s does not exist, drop --no-build\n' "$bin" >&2
  exit 1
fi

[ -x "$bin" ] || { printf 'error: %s is not executable\n' "$bin" >&2; exit 1; }

# Install via a temp file + rename so a running instance is never truncated
# (writing to a running executable fails with ETXTBSY).
tmp="${dest_dir}/.wlr-which-key.$$.tmp"
cleanup() { [ -e "$tmp" ] && as_root "$dest_dir" rm -f -- "$tmp" || true; }
trap cleanup EXIT

as_root "$dest_dir" install -d -- "$dest_dir"
as_root "$dest_dir" install -m 755 -- "$bin" "$tmp"
as_root "$dest_dir" mv -f -- "$tmp" "$dest"

printf '==> installed %s\n' "$dest"
printf '    version: %s\n' "$("$dest" --version 2>&1 | head -n1)"
printf '    sha256:  %s\n' "$(sha256sum -- "$dest" | cut -d' ' -f1)"

if git -C "$src_dir" rev-parse --git-dir >/dev/null 2>&1; then
  printf '    commit:  %s\n' "$(git -C "$src_dir" log -1 --pretty='%h %s')"
fi

resolved="$(command -v wlr-which-key || true)"
if [ "$resolved" != "$dest" ]; then
  printf '\nnote: "wlr-which-key" resolves to %s\n' "${resolved:-<not in PATH>}"
  printf '      put %s earlier in PATH, or call %s directly.\n' "$dest_dir" "$dest"
fi
