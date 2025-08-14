#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# OptiScaler: fetch latest release ZIP and set up in CWD
# Tested on Linux (Proton/Wine) and WSL. Should also work on macOS (for packaging game dirs).
# Usage: run this script *from the target game directory* you want to install OptiScaler into.
# ============================================================

REPO="optiscaler/OptiScaler"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"

# -------- helpers --------
log() { printf "\033[1;36m[optiscaler]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[error]\033[0m %s\n" "$*"; }
confirm() { read -r -p "$1 [y/N]: " _ans; [[ "${_ans,,}" == "y" || "${_ans,,}" == "yes" ]]; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "Required command '$1' not found."
    echo "Please install it and re-run. On Fedora/Bazzite: sudo dnf install $1"
    echo "On Ubuntu/Debian: sudo apt-get install $1"
    exit 1
  }
}

# -------- preflight --------
need_cmd curl
need_cmd unzip
if ! command -v jq >/dev/null 2>&1; then
  warn "jq not found. Falling back to grep/sed parsing."
  USE_JQ=0
else
  USE_JQ=1
fi

GAME_DIR="$(pwd)"
log "Target directory: ${GAME_DIR}"

# Safety check: ensure we're not in $HOME or root of the drive by accident
case "$GAME_DIR" in
  "/"|"/root"|"$HOME") warn "This looks like a risky directory to install into: $GAME_DIR";;
esac

# -------- choose asset from latest release --------
log "Resolving latest release from GitHub: ${REPO}"

json="$(curl -fsSL "$API_URL")" || { err "Failed to contact GitHub API."; exit 1; }

if [[ $USE_JQ -eq 1 ]]; then
  tag=$(printf "%s" "$json" | jq -r '.tag_name // .name // "unknown"')
  asset_url=$(printf "%s" "$json" | jq -r '.assets[]?.browser_download_url | select(test("(?i)optiscaler.*\\.zip$"))' | head -n1)
  # Fallback: any .zip
  if [[ -z "${asset_url:-}" ]]; then
    asset_url=$(printf "%s" "$json" | jq -r '.assets[]?.browser_download_url | select(endswith(".zip"))' | head -n1)
  fi
else
  tag=$(printf "%s" "$json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
  asset_url=$(printf "%s" "$json" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | grep -i 'optiscaler.*\.zip' | head -n1)
  if [[ -z "${asset_url:-}" ]]; then
    asset_url=$(printf "%s" "$json" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | grep -i '\.zip$' | head -n1)
  fi
fi

if [[ -z "${asset_url:-}" ]]; then
  err "Could not find a downloadable .zip asset in the latest release."
  echo "Open the releases page and check assets manually:"
  echo "  https://github.com/${REPO}/releases"
  exit 1
fi

log "Latest tag: ${tag}"
log "Asset: ${asset_url}"

# -------- download --------
TMPDIR="$(mktemp -d)"
ZIP="${TMPDIR}/OptiScaler-${tag}.zip"

log "Downloading…"
curl -fL --retry 3 --retry-delay 2 -o "$ZIP" "$asset_url"

if [[ ! -s "$ZIP" ]]; then
  err "Downloaded file is empty."
  exit 1
fi

SHA256="$(sha256sum "$ZIP" | awk '{print $1}')"
log "Download complete. sha256: ${SHA256}"

# -------- extract into current directory --------
log "Extracting into: ${GAME_DIR}"
# Show a quick preview of top-level entries in the zip (without extracting) for user awareness
if unzip -l "$ZIP" | awk 'NR<=20{print} END{if (NR>20) print "..."}' >/dev/null 2>&1; then
  unzip -l "$ZIP" | awk 'NR<=20{print} END{if (NR>20) print "..."}'
fi

if [[ -e "${GAME_DIR}/nvngx.ini" || -e "${GAME_DIR}/OptiScaler.ini" || -e "${GAME_DIR}/dxgi.dll" || -e "${GAME_DIR}/nvngx.dll" ]]; then
  warn "Existing OptiScaler-related files found in this directory."
  if ! confirm "Overwrite existing files?"; then
    err "User aborted to prevent overwriting."
    exit 1
  fi
fi

unzip -o "$ZIP" -d "$GAME_DIR" >/dev/null

# -------- optional: help user choose loading mode --------
# OptiScaler can be loaded as one of several proxy DLLs. For broad compatibility,
# using dxgi.dll is common (per project release notes).
log "Would you like to install a proxy DLL alias for loading (e.g., dxgi.dll)?"
echo "  1) Yes, use dxgi.dll (recommended for many DX12 titles)"
echo "  2) Yes, use winmm.dll"
echo "  3) Yes, use version.dll"
echo "  4) No, leave files as extracted (advanced users)"
read -r -p "Choose [1-4]: " CHOICE
CHOICE="${CHOICE:-1}"

# Determine OptiScaler's primary DLL shipped in the archive (varies by mode).
# Search common names shipped by the project.
PRIMARY_DLL=""
for cand in nvngx.dll OptiScaler.dll OptiScaler.asi; do
  if [[ -f "${GAME_DIR}/${cand}" ]]; then
    PRIMARY_DLL="$cand"
    break
  fi
done

# If nvngx.dll is present, keep it. The alias we create is a *copy* of OptiScaler's DLL under a proxy name.
# This mirrors instructions in release notes recommending renaming OptiScaler to dxgi.dll for DLSS 3.7 override.
if [[ -n "$PRIMARY_DLL" ]]; then
  case "$CHOICE" in
    1) cp -f "${GAME_DIR}/${PRIMARY_DLL}" "${GAME_DIR}/dxgi.dll"; log "Created proxy: dxgi.dll";;
    2) cp -f "${GAME_DIR}/${PRIMARY_DLL}" "${GAME_DIR}/winmm.dll"; log "Created proxy: winmm.dll";;
    3) cp -f "${GAME_DIR}/${PRIMARY_DLL}" "${GAME_DIR}/version.dll"; log "Created proxy: version.dll";;
    *) log "Leaving files as-is." ;;
  esac
else
  warn "Could not locate a primary OptiScaler DLL in extracted files. Proceeding without proxy alias."
fi

# -------- create/update nvngx.ini with sane defaults if missing --------
INI="${GAME_DIR}/nvngx.ini"
if [[ ! -f "$INI" ]]; then
  cat > "$INI" <<'INI_EOF'
[General]
# Show in-game menu (INSERT by default). Disable if it conflicts.
OverlayMenu=true

# Auto-select upscaler if available. You can still change in-game.
PreferredUpscaler=Auto

# Optional: write logs next to the game .exe (or prefix dir in Proton)
LogLevel=Info

[Keys]
# You can customize the menu hotkey here if INSERT conflicts.
MenuKey=INSERT

[Linux]
# If RCAS/OutputScaling fails to compile shaders on Proton/Wine:
# install d3dcompiler_47 via protontricks/winetricks to fix.
# Proton:  protontricks <appid> -q d3dcompiler_47
# Wine:    winetricks -q d3dcompiler_47
INI_EOF
  log "Created default nvngx.ini"
else
  log "nvngx.ini already exists — leaving it untouched."
fi

# -------- uninstaller --------
UNINSTALL="${GAME_DIR}/remove_optiscaler.sh"
cat > "$UNINSTALL" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sel=( "dxgi.dll" "winmm.dll" "version.dll" "nvngx.dll" "OptiScaler.dll" "OptiScaler.asi" "nvngx.ini" "OptiScaler.ini" "OptiScaler.log" "D3D12_Optiscaler" "DlssOverrides" "Licenses" )
echo "This will remove OptiScaler files from the current directory: $(pwd)"
read -r -p "Proceed? [y/N]: " a
[[ "${a,,}" == "y" || "${a,,}" == "yes" ]] || { echo "Cancelled."; exit 0; }
for f in "${sel[@]}"; do
  if [[ -e "$f" ]]; then
    rm -rf -- "$f"
    echo "Removed: $f"
  fi
done
echo "Done."
EOF
chmod +x "$UNINSTALL"
log "Uninstaller created: ${UNINSTALL}"


# -------- optional: dxvk.conf creation for GPU spoof --------
log "Do you want to create a dxvk.conf file to spoof your GPU (e.g., RDNA3) for FSR4?"
echo "  1) Yes, spoof RDNA3 (AMD Radeon RX 7900 XTX)"
echo "  2) Yes, enter custom GPU name and ID"
echo "  3) No"
read -r -p "Choose [1-3]: " SPOOF_CHOICE
SPOOF_CHOICE="${SPOOF_CHOICE:-3}"

DXVK_CONF="${GAME_DIR}/dxvk.conf"

if [[ "$SPOOF_CHOICE" == "1" ]]; then
  cat > "$DXVK_CONF" <<'DXVK_EOF'
# dxvk.conf generated by OptiScaler setup script
# Spoof RDNA3 for enabling FSR4 (RX 7900 XTX)
dxgi.customVendorId = 0x1002
dxgi.customDeviceId = 0x744C
dxgi.customDeviceDesc = "AMD Radeon RX 7900 XTX"
DXVK_EOF
  log "dxvk.conf created to spoof RDNA3 (RX 7900 XTX)."
elif [[ "$SPOOF_CHOICE" == "2" ]]; then
  read -r -p "Enter vendor ID (e.g., 0x1002 for AMD, 0x10DE for NVIDIA): " VID
  read -r -p "Enter device ID (e.g., 0x744C for RX 7900 XTX): " DID
  read -r -p "Enter device description string: " DESC
  cat > "$DXVK_CONF" <<DXVK_EOF
# dxvk.conf generated by OptiScaler setup script
dxgi.customVendorId = ${VID}
dxgi.customDeviceId = ${DID}
dxgi.customDeviceDesc = "${DESC}"
DXVK_EOF
  log "dxvk.conf created with custom spoof: ${DESC} (${VID}:${DID})."
else
  log "Skipping dxvk.conf creation."
fi


# -------- dxvk.conf (optional GPU spoof) --------
make_dxvk_conf() {
  local cfg="${GAME_DIR}/dxvk.conf"
  log "DXVK per-game config can spoof GPU vendor/device IDs."
  log "This is commonly used to enable features like FSR4 in some titles."

  if ! confirm "Create or update dxvk.conf here for GPU spoofing?"; then
    log "Skipping dxvk.conf creation."
    return 0
  fi

  echo
  echo "Choose a preset or enter custom IDs:"
  echo "  1) AMD RDNA3 spoof — RX 7900 XTX (vendor 0x1002, device 0x744C)"
  echo "  2) AMD RDNA3 spoof — RX 7800 XT (vendor 0x1002, device 0x747F)"
  echo "  3) AMD RDNA3 spoof — RX 7700 XT (vendor 0x1002, device 0x7480)"
  echo "  4) Custom vendor/device IDs"
  echo "  5) No spoofing (write template with comments only)"
  read -r -p "Choose [1-5]: " pick
  pick="${pick:-1}"

  vendor=""; device=""
  case "$pick" in
    1) vendor="0x1002"; device="0x744C";;
    2) vendor="0x1002"; device="0x747F";;
    3) vendor="0x1002"; device="0x7480";;
    4)
      read -r -p "Enter vendor ID (hex like 0x1002 for AMD): " vendor
      read -r -p "Enter device ID (hex like 0x744C): " device
      ;;
    5) ;;
    *) vendor="0x1002"; device="0x744C";;
  esac

  {
    echo "# dxvk.conf generated by OptiScaler setup ($(date -u +"%Y-%m-%dT%H:%M:%SZ"))"
    echo "# Reference: https://github.com/doitsujin/dxvk/wiki/Configuration"
    echo
    if [[ -n "${vendor}" && -n "${device}" ]]; then
      echo "# GPU spoofing to unlock game-side feature paths (e.g., FSR4)."
      echo "dxgi.customVendorId = ${vendor}   # AMD=0x1002, NVIDIA=0x10DE, Intel=0x8086"
      echo "dxgi.customDeviceId = ${device}   # Device ID of the GPU to spoof"
      echo
    else
      echo "# No spoofing selected. You can add it later by uncommenting these lines:"
      echo "# dxgi.customVendorId = 0x1002"
      echo "# dxgi.customDeviceId = 0x744C"
      echo
    fi
    echo "# Optional quality/perf toggles (disabled by default):"
    echo "# d3d11.relaxedBarriers = True"
    echo "# dxgi.maxDeviceMemory = 4096"
    echo "# dxgi.maxSharedMemory = 8192"
  } > "$cfg"

  log "Wrote ${cfg}"
  echo "Steam (Proton) launch options hint including RDNA3 spoof (adjust path if needed):"
  echo '  DXVK_CONFIG_FILE="$PWD/dxvk.conf" DXIL_SPIRV_CONFIG=wmma_rdna3_workaround FSR4_UPGRADE=1 %command%'
}

# Invoke the dxvk.conf helper
make_dxvk_conf

# -------- finish --------
log "OptiScaler ${tag} installed into: ${GAME_DIR}"
echo "Next steps:"
echo "  • Launch the game and press INSERT to open the OptiScaler menu."
echo "  • If using Proton and you see shader compile errors about 'rcp', install d3dcompiler_47 (see nvngx.ini [Linux] notes)."
echo "  • For DLSS 3.7 titles without DLSS Enabler, using the dxgi.dll proxy is often required (selected above)."
