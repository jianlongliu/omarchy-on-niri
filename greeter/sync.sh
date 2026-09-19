#!/bin/sh
# Give the greeter the artwork of every human account, so the login screen
# looks like the account that is selected (startup = the last account that
# logged in).
#
#   sudo omarchy-greeter-sync                    # every human account, default = $SUDO_USER
#   sudo omarchy-greeter-sync jianlongliu yvonne # just these, first one is also the default
#
# Layout under /var/lib/greeter:
#
#   .local/state/omarchy/current/theme/   shared default palette (also the path
#   wallpaper                             Color.qml falls back to)
#   .config/omarchy/shell.toml            machine-level look (fonts, spacing)
#   users/<user>/theme                    that account's palette
#   users/<user>/wallpaper                that account's wallpaper
#
# Accounts that never ran Omarchy get symlinks to the shared default instead.
# The greeter's HOME is /var/lib/greeter and /data is not readable by the
# greeter user, so artwork is copied, not linked, apart from those fallbacks.
#
# What follows the account: colours and wallpaper. What is machine-level and
# comes from the default account: everything else in shell.toml.
set -eu

[ "$(id -u)" -eq 0 ] || exec sudo -- "$0" "$@"

dest=/var/lib/greeter
shared_theme="$dest/.local/state/omarchy/current/theme"

install -d -m 755 -o greeter -g greeter "$shared_theme" "$dest/users" \
  "$dest/.config/omarchy" "$dest/.local/state/omarchy-greeter"

find_background() { # state dir — echoes the active wallpaper, if any
  for candidate in "$1/background" "$1/theme/backgrounds/background"; do
    if [ -e "$candidate" ]; then
      readlink -f "$candidate"
      return 0
    fi
  done
  return 1
}

sync_user() { # user — that account's palette + wallpaper
  user=$1
  home=$(getent passwd "$user" | cut -d: -f6)
  [ -n "$home" ] || {
    echo "no such user: $user" >&2
    return 1
  }
  state="$home/.local/state/omarchy/current"
  root="$dest/users/$user"
  install -d -m 755 -o greeter -g greeter "$root"

  what="default artwork only"
  copied=""
  if [ -d "$state/theme" ]; then
    rm -rf "$root/theme"
    install -d -m 755 -o greeter -g greeter "$root/theme"
    for name in colors.toml shell.toml; do
      if [ -r "$state/theme/$name" ]; then
        install -m 644 "$state/theme/$name" "$root/theme/$name"
        copied=yes
      fi
    done
    [ -n "$copied" ] && what="theme $(basename "$(readlink -f "$state/theme")")"
  fi
  [ -d "$root/theme" ] || ln -sfn "$shared_theme" "$root/theme"

  background=$(find_background "$state" || true)
  if [ -n "$background" ]; then
    install -m 644 -L "$background" "$root/wallpaper"
    what="$what + wallpaper"
  else
    ln -sfn "$dest/wallpaper" "$root/wallpaper"
  fi
  chown -h greeter:greeter "$root/theme" "$root/wallpaper" 2>/dev/null || true

  echo "$user: $what"
}

set_default() { # user — what accounts without their own artwork fall back to
  home=$(getent passwd "$1" | cut -d: -f6)
  state="$home/.local/state/omarchy/current"
  for name in colors.toml shell.toml; do
    [ -r "$state/theme/$name" ] && install -m 644 "$state/theme/$name" "$shared_theme/$name"
  done
  background=$(find_background "$state" || true)
  [ -n "$background" ] && install -m 644 -L "$background" "$dest/wallpaper"
  [ -r "$home/.config/omarchy/shell.toml" ] && \
    install -m 644 "$home/.config/omarchy/shell.toml" "$dest/.config/omarchy/shell.toml"
  echo "shared default: $1"
}

if [ "$#" -gt 0 ]; then
  users=$*
  default=$1
else
  users=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 { print $1 }')
  default=${SUDO_USER:-$(echo "$users" | head -1)}
fi

for user in $users; do
  sync_user "$user" || true
done

[ -n "$default" ] && set_default "$default"

echo "done — the login screen picks these up on its next start"
