#!/bin/bash
# Contract test for the yay→paru shim, offline: `paru` is a stub in a temp dir, so
# nothing here can touch the AUR, the package cache, or pacman.
#
# Four checks, one per thing Omarchy's bin/ actually depends on:
#   1. argv reaches paru untouched (the four call sites pass yay's flags straight through)
#   2. `-Gp` gets yay's 4-line header back, so upstream's `yay -Gpa {1} | tail -n +5`
#      preview still shows the whole PKGBUILD (a plain `exec paru "$@"` shim eats 4 lines)
#   3. everything else is not wrapped
#   4. the shim parses
#
#   ./tests/test-yay-shim.sh
#
# checks=N failures=M, exit 1 on any failure.

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SHIM=$(dirname "$HERE")/yay
[[ -f $SHIM ]] || { echo "no shim at $SHIM"; exit 1; }

checks=0
failures=0
check() { # name got want
    checks=$((checks + 1))
    if [[ "$2" == "$3" ]]; then
        printf '  %-46s ok\n' "$1"
    else
        printf '  %-46s FAIL (got %s, want %s)\n' "$1" "$2" "$3"
        failures=$((failures + 1))
    fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/shimdir" "$tmp/fakebin"
install -m 0755 "$SHIM" "$tmp/shimdir/yay"

# The body has NO leading comments on purpose: that is the shape where a passthrough
# shim plus upstream's `tail -n +5` would lose real assignments.
export STUB_BODY=$'pkgname=zen\npkgver=1\npkgrel=1\narch=(\'any\')\n'
BODY=${STUB_BODY%$'\n'} # command substitution strips the trailing newline too

# --- fake paru ------------------------------------------------------------------
cat >"$tmp/fakebin/paru" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$STUB_LOG"
case " $* " in
*" -G "*|*" -Gp"*|*" --getpkgbuild "*) printf '%s' "$STUB_BODY" ;;
*) printf 'PASSTHROUGH:%s\n' "$*" ;;
esac
SH
chmod +x "$tmp/fakebin/paru"
export STUB_LOG="$tmp/paru.log"

YAY="$tmp/shimdir/yay"
runpath="$tmp/shimdir:$tmp/fakebin:/usr/bin:/bin"

# --- 1. the call sites' flags reach paru untouched ------------------------------
: >"$STUB_LOG"
PATH="$runpath" "$YAY" -S --noconfirm --needed foo bar >/dev/null
check "argv reaches paru untouched" "$(cat "$STUB_LOG")" "-S --noconfirm --needed foo bar"

# --- 2. `-Gp` header emulation --------------------------------------------------
check "upstream's tail -n +5 yields full PKGBUILD" \
    "$(PATH="$runpath" "$YAY" -Gpa zen | tail -n +5)" "$BODY"

# --- 3. nothing else gets a header ----------------------------------------------
check "-Slqa list verbatim (menu TUI)" "$(PATH="$runpath" "$YAY" -Slqa)" $'PASSTHROUGH:-Slqa'

bash -n "$SHIM" 2>/dev/null
check "shim parses (bash -n)" "$?" "0"

echo
echo "checks=$checks failures=$failures"
[[ $failures -eq 0 ]]
