# Fedora SecuriTUI — TUI Tool Manager

An interactive bash menu (`whiptail` / `dialog`) for running diagnostic, security and pentest tools on **Fedora KDE**.

Start it with one letter: **`m`**

Open source under **GPL-2.0-or-later** (`LICENSE`).
Article (Czech): <https://svec-elektro.cz/projekty/fedora-securitui/>

*Public snapshot — development happens in a private repository; the commit history is squashed here.*

## Screenshots

| Main menu | Recon & Scanning |
|---|---|
| ![Main menu](docs/screenshots/fedora-stui-main.png) | ![Recon & Scanning](docs/screenshots/fedora-stui-recon.png) |

---

## Project structure

```
TUIFedora/
├── menu.sh                  # main TUI menu
├── install-pentest-tools.sh # installs the CLI packages (dnf + pipx)
├── setup.sh                 # alias m + symlinks into $HOME
├── config/
│   └── dialogrc             # dark theme for dialog
└── README.md
```

---

## Quick install

```bash
# Unpack the ZIP and go into the project folder
cd ~/Downloads/TUIFedora   # or wherever you unpacked the archive

# 1) Install the tools (optional, one-off)
bash install-pentest-tools.sh

# 2) Set up the m alias
bash setup.sh

# 3) Start the menu (in a new terminal)
m
```

Download: [svec-elektro.cz/projekty/tuifedora](https://svec-elektro.cz/projekty/tuifedora/) (Czech)

---

## Main menu — categories

| # | Section | Contents |
|---|--------|--------|
| 1 | Recon & Scanning | nmap, masscan, arp-scan, tshark, tcpdump, TLS, DNS, Wireshark |
| 2 | Web App Testing | ffuf, gobuster, whatweb, wafw00f, nuclei, subfinder, sqlmap |
| 3 | Passwords & Authentication | hydra, medusa, ncrack, john, hashcat |
| 4 | System processes | strace, ltrace, GDB |
| 5 | Reverse & Binary | radare2, checksec, binwalk, yara, strings, objdump |
| 6 | Wireless | aircrack-ng suite, hcxpcapngtool |
| 7 | Security & Forensics | lynis, Sleuthkit, AIDE, rkhunter, ClamAV, volatility3, foremost |
| 8 | SMB / Impacket | smbclient, impacket scripts (lab) |
| 9 | Proxy / OpSec | proxychains, tor |
| 10 | OSINT — people | holehe, maigret, sherlock, phoneinfoga, socid_extractor, cupp |
| 11 | Network utilities | ss, ncat, socat, curl, ip, nft, openssl, docker |
| 12 | Background scripts | ps aux \| grep .sh/.py |

---

## Dependencies

**TUI (required):**
```bash
sudo dnf install -y dialog newt    # dialog is preferred, whiptail as a fallback
```

**Pentest packages:** see `install-pentest-tools.sh`

**OSINT (pipx / ~/.local/bin):**
- holehe, maigret, phoneinfoga, socid_extractor, cupp
- sherlock (dnf)

---

## Appearance (dark theme)

- Terminal and window background: **black**
- Text: **white**, borders and titles: **red**
- Active menu item: **white on red**
- Buttons (dialog): inactive = red text, active = **black on white**

Theme: `config/dialogrc` is copied to `~/.config/menu/dialogrc` at startup

Whiptail colours: the `NEWT_COLORS` variable in `menu.sh`

---

## Development

1. Clone the repository: `git clone https://github.com/pauliquib/Fedora-SecuriTUI.git && cd Fedora-SecuriTUI`
2. Edit `menu.sh` or `config/dialogrc` in any editor
3. Test: `bash menu.sh` or `m` (after `setup.sh`)

After changing `config/dialogrc`, just restart the menu; the file is synchronised automatically.

---

## The m alias

| Shell | File |
|-------|--------|
| Fish (default) | `~/.config/fish/config.fish` |
| Bash | `~/.bashrc` |

`setup.sh` points the alias at the absolute path of `menu.sh` in this project.

---

## Legal notice

Use the pentest and OSINT tools **only** on systems where you have **written permission**, or in **your own lab**. The author of the menu is not responsible for misuse.

---

## Troubleshooting

| Problem | Solution |
|---------|--------|
| The menu does not start after installing dialog | Fixed in `config/dialogrc` — run `setup.sh` again |
| Light background | Use `dialog` (not whiptail): `sudo dnf install dialog` |
| A tool is missing from the menu | `bash install-pentest-tools.sh` |
| The m alias does not work | `bash setup.sh` and open a new terminal |
