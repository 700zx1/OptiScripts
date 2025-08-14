# OptiScaler Game Setup Scripts

Easily download and install the latest release of [OptiScaler](https://github.com/optiscaler/OptiScaler) into any game directory — with optional GPU spoofing for FSR4 and per-game configuration.

These scripts are designed to make it **simple** for Linux and Windows users to integrate OptiScaler into their games without having to manually download, rename, and configure files.

---

## ✨ Features

- **Auto-downloads the latest OptiScaler release** from GitHub
- Extracts directly into your **current game directory**
- **Proxy DLL setup** (e.g., `dxgi.dll`, `winmm.dll`, `version.dll`) for easy loading
- Creates a **default `nvngx.ini`** with sane settings
- Optional **`dxvk.conf` creation** to spoof GPU vendor/device IDs  
  → Includes presets for **RDNA3** GPUs (7900 XTX / 7800 XT / 7700 XT) to unlock FSR4 in supported games
- Adds an **uninstaller script** to cleanly remove all OptiScaler files

---

## 📦 Files

| File | Platform | Description |
|------|----------|-------------|
| `optiscaler_setup.sh` | **Linux** | Bash script for Linux users (Proton/Wine compatible) |
| `optiscaler_setup_windows.bat` | **Windows** | Batch script for Windows users |

---

## 🔧 Requirements

### Linux
- `bash` (already included in most distros)
- `curl`
- `unzip`
- `jq` *(optional — script will fall back to `grep`/`sed` parsing if missing)*

On Fedora / Bazzite:
```bash
sudo dnf install curl unzip jq
```

On Ubuntu / Debian:
```bash
sudo apt install curl unzip jq
```

---

### Windows
- **PowerShell** (included with Windows 10/11)
- Ability to run `.bat` scripts (may need to allow in execution policy)
- Internet connection to fetch GitHub release

---

## 🚀 Usage

### Linux
1. **Download the script**:
    ```bash
    curl -LO https://github.com/YOURNAME/OptiScaler-Setup/raw/main/optiscaler_setup.sh
    chmod +x optiscaler_setup.sh
    ```

2. **Navigate to your game directory**:
    ```bash
    cd /path/to/your/game
    ```

3. **Run the script**:
    ```bash
    ./optiscaler_setup.sh
    ```

4. Follow prompts to:
   - Choose a **proxy DLL**
   - Optionally create a `dxvk.conf` with GPU spoofing

---

### Windows
1. **Download** `optiscaler_setup_windows.bat` from the repo.
2. Place it **in your game directory** (same folder as your game `.exe`).
3. **Double-click** to run, or right-click → **Run as Administrator** (if required).
4. Follow prompts to:
   - Choose a **proxy DLL**
   - Optionally create a `dxvk.conf` with GPU spoofing

---

## 📝 `dxvk.conf` GPU Spoofing

The scripts can create a `dxvk.conf` that **spoofs your GPU** to a supported RDNA3 model, enabling **FSR4** in games that check GPU capability.

**Presets included:**
- AMD RX 7900 XTX → `Vendor ID: 0x1002`, `Device ID: 0x744C`
- AMD RX 7800 XT → `Vendor ID: 0x1002`, `Device ID: 0x747F`
- AMD RX 7700 XT → `Vendor ID: 0x1002`, `Device ID: 0x7480`
- Custom IDs → enter any Vendor/Device hex values

To use with **Proton**:
```bash
DXVK_CONFIG_FILE="$PWD/dxvk.conf" %command%
```

---

## 🔄 Updating OptiScaler

Just re-run the setup script in the game folder — it will fetch the latest release and replace existing files (after asking for confirmation).

---

## ❌ Uninstalling

Both scripts create a **removal script** in your game directory:

- Linux: `remove_optiscaler.sh`
- Windows: `remove_optiscaler.bat`

Run it to delete all OptiScaler-related files and configs.

---

## ⚠️ Notes & Tips

- If using Proton and you see shader compile errors mentioning `rcp` or RCAS, install `d3dcompiler_47` via:
    ```bash
    protontricks <appid> -q d3dcompiler_47
    ```
- For DLSS 3.7 titles without DLSS Enabler, you may need to use the `dxgi.dll` proxy option.
- Always back up your game directory before replacing files.

---

## 📜 License

These scripts are released under the **MIT License** — feel free to modify and share, but credit is appreciated.

---

## ❤️ Credits

- [OptiScaler Project](https://github.com/optiscaler/OptiScaler) for the upscaling technology.
- Script author: **YOUR NAME** — making OptiScaler setup easier for everyone!
