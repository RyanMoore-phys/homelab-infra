#!/usr/bin/env bash
# Fails if a tracked file contains data that identifies the real lab:
# private IPv4 addresses, Tailscale (CGNAT) addresses, tailnet DNS names,
# email addresses, MAC addresses, SSH public/private keys.
# Examples must use the RFC 5737 documentation ranges (192.0.2.0/24,
# 198.51.100.0/24, 203.0.113.0/24). The CGNAT block itself (100.64.0.0/10)
# is a well-known constant and is allowed.
set -euo pipefail
cd "$(dirname "$0")/.."

list_files() {
  if git rev-parse --git-dir >/dev/null 2>&1; then git ls-files --cached --others --exclude-standard
  else find . -type f -not -path './.git/*' | sed 's|^\./||'; fi
}

o='(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])'
patterns=(
  "rfc1918|(^|[^0-9.])(10\.${o}\.${o}\.${o}|172\.(1[6-9]|2[0-9]|3[01])\.${o}\.${o}|192\.168\.${o}\.${o})([^0-9]|$)"
  "tailscale-ip|(^|[^0-9.])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.${o}\.${o}([^0-9/]|$)"
  "tailnet-name|[a-z0-9-]+\.ts\.net"
  "email|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.(com|net|org|io|dev|edu|me|co)([^A-Za-z]|$)"
  "mac-address|([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}"
  "ssh-key|(ssh-(ed25519|rsa|dss)|ecdsa-sha2-nistp[0-9]+|sk-ssh-ed25519@openssh\.com) AAAA"
  "private-key|-----BEGIN [A-Z ]*PRIVATE KEY-----"
)

fail=0; count=0
while IFS= read -r f; do
  count=$((count+1))
  [ -f "$f" ] || continue
  case "$f" in scripts/check-private-data.sh|LICENSE) continue ;; esac
  for p in "${patterns[@]}"; do
    name=${p%%|*}; rx=${p#*|}
    if hits=$(grep -nE "$rx" "$f" 2>/dev/null); then
      # report line numbers only, never the matching text
      echo "PRIVATE DATA ($name) in $f at line(s): $(echo "$hits" | cut -d: -f1 | tr '\n' ' ')"
      fail=1
    fi
  done
done < <(list_files)
[ $fail -eq 0 ] && echo "check-private-data: clean ($count files)"
exit $fail
