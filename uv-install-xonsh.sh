#!/usr/bin/env sh
# uv-install-xonsh.sh — install an isolated xonsh using uv
set -eu

printf '\nStart\n\n'

# --------------------------------------------------------------------------
# 0. Configurable variables (can be overridden by env)
# --------------------------------------------------------------------------
TARGET_DIR="${TARGET_DIR:-${HOME}/.local/xonsh-env}"
PYTHON_VER="${PYTHON_VER:-3.12}"
XONSH_VER="${XONSH_VER:-xonsh[full]}"
PIP_INSTALL="${PIP_INSTALL:-}"
XONSHRC="${XONSHRC:-}"
UV_INSTALL_DIR="${UV_INSTALL_DIR:-}"  # empty = use default ~/.cargo/bin
UV_ISOLATED="${UV_ISOLATED:-no}"       # yes = install uv to TARGET_DIR/bin

printf 'Configuration\n'
printf '=============\n'
printf 'TARGET_DIR=%s\n' "$TARGET_DIR"
printf 'PYTHON_VER=%s\n' "$PYTHON_VER"
printf 'XONSH_VER=%s\n' "$XONSH_VER"
printf 'UV_ISOLATED=%s\n' "$UV_ISOLATED"
[ -n "$PIP_INSTALL" ] && printf 'PIP_INSTALL=%s\n' "$PIP_INSTALL"
[ -n "$XONSHRC" ] && printf 'XONSHRC=%s\n' "$XONSHRC"
printf '\n'

# --------------------------------------------------------------------------
# 1. Create workspace
# --------------------------------------------------------------------------
printf 'Creating directories...\n'
mkdir -p "$TARGET_DIR"                # the venv itself
mkdir -p "$TARGET_DIR/xbin"           # helper wrappers live here
cd "$TARGET_DIR"

# --------------------------------------------------------------------------
# 2. Install uv if missing
# --------------------------------------------------------------------------
UV_BIN=""
if command -v uv >/dev/null 2>&1; then
    UV_BIN=$(command -v uv)
    printf 'Found existing uv at: %s\n' "$UV_BIN"
else
    printf 'Installing uv...\n'
    
    if [ "$UV_ISOLATED" = "yes" ]; then
        # Install to TARGET_DIR for complete isolation
        mkdir -p "$TARGET_DIR/bin"
        if command -v curl >/dev/null 2>&1; then
            curl -LsSf https://astral.sh/uv/install.sh | sh -s -- --no-modify-path --install-dir "$TARGET_DIR/bin"
        elif command -v wget >/dev/null 2>&1; then
            wget -qO- https://astral.sh/uv/install.sh | sh -s -- --no-modify-path --install-dir "$TARGET_DIR/bin"
        else
            printf 'Error: Neither curl nor wget found\n' >&2
            exit 1
        fi
        UV_BIN="$TARGET_DIR/bin/uv"
        # Create convenience symlink in xbin
        ln -sf ../bin/uv "$TARGET_DIR/xbin/uv"
    else
        # Install to default location
        if command -v curl >/dev/null 2>&1; then
            curl -LsSf https://astral.sh/uv/install.sh | sh
        elif command -v wget >/dev/null 2>&1; then
            wget -qO- https://astral.sh/uv/install.sh | sh
        else
            printf 'Error: Neither curl nor wget found\n' >&2
            exit 1
        fi
        export PATH="$HOME/.cargo/bin:$PATH"
        UV_BIN="$HOME/.cargo/bin/uv"
    fi
fi

# Verify uv is available
if ! command -v "$UV_BIN" >/dev/null 2>&1; then
    printf 'Error: uv installation failed\n' >&2
    exit 1
fi

printf 'Using uv: %s\n' "$UV_BIN"
printf 'uv version: %s\n\n' "$("$UV_BIN" --version)"

# --------------------------------------------------------------------------
# 3. Create the Python interpreter + venv and install xonsh
# --------------------------------------------------------------------------
printf 'Creating venv with Python %s...\n' "$PYTHON_VER"
"$UV_BIN" venv --python "$PYTHON_VER" "$TARGET_DIR"

# Activate venv for package installation
. "$TARGET_DIR/bin/activate"

printf '\nInstalling %s...\n' "$XONSH_VER"
"$UV_BIN" pip install "$XONSH_VER"

if [ -n "$PIP_INSTALL" ]; then
    printf '\nInstalling additional packages: %s\n' "$PIP_INSTALL"
    # shellcheck disable=SC2086
    "$UV_BIN" pip install $PIP_INSTALL
fi

deactivate  # Done installing

# --------------------------------------------------------------------------
# 4. Helper scripts & shims
# --------------------------------------------------------------------------
printf '\nCreating helper scripts...\n'

# Main entry-points
ln -sf ../bin/xonsh "$TARGET_DIR/xbin/xonsh"
ln -sf ../bin/xonsh "$TARGET_DIR/xbin/xbin-xonsh"
ln -sf ../bin/python "$TARGET_DIR/xbin/xbin-python"
ln -sf ../bin/python "$TARGET_DIR/xbin/python"

# xpip → fast uv-powered pip inside the env
cat > "$TARGET_DIR/xbin/xpip" <<EOF
#!/usr/bin/env sh
exec "$UV_BIN" pip --python "$TARGET_DIR" "\$@"
EOF
chmod +x "$TARGET_DIR/xbin/xpip"

# pip wrapper using uv
cat > "$TARGET_DIR/xbin/pip" <<EOF
#!/usr/bin/env sh
exec "$UV_BIN" pip --python "$TARGET_DIR" "\$@"
EOF
chmod +x "$TARGET_DIR/xbin/pip"

# xenv → source the venv's activate in POSIX shells
cat > "$TARGET_DIR/xbin/xenv" <<EOF
# Run with: source xenv
[ "\${XONSH_MODE:-}" = "source" ] && exit 0  # ignore inside xonsh
. "$TARGET_DIR/bin/activate"
printf 'Activated xonsh environment at %s\n' "$TARGET_DIR"
EOF
chmod +x "$TARGET_DIR/xbin/xenv"

# xbin management scripts
cat > "$TARGET_DIR/xbin/xbin-add" <<EOF
#!/usr/bin/env sh
set -eu
if [ -z "\${1:-}" ]; then
    printf 'Usage: xbin-add <binary-name>\n' >&2
    exit 1
fi
if [ ! -f "$TARGET_DIR/bin/\$1" ]; then
    printf 'Error: %s not found in bin/\n' "\$1" >&2
    exit 1
fi
ln -sf ../bin/"\$1" "$TARGET_DIR/xbin/\$1"
ls -la "$TARGET_DIR/xbin/\$1"
EOF
chmod +x "$TARGET_DIR/xbin/xbin-add"

cat > "$TARGET_DIR/xbin/xbin-del" <<EOF
#!/usr/bin/env sh
set -eu
if [ -z "\${1:-}" ]; then
    printf 'Usage: xbin-del <binary-name>\n' >&2
    exit 1
fi
rm -i "$TARGET_DIR/xbin/\$@"
EOF
chmod +x "$TARGET_DIR/xbin/xbin-del"

cat > "$TARGET_DIR/xbin/xbin-list" <<EOF
#!/usr/bin/env sh
ls -1 "$TARGET_DIR/xbin" | grep -v '^xbin-' | sort
EOF
chmod +x "$TARGET_DIR/xbin/xbin-list"

cat > "$TARGET_DIR/xbin/xbin-venv" <<EOF
#!/usr/bin/env sh
ls -1 "$TARGET_DIR/bin/" | sort
EOF
chmod +x "$TARGET_DIR/xbin/xbin-venv"

# Alias for compatibility with mamba version
ln -sf xbin-venv "$TARGET_DIR/xbin/xbin-hidden"

# --------------------------------------------------------------------------
# 5. Optional: append extra lines to ~/.xonshrc
# --------------------------------------------------------------------------
if [ -n "$XONSHRC" ]; then
    printf '\nUpdating ~/.xonshrc...\n'
    printf '%s\n' "$XONSHRC" >> ~/.xonshrc
fi

# --------------------------------------------------------------------------
# 6. Done
# --------------------------------------------------------------------------
printf '\n'
printf 'Installation Complete!\n'
printf '====================\n'
printf 'TARGET_DIR: %s\n' "$TARGET_DIR"
printf 'PYTHON_VER: %s\n' "$PYTHON_VER"
printf 'UV_BIN: %s\n' "$UV_BIN"
printf '\n'

cat <<EOM
Next steps:

* Add xbin to the front of your PATH:

    echo 'export PATH=$TARGET_DIR/xbin:\$PATH' >> ~/.zshrc
    echo 'export PATH=$TARGET_DIR/xbin:\$PATH' >> ~/.bashrc
    
    Then restart your terminal and run: xonsh

* Or invoke xonsh directly:

    $TARGET_DIR/xbin/xonsh

* Available commands in xbin:
  - xonsh       : Start xonsh shell
  - python      : Python interpreter
  - pip/xpip    : Install packages (using uv)
  - xenv        : Activate venv in POSIX shells
  - xbin-add    : Add a binary from venv to xbin
  - xbin-del    : Remove a binary from xbin
  - xbin-list   : List all xbin entries
  - xbin-venv   : List all venv binaries

EOM

if [ "$UV_ISOLATED" = "yes" ]; then
    printf '\nNote: uv was installed in isolated mode at %s\n' "$UV_BIN"
fi
