#!/usr/bin/env bash
# menu.sh — TUI správce diagnostických a bezpečnostních nástrojů
# Spouštění: alias m  nebo  ./menu.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="${SCRIPT_DIR}/install-pentest-tools.sh"

BACKTITLE="Správce Nástrojů — CyberSec / Pentest Lab"
DEFAULT_WORDLIST="${HOME}/wordlists/SecLists/Discovery/Web-Content/common.txt"
FALLBACK_WORDLIST="/usr/share/dict/words"

# Tmavé TUI — celé okno černé (whiptail neumí tmavě modrou, jen zářivou blue)
# Neaktivní tlačítka: červený text | aktivní: černý text na bílém (inverze)
export NEWT_COLORS='root=white,black window=white,black border=red,black title=red,black button=red,black actbutton=black,white compactbutton=red,black checkbox=white,black actcheckbox=white,red entry=white,black label=white,black listbox=white,black actlistbox=white,red textbox=white,black disentry=lightgray,black shadow=black,black helpline=white,black roottext=white,black fullshadow=black,black'

setup_dark_terminal() {
  if [[ -t 1 ]]; then
    printf '\033[40m\033[37m\033[2J\033[H'
  fi
}

restore_terminal() {
  if [[ -t 1 ]]; then
    printf '\033[0m\033[2J\033[H'
  fi
}

trap restore_terminal EXIT INT TERM
setup_dark_terminal

# dialog — téma z config/dialogrc (kopie do ~/.config/menu/)
MENU_DIALOGRC="${HOME}/.config/menu/dialogrc"
mkdir -p "${HOME}/.config/menu"
if [[ -f "${SCRIPT_DIR}/config/dialogrc" ]]; then
  cp "${SCRIPT_DIR}/config/dialogrc" "$MENU_DIALOGRC"
else
  echo "Chyba: chybí ${SCRIPT_DIR}/config/dialogrc" >&2
  exit 1
fi

# dialog = spolehlivější barvy tlačítek; whiptail = záloha
if command -v dialog >/dev/null 2>&1; then
  DIALOG=(dialog --colors --no-shadow)
  export DIALOGRC="$MENU_DIALOGRC"
elif command -v whiptail >/dev/null 2>&1; then
  DIALOG=(whiptail)
else
  echo "Chyba: nainstalujte dialog (sudo dnf install dialog) nebo whiptail (newt)." >&2
  exit 1
fi

# Volání TUI — zachytí chybu dialogrc a přepne na whiptail
run_dialog() {
  local result rc
  result=$("${DIALOG[@]}" "$@" 3>&1 1>&2 2>&3)
  rc=$?
  rewrap_terminal_dark
  if (( rc != 0 )) && [[ "$result" == *"unknown variable"* || "$result" == *"dlg_parse"* ]]; then
    echo "Chyba dialog: $result" >&2
    if [[ "${DIALOG[0]}" == "dialog" ]] && command -v whiptail >/dev/null 2>&1; then
      echo "Přepínám na whiptail…" >&2
      DIALOG=(whiptail)
      unset DIALOGRC
      result=$("${DIALOG[@]}" "$@" 3>&1 1>&2 2>&3)
      rc=$?
      rewrap_terminal_dark
    fi
  fi
  if (( rc != 0 )); then
    return "$rc"
  fi
  printf '%s' "$result"
  return 0
}

rewrap_terminal_dark() {
  if [[ -t 1 ]]; then
    printf '\033[40m\033[37m'
  fi
}

MENU_HELP_HINT=$'\n\n↑↓ navigace | Enter = výběr | F1 = nápověda'

menu_help_for_tag() {
  local tag="$1"
  shift
  local -a items=("$@")
  local i=0
  while (( i + 2 < ${#items[@]} )); do
    if [[ "${items[i]}" == "$tag" ]]; then
      printf '%s' "${items[i+2]}"
      return 0
    fi
    (( i += 3 ))
  done
  return 1
}

show_help_box() {
  local title="$1" text="$2"
  local lines h
  lines=$(printf '%s\n' "$text" | wc -l | tr -d ' ')
  h=$(( lines + 6 ))
  (( h < 10 )) && h=10
  (( h > 24 )) && h=24
  run_dialog --title "Nápověda" --backtitle "$BACKTITLE" \
    --scrolltext --msgbox "$text" "$h" 72 || true
  rewrap_terminal_dark
}

# run_menu title prompt height width listheight tag label help ...
run_menu() {
  local title="$1" prompt="$2" height="$3" width="$4" listheight="$5"
  shift 5
  local -a items=("$@")
  local prompt_full="${prompt}${MENU_HELP_HINT}"

  while true; do
    local choice rc help_tag help_text

    if [[ "${DIALOG[0]}" == "dialog" ]]; then
      choice=$("${DIALOG[@]}" --title "$title" --backtitle "$BACKTITLE" \
        --item-help --help-button --help-label "Nápověda (F1)" --help-status \
        --menu "$prompt_full" "$height" "$width" "$listheight" \
        "${items[@]}" 3>&1 1>&2 2>&3)
      rc=$?
      rewrap_terminal_dark

      if (( rc == 2 )); then
        help_tag=$(printf '%s\n' "$choice" | awk 'END{print}' | tr -d '\r')
        help_text=$(menu_help_for_tag "$help_tag" "${items[@]}") || help_text=""
        if [[ -n "$help_text" ]]; then
          show_help_box "$title" "$help_text"
        fi
        continue
      fi
      if (( rc != 0 )); then
        return 1
      fi
      printf '%s' "$choice"
      return 0
    fi

    local -a wt_items=()
    local i=0
    while (( i + 2 < ${#items[@]} )); do
      wt_items+=("${items[i]}" "${items[i+1]}")
      (( i += 3 ))
    done
    choice=$("${DIALOG[@]}" --title "$title" --backtitle "$BACKTITLE" \
      --menu "${prompt_full} (F1 vyžaduje dialog)" "$height" "$width" "$listheight" \
      "${wt_items[@]}" 3>&1 1>&2 2>&3) || return 1
    rewrap_terminal_dark
    printf '%s' "$choice"
    return 0
  done
}

pause_return() {
  rewrap_terminal_dark
  echo
  echo -e "\033[38;5;196m\033[1m▸\033[0m \033[97mStiskněte Enter pro návrat do menu...\033[0m"
  read -r _
}

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Příkaz '$cmd' není nainstalován."
    echo "Spusťte: bash \"${INSTALL_SCRIPT}\""
    return 1
  fi
  return 0
}

ask_input() {
  # usage: ask_input "title" "prompt" [default]
  local title="$1" prompt="$2" def="${3:-}"
  run_dialog --title "$title" --backtitle "$BACKTITLE" \
    --inputbox "$prompt" 12 72 "$def"
}

pick_wordlist() {
  local wl="$DEFAULT_WORDLIST"
  [[ -f "$wl" ]] || wl="$FALLBACK_WORDLIST"
  ask_input "Wordlist" "Cesta k wordlistu:" "$wl"
}

run_sudo_or_plain() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

# =============================================================================
# 1) Recon & Scanning
# =============================================================================

nmap_scanner() {
  need_cmd nmap || { pause_return; return; }
  local target scan_type
  target=$(ask_input "Nmap" "Cíl (IP / hostname / rozsah, např. 192.168.1.0/24):") || return
  target="${target//[[:space:]]/}"
  [[ -n "$target" ]] || { echo "Cíl nebyl zadán."; pause_return; return; }

  scan_type=$(run_menu "Typ skenu" "Nmap → $target" 16 70 6 \
    "1" "Rychlý sken (-F)" "Rychlý sken (-F): top 100 portů. Bez root." \
    "2" "Ping sken (-sn)" "Ping sken (-sn): zjistí aktivní hosty bez port scanu." \
    "3" "Kompletní audit (-A)" "Kompletní audit (-A): OS detekce, skripty, traceroute. Vyžaduje sudo." \
    "4" "Syn sken + verze (-sS -sV)" "SYN sken + verze služeb (-sS -sV). Stealth, vyžaduje sudo." \
    "5" "UDP sken (-sU --top-ports 20)" "UDP sken top 20 portů. Pomalý, vyžaduje sudo." \
    "6" "Skriptový vuln sken (--script=vuln)" "NSE skript vuln: hledá známé zranitelnosti. Vyžaduje sudo."
  ) || return

  local -a args=()
  local need_root=0
  case "$scan_type" in
    1) args=(-F) ;;
    2) args=(-sn) ;;
    3) args=(-A); need_root=1 ;;
    4) args=(-sS -sV); need_root=1 ;;
    5) args=(-sU --top-ports 20); need_root=1 ;;
    6) args=(--script=vuln -sV); need_root=1 ;;
    *) return ;;
  esac

  clear
  echo ">>> nmap ${args[*]} $target"
  echo
  if [[ $need_root -eq 1 ]]; then
    run_sudo_or_plain nmap "${args[@]}" "$target"
  else
    nmap "${args[@]}" "$target"
  fi
  pause_return
}

masscan_scanner() {
  need_cmd masscan || { pause_return; return; }
  local target ports
  target=$(ask_input "Masscan" "Cíl (IP / CIDR):") || return
  ports=$(ask_input "Masscan" "Porty (např. 1-1024 nebo 80,443,8080):" "1-1024") || return
  clear
  echo ">>> sudo masscan $target -p$ports --rate 1000"
  echo
  run_sudo_or_plain masscan "$target" -p"$ports" --rate 1000
  pause_return
}

arp_scan_lan() {
  need_cmd arp-scan || { pause_return; return; }
  local iface
  iface=$(ask_input "arp-scan" "Rozhraní (prázdné = --localnet):" "") || return
  clear
  if [[ -n "${iface//[[:space:]]/}" ]]; then
    echo ">>> sudo arp-scan --interface=$iface --localnet"
    run_sudo_or_plain arp-scan --interface="$iface" --localnet
  else
    echo ">>> sudo arp-scan --localnet"
    run_sudo_or_plain arp-scan --localnet
  fi
  pause_return
}

tshark_capture() {
  need_cmd tshark || { pause_return; return; }
  local iface filter count
  iface=$(ask_input "tshark" "Rozhraní (např. eth0, wlan0, any):" "any") || return
  filter=$(ask_input "tshark" "Display/capture filtr (volitelné, např. tcp port 80):" "") || return
  count=$(ask_input "tshark" "Počet paketů (-c, Enter = 50):" "50") || return
  clear
  echo ">>> sudo tshark -i $iface -c ${count:-50} ${filter:+-f \"$filter\"}"
  echo "(Ctrl+C pro ukončení dříve)"
  echo
  if [[ -n "${filter//[[:space:]]/}" ]]; then
    run_sudo_or_plain tshark -i "$iface" -c "${count:-50}" -f "$filter"
  else
    run_sudo_or_plain tshark -i "$iface" -c "${count:-50}"
  fi
  pause_return
}

tcpdump_capture() {
  need_cmd tcpdump || { pause_return; return; }
  local iface filter count
  iface=$(ask_input "tcpdump" "Rozhraní (např. eth0, wlan0, any):" "any") || return
  filter=$(ask_input "tcpdump" "BPF filtr (volitelné, např. port 53 or host 1.1.1.1):" "") || return
  count=$(ask_input "tcpdump" "Počet paketů (-c, Enter = 50):" "50") || return
  clear
  echo ">>> sudo tcpdump -i $iface -nn -c ${count:-50} ${filter}"
  echo "(Ctrl+C pro ukončení dříve)"
  echo
  if [[ -n "${filter//[[:space:]]/}" ]]; then
    # shellcheck disable=SC2086
    run_sudo_or_plain tcpdump -i "$iface" -nn -c "${count:-50}" $filter
  else
    run_sudo_or_plain tcpdump -i "$iface" -nn -c "${count:-50}"
  fi
  pause_return
}

tls_scan() {
  local choice target
  choice=$(run_menu "TLS audit" "Nástroj:" 12 60 3 \
    "1" "sslscan" "sslscan — rychlý TLS/SSL skener cipher suite a certifikátů." \
    "2" "testssl.sh" "testssl.sh — podrobný audit TLS (Heartbleed, ROBOT, HSTS…)." \
    "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
  ) || return
  case "$choice" in
    1)
      need_cmd sslscan || { pause_return; return; }
      target=$(ask_input "sslscan" "Host[:port]:" "example.com:443") || return
      clear; echo ">>> sslscan $target"; sslscan "$target"; pause_return
      ;;
    2)
      need_cmd testssl || need_cmd testssl.sh || { pause_return; return; }
      target=$(ask_input "testssl" "URL nebo host:" "https://example.com") || return
      clear
      if command -v testssl >/dev/null 2>&1; then
        echo ">>> testssl $target"; testssl "$target"
      else
        echo ">>> testssl.sh $target"; testssl.sh "$target"
      fi
      pause_return
      ;;
    *) return ;;
  esac
}

quick_net_info() {
  local choice host
  choice=$(run_menu "Rychlá síťová diagnostika" "Akce:" 16 62 7 \
    "1" "dig (DNS)" "dig — DNS dotaz (ANY záznamy)." \
    "2" "host (DNS)" "host — DNS lookup (jednodušší než dig)." \
    "3" "whois" "whois — registrace domény / IP bloku." \
    "4" "mtr (traceroute+ping)" "mtr — kombinace ping + traceroute (5 paketů)." \
    "5" "traceroute" "traceroute — cesta paketů k cíli." \
    "6" "hping3 SYN ping (sudo)" "hping3 SYN ping — test dostupnosti portu 80. Sudo." \
    "7" "dnsenum" "dnsenum — enumerace DNS záznamů domény." \
    "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
  ) || return
  [[ "$choice" == "0" || -z "$choice" ]] && return
  host=$(ask_input "Cíl" "Hostname / IP:") || return
  clear
  case "$choice" in
    1) need_cmd dig && { echo ">>> dig $host ANY +noall +answer"; dig "$host" ANY +noall +answer || dig "$host"; } ;;
    2) need_cmd host && { echo ">>> host -a $host"; host -a "$host" || host "$host"; } ;;
    3) need_cmd whois && { echo ">>> whois $host"; whois "$host"; } ;;
    4) need_cmd mtr && { echo ">>> mtr -r -c 5 $host"; mtr -r -c 5 "$host"; } ;;
    5) need_cmd traceroute && { echo ">>> traceroute $host"; traceroute "$host"; } ;;
    6) need_cmd hping3 && { echo ">>> sudo hping3 -S -p 80 -c 4 $host"; run_sudo_or_plain hping3 -S -p 80 -c 4 "$host"; } ;;
    7) need_cmd dnsenum && { echo ">>> dnsenum $host"; dnsenum "$host"; } ;;
  esac
  pause_return
}

run_wireshark() {
  need_cmd wireshark || { pause_return; return; }
  clear
  echo "Spouštím Wireshark na pozadí..."
  if command -v setsid >/dev/null 2>&1; then
    setsid wireshark >/dev/null 2>&1 &
  else
    nohup wireshark >/dev/null 2>&1 &
  fi
  disown 2>/dev/null || true
  echo "Wireshark spuštěn."
  pause_return
}

recon_menu() {
  while true; do
    local choice
    choice=$(run_menu "1) Recon & Scanning" "Vyberte akci:" 20 72 11 \
      "1" "Nmap Skener" "Nmap — skener portů a služeb.
Zadejte cíl (IP/CIDR/host) a typ skenu." \
      "2" "Masscan (rychlý port scan)" "Masscan — extrémně rychlý TCP port scan.
Vyžaduje sudo, vhodný pro velké rozsahy." \
      "3" "arp-scan (LAN discovery)" "arp-scan — discovery zařízení v lokální síti přes ARP.
Vyžaduje sudo." \
      "4" "tshark (CLI capture)" "tshark — zachytávání paketů z CLI (Wireshark).
Volitelný BPF filtr a limit paketů." \
      "5" "tcpdump (CLI capture)" "tcpdump — klasický packet sniffer.
BPF filtr, sudo, výstup do terminálu." \
      "6" "TLS audit (sslscan / testssl)" "TLS audit: sslscan nebo testssl.sh.
Kontrola šifer, certifikátů a zranitelností." \
      "7" "DNS / whois / mtr / traceroute / hping3" "Rychlá diagnostika: dig, whois, mtr, traceroute, hping3, dnsenum." \
      "8" "Wireshark (GUI na pozadí)" "Wireshark GUI — spustí se na pozadí (setsid/nohup)." \
      "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
    ) || return
    case "$choice" in
      1) nmap_scanner ;;
      2) masscan_scanner ;;
      3) arp_scan_lan ;;
      4) tshark_capture ;;
      5) tcpdump_capture ;;
      6) tls_scan ;;
      7) quick_net_info ;;
      8) run_wireshark ;;
      0|"") return ;;
    esac
  done
}

# =============================================================================
# 2) Web App Testing
# =============================================================================

ffuf_scan() {
  need_cmd ffuf || { pause_return; return; }
  local url wl mode
  url=$(ask_input "ffuf" "URL s FUZZ (např. https://target/FUZZ):") || return
  wl=$(pick_wordlist) || return
  mode=$(run_menu "ffuf mód" "Režim:" 12 60 3 \
    "1" "Directory / path fuzzing" "Directory fuzzing: nahradí FUZZ v URL wordlistou cest." \
    "2" "VHost fuzzing (Host header)" "VHost fuzzing: FUZZ v Host hlavičce pro virtual host discovery." \
    "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
  ) || return
  clear
  case "$mode" in
    1)
      echo ">>> ffuf -u \"$url\" -w \"$wl\" -mc 200,204,301,302,307,401,403"
      ffuf -u "$url" -w "$wl" -mc 200,204,301,302,307,401,403
      ;;
    2)
      local host
      host=$(ask_input "ffuf vhost" "Základní Host / doména (např. target.local):") || return
      echo ">>> ffuf -u \"$url\" -w \"$wl\" -H \"Host: FUZZ.$host\" -mc 200,301,302,403"
      ffuf -u "$url" -w "$wl" -H "Host: FUZZ.$host" -mc 200,301,302,403
      ;;
    *) return ;;
  esac
  pause_return
}

gobuster_scan() {
  need_cmd gobuster || { pause_return; return; }
  local url wl
  url=$(ask_input "gobuster" "Základní URL (např. https://target/):") || return
  wl=$(pick_wordlist) || return
  clear
  echo ">>> gobuster dir -u \"$url\" -w \"$wl\" -t 30"
  gobuster dir -u "$url" -w "$wl" -t 30
  pause_return
}

whatweb_scan() {
  need_cmd whatweb || { pause_return; return; }
  local url
  url=$(ask_input "whatweb" "URL / host:") || return
  clear
  echo ">>> whatweb -a 3 \"$url\""
  whatweb -a 3 "$url"
  pause_return
}

wafw00f_scan() {
  need_cmd wafw00f || { pause_return; return; }
  local url
  url=$(ask_input "wafw00f" "URL:") || return
  clear
  echo ">>> wafw00f \"$url\""
  wafw00f "$url"
  pause_return
}

nuclei_scan() {
  need_cmd nuclei || { pause_return; return; }
  local target
  target=$(ask_input "nuclei" "Cíl (URL nebo host):") || return
  clear
  echo ">>> nuclei -u \"$target\" -silent"
  echo "(první běh může stahovat šablony)"
  nuclei -u "$target"
  pause_return
}

subfinder_scan() {
  need_cmd subfinder || { pause_return; return; }
  local domain
  domain=$(ask_input "subfinder" "Doména (např. example.com):") || return
  clear
  echo ">>> subfinder -d \"$domain\" -silent"
  subfinder -d "$domain"
  pause_return
}

sqlmap_scan() {
  need_cmd sqlmap || { pause_return; return; }
  local url
  url=$(ask_input "sqlmap" "URL s parametrem (např. http://target/x.php?id=1):") || return
  clear
  echo ">>> sqlmap -u \"$url\" --batch --banner"
  echo "POUZE na systémech, kde máte povolení testovat!"
  sqlmap -u "$url" --batch --banner
  pause_return
}

web_menu() {
  while true; do
    local choice
    choice=$(run_menu "2) Web App Testing" "Vyberte akci:" 18 70 9 \
      "1" "ffuf — fuzzing" "ffuf — rychlý web fuzzer (cesty, vhosty).
Pouze na autorizovaných cílech / v labu." \
      "2" "gobuster — dir brute" "gobuster — brute-force adresářů a souborů.
Pouze na autorizovaných cílech / v labu." \
      "3" "whatweb — fingerprint" "whatweb — fingerprint webového serveru a technologií." \
      "4" "wafw00f — detekce WAF" "wafw00f — detekce Web Application Firewall." \
      "5" "nuclei — template scan" "nuclei — scan podle YAML šablon (CVE, misconfig).
Pouze na autorizovaných cílech / v labu." \
      "6" "subfinder — subdomény" "subfinder — pasivní enumerace subdomén." \
      "7" "sqlmap — SQLi (lab!)" "sqlmap — automatický SQL injection test.
Pouze na autorizovaných cílech / v labu." \
      "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
    ) || return
    case "$choice" in
      1) ffuf_scan ;;
      2) gobuster_scan ;;
      3) whatweb_scan ;;
      4) wafw00f_scan ;;
      5) nuclei_scan ;;
      6) subfinder_scan ;;
      7) sqlmap_scan ;;
      0|"") return ;;
    esac
  done
}

# =============================================================================
# 3) Passwords & Auth
# =============================================================================

hydra_attack() {
  need_cmd hydra || { pause_return; return; }
  local target service user userlist passlist
  target=$(ask_input "hydra" "Cíl (IP/host):") || return
  service=$(ask_input "hydra" "Služba (ssh, ftp, http-get, http-post-form, smb, rdp...):" "ssh") || return
  user=$(ask_input "hydra" "Jeden uživatel (nebo nechte prázdné a zadejte list):" "root") || return
  clear
  if [[ -n "${user//[[:space:]]/}" ]]; then
    passlist=$(ask_input "hydra" "Password list:" "$FALLBACK_WORDLIST") || return
    echo ">>> hydra -l $user -P $passlist $target $service"
    echo "POUZE autorizované testy!"
    hydra -l "$user" -P "$passlist" "$target" "$service"
  else
    userlist=$(ask_input "hydra" "User list:" "$FALLBACK_WORDLIST") || return
    passlist=$(ask_input "hydra" "Password list:" "$FALLBACK_WORDLIST") || return
    echo ">>> hydra -L $userlist -P $passlist $target $service"
    hydra -L "$userlist" -P "$passlist" "$target" "$service"
  fi
  pause_return
}

medusa_attack() {
  need_cmd medusa || { pause_return; return; }
  local target module user passlist
  target=$(ask_input "medusa" "Cíl:") || return
  module=$(ask_input "medusa" "Modul (-M), např. ssh, ftp, http:" "ssh") || return
  user=$(ask_input "medusa" "Uživatel (-u):" "root") || return
  passlist=$(ask_input "medusa" "Password file (-P):" "$FALLBACK_WORDLIST") || return
  clear
  echo ">>> medusa -h $target -u $user -P $passlist -M $module"
  medusa -h "$target" -u "$user" -P "$passlist" -M "$module"
  pause_return
}

ncrack_attack() {
  need_cmd ncrack || { pause_return; return; }
  local target user passlist
  target=$(ask_input "ncrack" "Cíl se službou (např. ssh://192.168.1.10):" "ssh://127.0.0.1") || return
  user=$(ask_input "ncrack" "Uživatel:" "root") || return
  passlist=$(ask_input "ncrack" "Password list:" "$FALLBACK_WORDLIST") || return
  clear
  echo ">>> ncrack -user $user -P $passlist $target"
  ncrack -user "$user" -P "$passlist" "$target"
  pause_return
}

john_crack() {
  need_cmd john || { pause_return; return; }
  local hashfile
  hashfile=$(ask_input "john" "Cesta k souboru s hashi:") || return
  clear
  echo ">>> john \"$hashfile\""
  john "$hashfile"
  echo
  echo ">>> john --show \"$hashfile\""
  john --show "$hashfile"
  pause_return
}

hashcat_crack() {
  need_cmd hashcat || { pause_return; return; }
  local hashfile mode wl
  hashfile=$(ask_input "hashcat" "Cesta k hashi / hashfile:") || return
  mode=$(ask_input "hashcat" "Hash mode (-m), např. 0=MD5, 1000=NTLM, 1800=sha512crypt:" "0") || return
  wl=$(ask_input "hashcat" "Wordlist:" "$FALLBACK_WORDLIST") || return
  clear
  echo ">>> hashcat -m $mode \"$hashfile\" \"$wl\" --force"
  hashcat -m "$mode" "$hashfile" "$wl" --force
  pause_return
}

auth_menu() {
  while true; do
    local choice
    choice=$(run_menu "3) Hesla & Autentizace" "Vyberte akci:" 16 70 7 \
      "1" "hydra — online brute" "hydra — paralelní online brute-force (SSH, FTP, HTTP…).
Pouze na autorizovaných cílech / v labu." \
      "2" "medusa — online brute" "medusa — alternativa k hydře, modulární brute.
Pouze na autorizovaných cílech / v labu." \
      "3" "ncrack — online brute" "ncrack — rychlý network auth cracker od nmap týmu.
Pouze na autorizovaných cílech / v labu." \
      "4" "john — offline crack" "john — offline crack hashů ze souboru.
Pouze na autorizovaných cílech / v labu." \
      "5" "hashcat — offline crack (GPU/CPU)" "hashcat — GPU/CPU offline crack, mnoho hash módů.
Pouze na autorizovaných cílech / v labu." \
      "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
    ) || return
    case "$choice" in
      1) hydra_attack ;;
      2) medusa_attack ;;
      3) ncrack_attack ;;
      4) john_crack ;;
      5) hashcat_crack ;;
      0|"") return ;;
    esac
  done
}

# =============================================================================
# 4) System processes
# =============================================================================

trace_process() {
  local tool choice target mode
  choice=$(run_menu "Sledování procesů" "Nástroj:" 12 60 3 \
    "1" "strace — syscalls" "strace — zachytí syscalls (open, read, connect…)." \
    "2" "ltrace — library calls" "ltrace — zachytí volání sdílených knihoven (libc…)." \
    "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
  ) || return
  case "$choice" in
    1) tool=strace ;;
    2) tool=ltrace ;;
    *) return ;;
  esac
  need_cmd "$tool" || { pause_return; return; }

  mode=$(run_menu "$tool" "Režim:" 12 60 3 \

    "1" "Připojit k PID (-p)" "Připojí se k běžícímu procesu podle PID (-p). Ctrl+C ukončí." \

    "2" "Spustit nový příkaz" "Spustí nový příkaz pod sledováním od začátku." \

    "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."

  ) || return

  clear
  case "$mode" in
    1)
      target=$(ask_input "$tool" "PID:") || return
      target="${target//[[:space:]]/}"
      [[ "$target" =~ ^[0-9]+$ ]] || { echo "Neplatné PID."; pause_return; return; }
      echo ">>> $tool -p $target  (Ctrl+C ukončí)"
      run_sudo_or_plain "$tool" -p "$target" || "$tool" -p "$target"
      ;;
    2)
      target=$(ask_input "$tool" "Příkaz včetně argumentů:") || return
      [[ -n "${target//[[:space:]]/}" ]] || { echo "Prázdný příkaz."; pause_return; return; }
      echo ">>> $tool -- $target"
      # shellcheck disable=SC2086
      "$tool" -- $target
      ;;
    *) return ;;
  esac
  pause_return
}

run_gdb() {
  need_cmd gdb || { pause_return; return; }
  clear
  echo "Spouštím GDB (GEF z ~/.gdbinit, pokud je nastaven)."
  echo
  gdb
  pause_return
}

system_menu() {
  while true; do
    local choice
    choice=$(run_menu "4) Systémové procesy & diagnostika" "Vyberte akci:" 14 65 4 \
      "1" "strace / ltrace" "strace/ltrace — sledování syscalls a knihovních volání procesu." \
      "2" "GDB (GEF)" "GDB s GEF — interaktivní debugger (breakpointy, disasm)." \
      "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
    ) || return
    case "$choice" in
      1) trace_process ;;
      2) run_gdb ;;
      0|"") return ;;
    esac
  done
}

# =============================================================================
# 5) Reverse & Binary
# =============================================================================

run_radare2() {
  need_cmd r2 || need_cmd radare2 || { pause_return; return; }
  local bin
  bin=$(ask_input "radare2" "Cesta k binárce (prázdné = interaktivní r2 bez souboru):") || return
  clear
  if [[ -n "${bin//[[:space:]]/}" ]]; then
    echo ">>> r2 \"$bin\""
    r2 "$bin" 2>/dev/null || radare2 "$bin"
  else
    r2 - 2>/dev/null || radare2 -
  fi
  pause_return
}

run_checksec() {
  need_cmd checksec || { pause_return; return; }
  local bin
  bin=$(ask_input "checksec" "Cesta k ELF binárce:") || return
  clear
  echo ">>> checksec --file=\"$bin\""
  checksec --file="$bin" 2>/dev/null || checksec "$bin"
  pause_return
}

run_binwalk() {
  need_cmd binwalk || { pause_return; return; }
  local file
  file=$(ask_input "binwalk" "Soubor k analýze / extrakci:") || return
  local mode
  mode=$(run_menu "binwalk" "Režim:" 12 60 3 \
    "1" "Sken (výchozí)" "Výchozí sken — hledá signature (ZIP, ELF, JPEG…) v souboru." \
    "2" "Extrakce (-e)" "Extrakce (-e) — automaticky vytáhne nalezené soubory." \
    "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
  ) || return
  clear
  case "$mode" in
    1) echo ">>> binwalk \"$file\""; binwalk "$file" ;;
    2) echo ">>> binwalk -e \"$file\""; binwalk -e "$file" ;;
    *) return ;;
  esac
  pause_return
}

run_yara() {
  need_cmd yara || { pause_return; return; }
  local rules target
  rules=$(ask_input "yara" "Cesta k .yar pravidlům:") || return
  target=$(ask_input "yara" "Soubor / adresář k skenu:") || return
  clear
  echo ">>> yara -r \"$rules\" \"$target\""
  yara -r "$rules" "$target"
  pause_return
}

strings_objdump() {
  local choice file
  choice=$(run_menu "strings / objdump" "Nástroj:" 12 60 3 \
    "1" "strings" "strings — vytiskne tisknutelné řetězce z binárky." \
    "2" "objdump -d (disasm)" "objdump -d — disassembly (prvních 200 řádků)." \
    "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
  ) || return
  [[ "$choice" == "0" || -z "$choice" ]] && return
  file=$(ask_input "Soubor" "Cesta k binárce:") || return
  clear
  case "$choice" in
    1) need_cmd strings && { echo ">>> strings \"$file\" | head -n 200"; strings "$file" | head -n 200; } ;;
    2) need_cmd objdump && { echo ">>> objdump -d \"$file\" | head -n 200"; objdump -d "$file" | head -n 200; } ;;
  esac
  pause_return
}

reverse_menu() {
  while true; do
    local choice
    choice=$(run_menu "5) Reverse & Binary" "Vyberte akci:" 16 65 7 \
      "1" "radare2 (r2)" "radare2 (r2) — disassembler, debugger, decompiler v jednom." \
      "2" "checksec" "checksec — kontrola ochrany binárky (NX, PIE, Canary…)." \
      "3" "binwalk" "binwalk — analýza a extrakce embedded souborů z image." \
      "4" "yara" "yara — scan souborů podle pravidel (.yar)." \
      "5" "strings / objdump" "strings / objdump — extrakce textu a disassembly." \
      "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
    ) || return
    case "$choice" in
      1) run_radare2 ;;
      2) run_checksec ;;
      3) run_binwalk ;;
      4) run_yara ;;
      5) strings_objdump ;;
      0|"") return ;;
    esac
  done
}

# =============================================================================
# 6) Wireless
# =============================================================================

wireless_menu() {
  while true; do
    local choice
    choice=$(run_menu "6) Wireless (aircrack-ng)" "Vyberte akci:" 16 70 6 \
      "1" "airmon-ng — stav rozhraní" "airmon-ng — stav WiFi rozhraní a monitor mode." \
      "2" "airodump-ng — scan sítí" "airodump-ng — scan WiFi sítí a kanálů.
Pouze na autorizovaných cílech / v labu." \
      "3" "aircrack-ng — crack .cap/.hccapx" "aircrack-ng — crack WPA handshake ze .cap.
Pouze na autorizovaných cílech / v labu." \
      "4" "hcxpcapngtool — převod handshake" "hcxpcapngtool — převod pcap na formát .hc22000 pro hashcat." \
      "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
    ) || return
    case "$choice" in
      1)
        need_cmd airmon-ng || { pause_return; continue; }
        clear; echo ">>> sudo airmon-ng"; run_sudo_or_plain airmon-ng; pause_return
        ;;
      2)
        need_cmd airodump-ng || { pause_return; continue; }
        local iface
        iface=$(ask_input "airodump-ng" "Monitor rozhraní (např. wlan0mon):" "wlan0mon") || continue
        clear
        echo ">>> sudo airodump-ng $iface"
        echo "(Ctrl+C ukončí)"
        run_sudo_or_plain airodump-ng "$iface"
        pause_return
        ;;
      3)
        need_cmd aircrack-ng || { pause_return; continue; }
        local cap wl
        cap=$(ask_input "aircrack-ng" "Cesta k .cap / .hccapx:") || continue
        wl=$(ask_input "aircrack-ng" "Wordlist:" "$FALLBACK_WORDLIST") || continue
        clear
        echo ">>> aircrack-ng -w \"$wl\" \"$cap\""
        aircrack-ng -w "$wl" "$cap"
        pause_return
        ;;
      4)
        need_cmd hcxpcapngtool || { pause_return; continue; }
        local cap out
        cap=$(ask_input "hcxpcapngtool" "Vstupní pcap/pcapng:") || continue
        out=$(ask_input "hcxpcapngtool" "Výstupní .hc22000:" "./handshake.hc22000") || continue
        clear
        echo ">>> hcxpcapngtool -o \"$out\" \"$cap\""
        hcxpcapngtool -o "$out" "$cap"
        pause_return
        ;;
      0|"") return ;;
    esac
  done
}

# =============================================================================
# 7) Security & Forensics (Blue Team)
# =============================================================================

run_lynis() {
  need_cmd lynis || { pause_return; return; }
  clear
  echo ">>> sudo lynis audit system"
  run_sudo_or_plain lynis audit system
  pause_return
}

sleuthkit_menu() {
  while true; do
    local choice
    choice=$(run_menu "Sleuthkit" "Nástroj:" 14 65 4 \
      "1" "mmls — partition tables" "mmls — partition table z disk image." \
      "2" "fls — výpis souborů" "fls — výpis souborů z image (volitelný offset)." \
      "3" "man mmls / fls (náhled)" "Náhled man stránek mmls a fls." \
      "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
    ) || return
    case "$choice" in
      1)
        need_cmd mmls || { pause_return; continue; }
        local img
        img=$(ask_input "mmls" "Image / zařízení:") || continue
        clear; echo ">>> mmls \"$img\""; run_sudo_or_plain mmls "$img" 2>/dev/null || mmls "$img"; pause_return
        ;;
      2)
        need_cmd fls || { pause_return; continue; }
        local img offset
        img=$(ask_input "fls" "Image / zařízení:") || continue
        offset=$(ask_input "fls" "Offset (-o), Enter = bez:" "") || continue
        clear
        if [[ -n "${offset//[[:space:]]/}" ]]; then
          echo ">>> fls -o $offset \"$img\""
          run_sudo_or_plain fls -o "$offset" "$img" 2>/dev/null || fls -o "$offset" "$img"
        else
          echo ">>> fls \"$img\""
          run_sudo_or_plain fls "$img" 2>/dev/null || fls "$img"
        fi
        pause_return
        ;;
      3)
        clear
        man -P cat mmls 2>/dev/null | head -n 35 || true
        echo; man -P cat fls 2>/dev/null | head -n 35 || true
        pause_return
        ;;
      0|"") return ;;
    esac
  done
}

run_aide() {
  need_cmd aide || { pause_return; return; }
  local choice
  choice=$(run_menu "AIDE" "Akce:" 12 60 3 \
    "1" "Inicializace DB (aide --init)" "aide --init — vytvoří baseline databázi integrity." \
    "2" "Kontrola integrity (aide --check)" "aide --check — porovná současný stav s baseline." \
    "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
  ) || return
  clear
  case "$choice" in
    1) echo ">>> sudo aide --init"; run_sudo_or_plain aide --init ;;
    2) echo ">>> sudo aide --check"; run_sudo_or_plain aide --check ;;
    *) return ;;
  esac
  pause_return
}

run_rkhunter() {
  need_cmd rkhunter || { pause_return; return; }
  clear
  echo ">>> sudo rkhunter --check --sk"
  run_sudo_or_plain rkhunter --check --sk
  pause_return
}

run_clamav() {
  need_cmd clamscan || { pause_return; return; }
  local path choice
  choice=$(run_menu "ClamAV" "Akce:" 12 60 3 \
    "1" "Aktualizace DB (freshclam)" "freshclam — stáhne nejnovější virové definice." \
    "2" "Sken adresáře" "clamscan -r — rekurzivní scan zadaného adresáře." \
    "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
  ) || return
  clear
  case "$choice" in
    1)
      need_cmd freshclam || { pause_return; return; }
      echo ">>> sudo freshclam"
      run_sudo_or_plain freshclam
      ;;
    2)
      path=$(ask_input "clamscan" "Adresář ke skenu:" "$HOME") || return
      echo ">>> clamscan -r \"$path\""
      clamscan -r "$path"
      ;;
    *) return ;;
  esac
  pause_return
}

run_volatility() {
  local vol=vol
  command -v vol >/dev/null 2>&1 || vol=volatility3
  need_cmd "$vol" || need_cmd vol || { pause_return; return; }
  command -v vol >/dev/null 2>&1 && vol=vol
  local mem cmd
  mem=$(ask_input "volatility3" "Cesta k memory dump (.raw/.mem/.dmp):") || return
  cmd=$(ask_input "volatility3" "Plugin (např. windows.info / windows.pslist):" "windows.info") || return
  clear
  echo ">>> vol -f \"$mem\" $cmd"
  vol -f "$mem" $cmd 2>/dev/null || volatility3 -f "$mem" $cmd
  pause_return
}

run_foremost_testdisk() {
  local choice
  choice=$(run_menu "Obnova dat" "Nástroj:" 12 60 3 \
    "1" "foremost — carving" "foremost — file carving z disk image." \
    "2" "testdisk (interaktivní)" "testdisk — interaktivní obnova ztracených partition." \
    "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
  ) || return
  case "$choice" in
    1)
      need_cmd foremost || { pause_return; return; }
      local img out
      img=$(ask_input "foremost" "Image / zařízení:") || return
      out=$(ask_input "foremost" "Výstupní adresář:" "./foremost-out") || return
      clear
      echo ">>> foremost -i \"$img\" -o \"$out\""
      foremost -i "$img" -o "$out"
      pause_return
      ;;
    2)
      need_cmd testdisk || { pause_return; return; }
      clear
      echo ">>> sudo testdisk"
      run_sudo_or_plain testdisk
      pause_return
      ;;
    *) return ;;
  esac
}

run_exiftool() {
  need_cmd exiftool || { pause_return; return; }
  local file
  file=$(ask_input "exiftool" "Soubor (foto/dokument):") || return
  clear
  echo ">>> exiftool \"$file\""
  exiftool "$file"
  pause_return
}

run_bpftrace_demo() {
  need_cmd bpftrace || { pause_return; return; }
  clear
  echo ">>> sudo bpftrace -e 'tracepoint:syscalls:sys_enter_openat { @[comm] = count(); }'"
  echo "Běží ~8s, pak Ctrl+C ekvivalent timeoutem..."
  run_sudo_or_plain timeout 8 bpftrace -e 'tracepoint:syscalls:sys_enter_openat { @[comm] = count(); }' || true
  pause_return
}

audit_journal() {
  local choice
  choice=$(run_menu "Audit / Journal" "Akce:" 12 65 3 \
    "1" "ausearch -m avc,USER_AVC -ts recent" "ausearch — nedávné SELinux AVC události." \
    "2" "journalctl -p err..alert -b --no-pager" "journalctl — chyby a alerty od posledního bootu." \
    "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
  ) || return
  clear
  case "$choice" in
    1)
      if command -v ausearch >/dev/null 2>&1; then
        echo ">>> sudo ausearch -m avc,USER_AVC -ts recent"
        run_sudo_or_plain ausearch -m avc,USER_AVC -ts recent || true
      else
        echo "ausearch není k dispozici (balíček audit)."
      fi
      ;;
    2)
      echo ">>> journalctl -p err..alert -b --no-pager | tail -n 80"
      journalctl -p err..alert -b --no-pager | tail -n 80
      ;;
    *) return ;;
  esac
  pause_return
}

blue_menu() {
  while true; do
    local choice
    choice=$(run_menu "7) Bezpečnost & Forenzní analýza" "Vyberte akci:" 20 72 11 \
      "1" "Lynis Audit" "Lynis — audit hardeningu a bezpečnosti systému." \
      "2" "Sleuthkit (mmls / fls)" "Sleuthkit: mmls (partitions), fls (soubory z image)." \
      "3" "AIDE — integrita" "AIDE — detekce změn souborů (integrita)." \
      "4" "rkhunter" "rkhunter — hledání rootkitů a podezřelých souborů." \
      "5" "ClamAV" "ClamAV — antivirový scan a aktualizace DB." \
      "6" "Volatility3 — memory forensics" "Volatility3 — analýza memory dumpu (Windows/Linux)." \
      "7" "foremost / testdisk" "foremost (carving) / testdisk (obnova partition)." \
      "8" "exiftool — metadata" "exiftool — metadata z fotek a dokumentů." \
      "9" "bpftrace — ukázka syscalls" "bpftrace — ukázka eBPF sledování syscalls." \
      "10" "audit / journalctl" "Audit logy: ausearch (SELinux), journalctl (chyby)." \
      "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
    ) || return
    case "$choice" in
      1) run_lynis ;;
      2) sleuthkit_menu ;;
      3) run_aide ;;
      4) run_rkhunter ;;
      5) run_clamav ;;
      6) run_volatility ;;
      7) run_foremost_testdisk ;;
      8) run_exiftool ;;
      9) run_bpftrace_demo ;;
      10) audit_journal ;;
      0|"") return ;;
    esac
  done
}

# =============================================================================
# 8) SMB / Impacket (lab)
# =============================================================================

smb_impacket_menu() {
  while true; do
    local choice
    choice=$(run_menu "8) SMB / Impacket (lab)" "Vyberte akci:" 16 70 6 \
      "1" "smbclient -L (výpis sdílení)" "smbclient -L — výpis SMB sdílení na hostu.
Pouze na autorizovaných cílech / v labu." \
      "2" "impacket-smbclient" "impacket-smbclient — interaktivní SMB shell.
Pouze na autorizovaných cílech / v labu." \
      "3" "impacket-GetADUsers / GetNPUsers (nápověda)" "Textová nápověda k Impacket AD skriptům (GetNPUsers…)." \
      "4" "Seznam impacket skriptů" "Seznam nainstalovaných impacket-* příkazů." \
      "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
    ) || return
    case "$choice" in
      1)
        need_cmd smbclient || { pause_return; continue; }
        local host
        host=$(ask_input "smbclient" "Host:") || continue
        clear
        echo ">>> smbclient -L \"$host\" -N"
        smbclient -L "$host" -N || smbclient -L "$host"
        pause_return
        ;;
      2)
        if ! command -v impacket-smbclient >/dev/null 2>&1 && ! command -v smbclient.py >/dev/null 2>&1; then
          echo "python3-impacket není nainstalován."
          pause_return
          continue
        fi
        local cred
        cred=$(ask_input "impacket-smbclient" "domain/user:password@host:") || continue
        clear
        if command -v impacket-smbclient >/dev/null 2>&1; then
          echo ">>> impacket-smbclient \"$cred\""
          impacket-smbclient "$cred"
        else
          echo ">>> smbclient.py \"$cred\""
          smbclient.py "$cred"
        fi
        pause_return
        ;;
      3)
        clear
        cat <<'EOF'
Impacket (AD lab) — typické příkazy:

  impacket-GetNPUsers domain/ -dc-ip DC_IP -usersfile users.txt -format hashcat
  impacket-GetUserSPNs domain/user:pass -dc-ip DC_IP -request
  impacket-secretsdump domain/user:pass@HOST
  impacket-psexec domain/user:pass@HOST
  impacket-wmiexec domain/user:pass@HOST

POUZE v laboratoři / s písemným povolením.
EOF
        pause_return
        ;;
      4)
        clear
        echo "Dostupné impacket-* příkazy:"
        compgen -c | grep -E '^impacket-' | sort
        echo
        ls /usr/bin/*impacket* /usr/bin/*.py 2>/dev/null | grep -iE 'impacket|secretsdump|psexec|GetNPUsers' | head -40 || true
        pause_return
        ;;
      0|"") return ;;
    esac
  done
}

# =============================================================================
# 9) Proxy / OpSec
# =============================================================================

proxy_menu() {
  while true; do
    local choice
    choice=$(run_menu "9) Proxy / OpSec" "Vyberte akci:" 14 70 5 \
      "1" "proxychains4 — nápověda + test" "proxychains4 — směruje příkazy přes SOCKS/HTTP proxy (Tor)." \
      "2" "tor služba (status / start)" "Tor služba — status, případně enable/start." \
      "3" "Zobrazit ~/.proxychains/proxychains.conf" "Zobrazí obsah proxychains.conf." \
      "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
    ) || return
    case "$choice" in
      1)
        need_cmd proxychains4 || need_cmd proxychains || { pause_return; continue; }
        clear
        cat <<'EOF'
Příklad:
  proxychains4 nmap -sT -Pn target
  proxychains4 curl https://ifconfig.me

Konfigurace: /etc/proxychains.conf nebo ~/.proxychains/proxychains.conf
Typicky SOCKS5 127.0.0.1:9050 (Tor).
EOF
        echo
        if command -v proxychains4 >/dev/null 2>&1; then
          echo ">>> proxychains4 curl -s https://ifconfig.me"
          proxychains4 curl -s --max-time 15 https://ifconfig.me || echo "(Tor pravděpodobně neběží)"
        fi
        pause_return
        ;;
      2)
        need_cmd tor || { pause_return; continue; }
        clear
        systemctl status tor --no-pager || true
        echo
        read -r -p "Spustit/enablovat tor? [y/N] " ans
        if [[ "${ans:-}" =~ ^[yY]$ ]]; then
          run_sudo_or_plain systemctl enable --now tor
          systemctl status tor --no-pager || true
        fi
        pause_return
        ;;
      3)
        clear
        for f in "$HOME/.proxychains/proxychains.conf" /etc/proxychains.conf /etc/proxychains-ng/proxychains.conf; do
          if [[ -f "$f" ]]; then
            echo "=== $f ==="
            head -n 40 "$f"
            echo
          fi
        done
        pause_return
        ;;
      0|"") return ;;
    esac
  done
}

# =============================================================================
# 10) OSINT — osoby (e-mail / username / telefon)
# =============================================================================

osint_holehe() {
  need_cmd holehe || { pause_return; return; }
  local email mode
  email=$(ask_input "holehe" "E-mail cílové osoby:") || return
  mode=$(run_menu "holehe" "Režim:" 12 65 3 \
    "1" "Plný sken (všechny služby)" "Plný sken všech podporovaných služeb pro e-mail." \
    "2" "Jen nalezené účty (--only-used)" "Jen služby, kde je e-mail registrován (--only-used)." \
    "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
  ) || return
  clear
  echo "POUZE pro OSINT s oprávněním / vlastní účty / vzdělávací lab."
  echo
  case "$mode" in
    1) echo ">>> holehe --no-clear \"$email\""; holehe --no-clear "$email" ;;
    2) echo ">>> holehe --only-used --no-clear \"$email\""; holehe --only-used --no-clear "$email" ;;
    *) return ;;
  esac
  pause_return
}

osint_maigret() {
  need_cmd maigret || { pause_return; return; }
  local user mode
  user=$(ask_input "maigret" "Username (přezdívka):") || return
  mode=$(run_menu "maigret" "Hloubka skenu:" 14 70 4 \
    "1" "Rychlý (top 150 site)" "Rychlý sken top 150 webů." \
    "2" "Střední (top 500)" "Střední sken top 500 webů." \
    "3" "Široký (-a, všechny známé)" "Široký sken všech známých site (-a). Pomalý." \
    "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
  ) || return
  clear
  echo "POUZE pro OSINT s oprávněním / vzdělávací lab."
  echo
  case "$mode" in
    1) echo ">>> maigret \"$user\" --top-sites 150"; maigret "$user" --top-sites 150 ;;
    2) echo ">>> maigret \"$user\" --top-sites 500"; maigret "$user" --top-sites 500 ;;
    3) echo ">>> maigret \"$user\" -a"; maigret "$user" -a ;;
    *) return ;;
  esac
  pause_return
}

osint_sherlock() {
  need_cmd sherlock || { pause_return; return; }
  local user
  user=$(ask_input "sherlock" "Username ke hledání na sociálních sítích:") || return
  clear
  echo ">>> sherlock \"$user\" --print-found"
  echo "POUZE pro OSINT s oprávněním / vzdělávací lab."
  echo
  sherlock "$user" --print-found
  pause_return
}

osint_phoneinfoga() {
  need_cmd phoneinfoga || { pause_return; return; }
  local number mode
  number=$(ask_input "phoneinfoga" "Telefonní číslo (E.164, např. +420777123456):") || return
  mode=$(run_menu "phoneinfoga" "Akce:" 12 65 3 \
    "1" "scan — sken čísla" "scan — OSINT scan telefonního čísla." \
    "2" "scanners — seznam scannerů" "scanners — seznam dostupných scanner modulů." \
    "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
  ) || return
  clear
  case "$mode" in
    1)
      echo ">>> phoneinfoga scan -n \"$number\""
      echo "POUZE pro OSINT s oprávněním / vzdělávací lab."
      echo
      phoneinfoga scan -n "$number"
      ;;
    2)
      echo ">>> phoneinfoga scanners"
      phoneinfoga scanners
      ;;
    *) return ;;
  esac
  pause_return
}

osint_socid() {
  need_cmd socid_extractor || { pause_return; return; }
  local url
  url=$(ask_input "socid_extractor" "URL profilu / stránky k extrakci ID:") || return
  clear
  echo ">>> socid_extractor --url \"$url\""
  echo
  socid_extractor --url "$url"
  pause_return
}

osint_cupp() {
  need_cmd cupp || { pause_return; return; }
  clear
  echo ">>> cupp -i"
  echo "Interaktivní profilování hesel z osobních údajů (pro lab / wordlist)."
  echo
  cupp -i
  pause_return
}

osint_combo() {
  # Rychlý řetězec: e-mail → holehe, username → maigret+sherlock
  local email user
  email=$(ask_input "OSINT combo" "E-mail (Enter = přeskočit):") || return
  user=$(ask_input "OSINT combo" "Username (Enter = přeskočit):") || return
  clear
  echo "=== Kombinovaný OSINT průchod ==="
  echo "POUZE s oprávněním / vzdělávací lab."
  echo
  if [[ -n "${email//[[:space:]]/}" ]] && command -v holehe >/dev/null 2>&1; then
    echo "----- holehe: $email -----"
    holehe --only-used --no-clear "$email" || true
    echo
  fi
  if [[ -n "${user//[[:space:]]/}" ]]; then
    if command -v maigret >/dev/null 2>&1; then
      echo "----- maigret (top 150): $user -----"
      maigret "$user" --top-sites 150 || true
      echo
    fi
    if command -v sherlock >/dev/null 2>&1; then
      echo "----- sherlock: $user -----"
      sherlock "$user" --print-found || true
      echo
    fi
  fi
  if [[ -z "${email//[[:space:]]/}" && -z "${user//[[:space:]]/}" ]]; then
    echo "Nebyl zadán e-mail ani username."
  fi
  pause_return
}

osint_menu() {
  while true; do
    local choice
    choice=$(run_menu "10) OSINT — osoby" "E-mail / username / telefon (nainstalované nástroje):" 18 74 9 \
      "1" "holehe — e-mail → registrované služby" "holehe — z e-mailu zjistí registrace na službách.
Pouze na autorizovaných cílech / v labu." \
      "2" "maigret — username napříč weby" "maigret — username na stovkách webů.
Pouze na autorizovaných cílech / v labu." \
      "3" "sherlock — username na sociálních sítích" "sherlock — username na sociálních sítích.
Pouze na autorizovaných cílech / v labu." \
      "4" "phoneinfoga — telefonní číslo" "phoneinfoga — OSINT telefonního čísla.
Pouze na autorizovaných cílech / v labu." \
      "5" "socid_extractor — ID z URL profilu" "socid_extractor — extrakce ID z URL profilu.
Pouze na autorizovaných cílech / v labu." \
      "6" "cupp — wordlist z osobních údajů" "cupp — generátor wordlist z osobních údajů.
Pouze na autorizovaných cílech / v labu." \
      "7" "Combo — e-mail + username (holehe/maigret/sherlock)" "Combo — holehe + maigret + sherlock v jednom průchodu.
Pouze na autorizovaných cílech / v labu." \
      "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
    ) || return
    case "$choice" in
      1) osint_holehe ;;
      2) osint_maigret ;;
      3) osint_sherlock ;;
      4) osint_phoneinfoga ;;
      5) osint_socid ;;
      6) osint_cupp ;;
      7) osint_combo ;;
      0|"") return ;;
    esac
  done
}

# =============================================================================
# 11) Síťové & systémové utility (už nainstalované CLI)
# =============================================================================

sockets_overview() {
  local choice
  choice=$(run_menu "Sokety & procesy" "Akce:" 14 70 5 \
    "1" "ss -tulpn (poslouchající porty)" "ss -tulpn — poslouchající TCP/UDP porty + procesy." \
    "2" "ss -tp (aktivní TCP + procesy)" "ss -tp — aktivní TCP spojení s PID." \
    "3" "lsof -i -P -n" "lsof -i — otevřené síťové sockety (sudo)." \
    "4" "netstat -tulpn" "netstat -tulpn — klasický přehled portů." \
    "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
  ) || return
  clear
  case "$choice" in
    1) need_cmd ss && { echo ">>> ss -tulpn"; ss -tulpn; } ;;
    2) need_cmd ss && { echo ">>> ss -tp"; ss -tp; } ;;
    3) need_cmd lsof && { echo ">>> sudo lsof -i -P -n"; run_sudo_or_plain lsof -i -P -n; } ;;
    4) need_cmd netstat && { echo ">>> netstat -tulpn"; netstat -tulpn 2>/dev/null || run_sudo_or_plain netstat -tulpn; } ;;
    *) return ;;
  esac
  pause_return
}

ncat_connect() {
  local bin=ncat
  command -v ncat >/dev/null 2>&1 || bin=nc
  need_cmd "$bin" || { pause_return; return; }
  local mode host port
  mode=$(run_menu "$bin" "Režim:" 14 65 4 \
    "1" "Connect (klient) na host:port" "TCP connect na zadaný host:port." \
    "2" "Listen (server) na portu" "Listen na portu — příchozí spojení." \
    "3" "Banner grab (HTTP HEAD)" "Banner grab — HTTP HEAD request." \
    "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
  ) || return
  clear
  case "$mode" in
    1)
      host=$(ask_input "$bin" "Host:") || return
      port=$(ask_input "$bin" "Port:" "80") || return
      echo ">>> $bin -v $host $port"
      echo "(Ctrl+C ukončí)"
      "$bin" -v "$host" "$port"
      ;;
    2)
      port=$(ask_input "$bin" "Port k naslouchání:" "4444") || return
      echo ">>> $bin -lvnp $port"
      echo "(Ctrl+C ukončí)"
      if [[ "$bin" == "ncat" ]]; then
        "$bin" -lvnp "$port"
      else
        "$bin" -lvnp "$port" 2>/dev/null || "$bin" -l -v -p "$port"
      fi
      ;;
    3)
      host=$(ask_input "$bin" "Host:") || return
      port=$(ask_input "$bin" "Port:" "80") || return
      echo ">>> (echo -e 'HEAD / HTTP/1.0\\r\\n\\r\\n'; | $bin -w 3 $host $port)"
      # shellcheck disable=SC2086
      printf 'HEAD / HTTP/1.0\r\n\r\n' | "$bin" -w 3 "$host" "$port" || true
      ;;
    *) return ;;
  esac
  pause_return
}

socat_helper() {
  need_cmd socat || { pause_return; return; }
  local mode host port
  mode=$(run_menu "socat" "Režim:" 14 70 4 \
    "1" "TCP klient (STDIN/STDOUT ↔ host:port)" "TCP klient: stdin/stdout ↔ remote host:port." \
    "2" "TCP listen → STDIO" "TCP listener na portu, výstup na STDIO." \
    "3" "Port forward (local → remote)" "Port forward: local port → remote host:port." \
    "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
  ) || return
  clear
  case "$mode" in
    1)
      host=$(ask_input "socat" "Host:") || return
      port=$(ask_input "socat" "Port:" "80") || return
      echo ">>> socat - TCP:$host:$port"
      socat - "TCP:${host}:${port}"
      ;;
    2)
      port=$(ask_input "socat" "Lokální port:" "4444") || return
      echo ">>> socat TCP-LISTEN:$port,reuseaddr,fork STDIO"
      socat "TCP-LISTEN:${port},reuseaddr,fork" STDIO
      ;;
    3)
      local lport rhost rport
      lport=$(ask_input "socat" "Lokální port:" "8080") || return
      rhost=$(ask_input "socat" "Vzdálený host:") || return
      rport=$(ask_input "socat" "Vzdálený port:" "80") || return
      echo ">>> socat TCP-LISTEN:$lport,reuseaddr,fork TCP:$rhost:$rport"
      echo "(Ctrl+C ukončí)"
      socat "TCP-LISTEN:${lport},reuseaddr,fork" "TCP:${rhost}:${rport}"
      ;;
    *) return ;;
  esac
  pause_return
}

http_helpers() {
  local choice url
  choice=$(run_menu "HTTP (curl / wget)" "Akce:" 14 70 5 \
    "1" "curl -I (headers)" "curl -I — jen HTTP hlavičky odpovědi." \
    "2" "curl -v (verbose GET)" "curl -v — verbose GET s TLS detaily." \
    "3" "curl — zobrazit vlastní IP" "curl ifconfig.me — vaše veřejná IP." \
    "4" "wget — stáhnout soubor" "wget — stáhne soubor z URL." \
    "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
  ) || return
  clear
  case "$choice" in
    1)
      need_cmd curl || { pause_return; return; }
      url=$(ask_input "curl" "URL:" "https://example.com") || return
      echo ">>> curl -I \"$url\""
      curl -I "$url"
      ;;
    2)
      need_cmd curl || { pause_return; return; }
      url=$(ask_input "curl" "URL:" "https://example.com") || return
      echo ">>> curl -v \"$url\""
      curl -v "$url"
      ;;
    3)
      need_cmd curl || { pause_return; return; }
      echo ">>> curl -s https://ifconfig.me"
      curl -s --max-time 10 https://ifconfig.me; echo
      ;;
    4)
      need_cmd wget || { pause_return; return; }
      url=$(ask_input "wget" "URL ke stažení:") || return
      echo ">>> wget \"$url\""
      wget "$url"
      ;;
    *) return ;;
  esac
  pause_return
}

firewall_overview() {
  local choice
  choice=$(run_menu "Firewall (nft / iptables)" "Akce:" 14 70 5 \
    "1" "nft list ruleset" "nft list ruleset — kompletní pravidla nftables." \
    "2" "nft list tables" "nft list tables — seznam tabulek." \
    "3" "iptables -L -n -v" "iptables -L — pravidla filter tabulky." \
    "4" "iptables -t nat -L -n -v" "iptables -t nat — NAT pravidla." \
    "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
  ) || return
  clear
  case "$choice" in
    1) need_cmd nft && { echo ">>> sudo nft list ruleset"; run_sudo_or_plain nft list ruleset; } ;;
    2) need_cmd nft && { echo ">>> sudo nft list tables"; run_sudo_or_plain nft list tables; } ;;
    3) need_cmd iptables && { echo ">>> sudo iptables -L -n -v"; run_sudo_or_plain iptables -L -n -v; } ;;
    4) need_cmd iptables && { echo ">>> sudo iptables -t nat -L -n -v"; run_sudo_or_plain iptables -t nat -L -n -v; } ;;
    *) return ;;
  esac
  pause_return
}

crypto_helpers() {
  local choice
  choice=$(run_menu "Krypto (openssl / gpg)" "Akce:" 16 72 7 \
    "1" "openssl s_client — TLS handshake" "openssl s_client — TLS handshake a certifikát serveru." \
    "2" "openssl x509 — info o certifikátu" "openssl x509 — detail certifikátu ze souboru." \
    "3" "openssl rand — náhodná data" "openssl rand — kryptograficky náhodná data." \
    "4" "gpg --list-keys" "gpg --list-keys — veřejné a privátní klíče." \
    "5" "gpg — šifrovat soubor (-c)" "gpg -c — symetrické šifrování souboru." \
    "6" "gpg — dešifrovat soubor" "gpg -d — dešifrování .gpg souboru." \
    "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
  ) || return
  clear
  case "$choice" in
    1)
      need_cmd openssl || { pause_return; return; }
      local host
      host=$(ask_input "openssl" "Host[:port]:" "example.com:443") || return
      echo ">>> openssl s_client -connect $host -servername ${host%%:*} </dev/null"
      openssl s_client -connect "$host" -servername "${host%%:*}" </dev/null 2>&1 | head -n 80
      ;;
    2)
      need_cmd openssl || { pause_return; return; }
      local cert
      cert=$(ask_input "openssl" "Cesta k .pem/.crt:") || return
      echo ">>> openssl x509 -in \"$cert\" -noout -text | head"
      openssl x509 -in "$cert" -noout -text | head -n 80
      ;;
    3)
      need_cmd openssl || { pause_return; return; }
      echo ">>> openssl rand -hex 32"
      openssl rand -hex 32
      echo
      echo ">>> openssl rand -base64 32"
      openssl rand -base64 32
      ;;
    4)
      need_cmd gpg || { pause_return; return; }
      echo ">>> gpg --list-keys"
      gpg --list-keys
      echo
      echo ">>> gpg --list-secret-keys"
      gpg --list-secret-keys
      ;;
    5)
      need_cmd gpg || { pause_return; return; }
      local file
      file=$(ask_input "gpg" "Soubor k šifrování (symetricky -c):") || return
      echo ">>> gpg -c \"$file\""
      gpg -c "$file"
      ;;
    6)
      need_cmd gpg || { pause_return; return; }
      local file
      file=$(ask_input "gpg" "Soubor .gpg k dešifrování:") || return
      echo ">>> gpg -d \"$file\""
      gpg -d "$file"
      ;;
    *) return ;;
  esac
  pause_return
}

ip_link_overview() {
  need_cmd ip || { pause_return; return; }
  local choice
  choice=$(run_menu "iproute2" "Akce:" 14 65 5 \
    "1" "ip -c a (adresy)" "ip -c a — IP adresy rozhraní (barevně)." \
    "2" "ip -c r (routing)" "ip -c r — routing tabulka." \
    "3" "ip -c link" "ip -c link — stav síťových rozhraní." \
    "4" "ip neigh" "ip neigh — ARP / sousedé." \
    "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
  ) || return
  clear
  case "$choice" in
    1) echo ">>> ip -c a"; ip -c a ;;
    2) echo ">>> ip -c r"; ip -c r ;;
    3) echo ">>> ip -c link"; ip -c link ;;
    4) echo ">>> ip neigh"; ip neigh ;;
    *) return ;;
  esac
  pause_return
}

docker_menu() {
  need_cmd docker || { pause_return; return; }
  while true; do
    local choice
    choice=$(run_menu "Docker (lab)" "Akce:" 16 70 7 \
      "1" "docker ps -a" "docker ps -a — všechny kontejnery." \
      "2" "docker images" "docker images — lokální image." \
      "3" "docker stats (snapshot)" "docker stats — snapshot využití CPU/RAM." \
      "4" "docker system df" "docker system df — využití disku Dockerem." \
      "5" "docker logs (kontejner)" "docker logs — posledních 100 řádků logu kontejneru." \
      "6" "docker exec -it (shell)" "docker exec -it — interaktivní shell v kontejneru." \
      "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
    ) || return
    case "$choice" in
      1) clear; echo ">>> docker ps -a"; docker ps -a; pause_return ;;
      2) clear; echo ">>> docker images"; docker images; pause_return ;;
      3) clear; echo ">>> docker stats --no-stream"; docker stats --no-stream; pause_return ;;
      4) clear; echo ">>> docker system df"; docker system df; pause_return ;;
      5)
        local cid
        cid=$(ask_input "docker logs" "Container name/ID:") || continue
        clear
        echo ">>> docker logs --tail 100 \"$cid\""
        docker logs --tail 100 "$cid"
        pause_return
        ;;
      6)
        local cid shell
        cid=$(ask_input "docker exec" "Container name/ID:") || continue
        shell=$(ask_input "docker exec" "Shell:" "/bin/sh") || continue
        clear
        echo ">>> docker exec -it \"$cid\" $shell"
        docker exec -it "$cid" "$shell"
        pause_return
        ;;
      0|"") return ;;
    esac
  done
}

utils_menu() {
  while true; do
    local choice
    choice=$(run_menu "11) Síťové & systémové utility" "Vyberte akci:" 18 72 9 \
      "1" "Sokety: ss / lsof / netstat" "Přehled soketů: ss, lsof, netstat." \
      "2" "ncat / nc — connect & listen" "ncat/nc — TCP klient, listener, banner grab." \
      "3" "socat — relay / forward" "socat — TCP relay, port forward, STDIO bridge." \
      "4" "HTTP: curl / wget" "curl / wget — HTTP requesty a stahování." \
      "5" "ip — adresy / routing / neigh" "ip — adresy, routing, link, ARP tabulka." \
      "6" "Firewall: nft / iptables" "nft / iptables — zobrazení pravidel firewallu." \
      "7" "Krypto: openssl / gpg" "openssl / gpg — TLS, certifikáty, šifrování." \
      "8" "Docker (lab)" "Docker — kontejnery, image, logy, exec." \
      "0" "Zpět" "Návrat do nadřazeného menu bez spuštění akce."
    ) || return
    case "$choice" in
      1) sockets_overview ;;
      2) ncat_connect ;;
      3) socat_helper ;;
      4) http_helpers ;;
      5) ip_link_overview ;;
      6) firewall_overview ;;
      7) crypto_helpers ;;
      8) docker_menu ;;
      0|"") return ;;
    esac
  done
}

# =============================================================================
# 12) Background scripts
# =============================================================================

show_background_scripts() {
  clear
  echo ">>> Běžící uživatelské skripty (.sh / .py)"
  echo
  ps aux | grep -E '\.sh|\.py' | grep -v --color=never 'grep -E' || true
  echo
  pause_return
}

# =============================================================================
# Main
# =============================================================================

main_menu() {
  while true; do
    local choice
    choice=$(run_menu "Hlavní menu" "Vyberte kategorii:" 24 76 14 \
      "1" "Recon & Scanning" "Průzkum sítě: port skeny, capture paketů, DNS, TLS.\nNástroje: nmap, masscan, tshark, Wireshark…" \
      "2" "Web App Testing" "Testování webových aplikací: fuzzing, fingerprint, WAF, SQLi.\nPouze na autorizovaných cílech!" \
      "3" "Hesla & Autentizace" "Útoky na hesla online (hydra) i offline (john, hashcat).\nPouze v labu nebo s písemným povolením." \
      "4" "Systémové procesy & diagnostika" "Diagnostika procesů: strace, ltrace, GDB debugger." \
      "5" "Reverse & Binary" "Reverse engineering: radare2, binwalk, yara, strings, objdump." \
      "6" "Wireless (aircrack-ng)" "Bezdrátové sítě: airmon-ng, airodump-ng, aircrack-ng.\nPouze na autorizovaných cílech!" \
      "7" "Bezpečnost & Forenzní analýza" "Blue team: Lynis, forenzní nástroje, AV, integrita systému." \
      "8" "SMB / Impacket (lab)" "SMB klient a Impacket skripty pro AD lab.\nPouze na autorizovaných cílech!" \
      "9" "Proxy / OpSec" "Anonymizace: proxychains, Tor — směrování provozu přes proxy." \
      "10" "OSINT — osoby (e-mail / username / tel.)" "OSINT na osoby: e-mail, username, telefon.\nPouze legálně — vlastní údaje nebo s povolením." \
      "11" "Síťové & systémové utility" "Síťové CLI: ss, curl, ip, nft, openssl, docker…" \
      "12" "Rychlý přehled skriptů na pozadí" "Přehled běžících .sh a .py skriptů (ps aux | grep)." \
      "0" "Konec / Exit" "Ukončí TUI menu a vrátí se do shellu."
    ) || {
      clear
      exit 0
    }

    case "$choice" in
      1) recon_menu ;;
      2) web_menu ;;
      3) auth_menu ;;
      4) system_menu ;;
      5) reverse_menu ;;
      6) wireless_menu ;;
      7) blue_menu ;;
      8) smb_impacket_menu ;;
      9) proxy_menu ;;
      10) osint_menu ;;
      11) utils_menu ;;
      12) show_background_scripts ;;
      0) clear; exit 0 ;;
    esac
  done
}

main_menu
