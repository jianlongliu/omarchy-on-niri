#!/bin/sh
# Install the Omarchy greeter system-wide.
#
#   sudo ./install.sh
#
# Copies the shell to /etc/greetd/omarchy-greeter (world readable: the greeter
# user has to read it) and installs /usr/local/bin/omarchy-greeter as greetd's
# session command. It never touches /etc/greetd/config.toml: switching greetd
# over to this greeter is the one step that can lock you out, so it is printed
# at the end for you to do at a TTY.
set -eu

SRC=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEST=/etc/greetd/omarchy-greeter

[ "$(id -u)" -eq 0 ] || {
  echo "run me with sudo" >&2
  exit 1
}

# 1. the shell itself
install -d -m 755 "$DEST" "$DEST/bridge"
for file in shell.qml Greetd.qml Users.qml UserPicker.qml SelfTest.qml niri.kdl; do
  install -m 644 "$SRC/$file" "$DEST/$file"
done
for dir in designs Commons Ui; do
  install -d -m 755 "$DEST/$dir"
  for file in "$SRC/$dir"/*; do
    install -m 644 "$file" "$DEST/$dir/$(basename "$file")"
  done
done
install -m 755 "$SRC/bridge/greetd-bridge.py" "$DEST/bridge/greetd-bridge.py"
chmod -R a+rX "$DEST"

# 2. greetd's session command for the greeter
cat > /usr/local/bin/omarchy-greeter <<'EOF'
#!/bin/sh
# greetd entry point for the Omarchy greeter: run the greeter's own niri
# instance. Login user, session and wallpaper are the GREETER_* values in
# /etc/greetd/omarchy-greeter/niri.kdl.
exec niri -c /etc/greetd/omarchy-greeter/niri.kdl
EOF
chmod 755 /usr/local/bin/omarchy-greeter

# 3. theme sync command
install -m 755 "$SRC/sync.sh" /usr/local/bin/omarchy-greeter-sync

# 4. the greeter user's state (its HOME is /var/lib/greeter)
install -d -m 755 -o greeter -g greeter /var/lib/greeter/.local/state/omarchy-greeter
install -d -m 755 -o greeter -g greeter /var/lib/greeter/.local/state/omarchy/current/theme
install -d -m 755 -o greeter -g greeter /var/lib/greeter/.config/omarchy
install -d -m 755 -o greeter -g greeter /var/lib/greeter/users

cat <<'EOF'

Installed. What is left is the part that can lock you out of the machine:

  1. Keep a TTY open (Ctrl+Alt+F2) and log in there.
  2. Put this in /etc/greetd/config.toml:

         [default_session]
         command = "/usr/local/bin/omarchy-greeter"
         user = "greeter"

     (dms-greeter may have left the previous value in
     /etc/greetd/config.toml.backup-* — keep it, it is the rollback.)
  3. Log out and log in. If the greeter does not come up, use the TTY and put
     the previous command back.
  4. Give the login screen the current theme and wallpaper:

         sudo omarchy-greeter-sync

  5. Only once logins work, and only if you want the DMS greeter gone:

         sudo pacman -D --asexplicit quickshell        # so -Rns cannot take quickshell with it
         sudo pacman -Rns greetd-dms-greeter-bin

Test the shell without logging out first:

    ./tests/smoke.sh
EOF
