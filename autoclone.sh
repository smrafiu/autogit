#!/usr/bin/env bash
(
VERSION="1.0.0"
NAME="autoclone"

T_TITLE="GITHUB AUTO CLONER"
T_OK="CLONED SUCCESSFULLY"
T_NO="CLONE FAILED"
S_1="CONFIGURATION"
S_2="EXECUTION"
S_3="RESULT"
L_FOLDER="Folder Path"
L_REPO="Repo URL"
L_TOKEN="Access Token"
L_PROG="Downloading from GitHub"
LAB=$L_PROG

A_FOLDER=""; A_REPO=""
NI=0; NOCOLOR=0; TOKSTDIN=0; FULL=0

usage() {
  printf 'Usage: %s [options]\n\n' "$NAME"
  printf '  --folder PATH     destination folder (default: current folder)\n'
  printf '  --repo URL        https://github.com/owner/repo or owner/repo\n'
  printf '  --full            entire history and all branches (default: latest commit)\n'
  printf '  --token-stdin     read the token from stdin (private repositories)\n'
  printf '  --yes             never prompt\n'
  printf '  --no-color        plain output\n'
  printf '  --version, --help\n\n'
  printf 'Token: AUTOCLONE_TOKEN environment variable or --token-stdin\n'
}

need() { [ "$1" -ge 2 ] || { usage; exit 2; }; }

while [ $# -gt 0 ]; do
  case $1 in
    --folder)  need $#; A_FOLDER=$2; shift 2 ;;
    --repo)    need $#; A_REPO=$2; shift 2 ;;
    --full)    FULL=1; shift ;;
    --token-stdin) TOKSTDIN=1; shift ;;
    --yes|-y)  NI=1; shift ;;
    --no-color) NOCOLOR=1; shift ;;
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    --help|-h) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

FANCY=0
[ -t 1 ] && [ "$NOCOLOR" = 0 ] && [ -z "${NO_COLOR:-}" ] && FANCY=1

if [ "$FANCY" = 1 ]; then
  R=$'\033[0m'; D=$'\033[2m'
  C=$'\033[1;36m'; G=$'\033[1;32m'; Y=$'\033[1;33m'; E=$'\033[1;31m'
  M=$'\033[1;35m'; MD=$'\033[2;35m'; WT=$'\033[1;37m'
  GBG=$'\033[42m'; XBG=$'\033[48;5;238m'
else
  R=; D=; C=; G=; Y=; E=; M=; MD=; WT=; GBG=; XBG=
fi

is_termux() { case ${PREFIX:-} in */com.termux/*) return 0 ;; esac; return 1; }

term_cols() {
  local s c
  s=$(stty size 2>/dev/null </dev/tty); c=${s#* }
  case $c in ''|*[!0-9]*|0) c=$(tput cols 2>/dev/null </dev/tty) ;; esac
  case $c in ''|*[!0-9]*|0) c=${COLUMNS:-} ;; esac
  case $c in ''|*[!0-9]*|0) c=44 ;; esac
  printf '%s' "$c"
}

COLS=$(term_cols)
[ "$COLS" -lt 32 ] && COLS=32
WD=$((COLS - 1))
[ "$WD" -gt 60 ] && WD=60

if [ -t 0 ]; then rd() { read "$@"; }; else rd() { read "$@" </dev/tty; }; fi

LOG=$(mktemp 2>/dev/null || echo "$HOME/.autoclone.log")
trap 'rm -f "$LOG"; ctl echoctl' EXIT
ctl() { [ "$FANCY" = 1 ] && stty "$1" 2>/dev/null </dev/tty; }

quit() {
  stty echo 2>/dev/null
  ctl echoctl
  [ "$CLONING" = 1 ] && [ -n "$DEST" ] && rm -rf "$DEST"
  if [ "$BARON" = 1 ]; then
    printf '\r\033[2A\033[J'
    bad "Cancelled"
  else
    printf '\n'
  fi
  exit 130
}
trap quit INT

TOKEN=""; SLUG=""; BR=""; HASH=""; NFILES=""; DEST=""; GH_LOGIN=""
BARON=0; ER=0; INSTALL_PID=""; FROMENV=0; PUBLIC=0; CLONING=0

rep() { printf '%*s' "$2" '' | tr ' ' "$1"; }

spread() {
  local s=$1 o="" i c
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    if [ "$c" = " " ]; then o+="  "; else o+="$c "; fi
  done
  printf '%s' "${o% }"
}

banner() {
  local t line
  t=$(spread "$2")
  [ "${#t}" -gt "$WD" ] && t=$2
  line=$(rep = "$WD")
  printf '%s%s%s\n\n' "$1" "$line" "$R"
  printf '%s%*s%s%s\n\n' "$1" $(( (WD - ${#t}) / 2 )) '' "$t" "$R"
  printf '%s%s%s\n' "$1" "$line" "$R"
}

section() {
  local head="STEP $1/3  $2 "
  printf '\n%s%s%s%s%s\n' "$M" "$head" "$MD" "$(rep - $((WD - ${#head})))" "$R"
}

fit() {
  local s=${1//$'\n'/ } max=$2
  [ "$max" -lt 4 ] && max=4
  [ "${#s}" -gt "$max" ] && s="${s:0:$((max - 1))}…"
  printf '%s' "$s"
}


ok()    { printf '%s✔%s %s\n' "$G" "$R" "$1"; }
bad()   { printf '%s✘ %s%s\n' "$E" "$1" "$R"; }
step()  { ok "${WT}$1${R} ${D}· $(fit "$2" $((WD - ${#1} - 5)))${R}"; }
field() { ok "${C}$1:${R} ${3:-$WT}$(fit "$2" $((WD - ${#1} - 4)))${R}"; }
res()   { ok "${C}$1${R} ${D}·${R} ${WT}$(fit "$2" $((WD - ${#1} - 5)))${R}"; }
note()  { printf '%s•%s %s%s%s %s·%s %s%s%s\n' "$D" "$R" "$C" "$1" "$R" "$D" "$R" "$WT" "$(fit "$2" $((WD - ${#1} - 5)))" "$R"; }

fail_row() {
  local first=1 l
  while IFS= read -r l; do
    if [ "$first" = 1 ]; then
      printf '%s✘ %s%s\n' "$E" "$l" "$R"
      first=0
    else
      printf '%s  %s%s\n' "$E" "$l" "$R"
    fi
  done <<<"$(printf '%s' "$1" | fold -s -w $((WD - 2)))"
}

tilde() {
  case $1 in
    "$HOME"*) printf '~%s' "${1#"$HOME"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

scrub() {
  local s=$1
  [ -n "$TOKEN" ] && s=${s//$TOKEN/***}
  printf '%s' "$s"
}

now() {
  if [ -n "${EPOCHREALTIME:-}" ]; then printf '%s' "${EPOCHREALTIME//[.,]/}"
  else printf '%s' "$(( $(date +%s) * 1000000 ))"; fi
}

elapsed() {
  local d=$(( ($2 - $1) / 100000 ))
  printf '%d.%d' $((d / 10)) $((d % 10))
}

rows() { local n=$(( ($1 + COLS - 1) / COLS )); [ "$n" -lt 1 ] && n=1; echo "$n"; }
wipe() { [ "$FANCY" = 1 ] && [ "$ER" -gt 0 ] && printf '\033[%dA\r\033[J' "$ER"; ER=0; }
info() { printf '  %s%s%s %s\n' "$C" "$1" "$R" "$2"; ER=$((ER + $(rows $((${#1} + ${#2} + 3))))); }
err()  { bad "$1"; ER=$((ER + $(rows $((${#1} + 2))))); }

ask() {
  printf '  %s%s%s ' "$C" "$1" "$R"
  rd -r V_IN || quit
  ER=$((ER + $(rows $((${#1} + ${#V_IN} + 3)))))
}

confirm() {
  local p="$1 (Y/n):"
  printf '  %s%s%s ' "$C" "$p" "$R"
  rd -r YN || quit
  ER=$((ER + $(rows $((${#p} + ${#YN} + 3)))))
  case $YN in [Nn]*) return 1 ;; esac
  return 0
}

ask_secret() {
  local ch
  V_IN=""
  printf '  %s%s%s ' "$C" "$1" "$R"
  while IFS= rd -r -s -n1 ch; do
    [ -z "$ch" ] && break
    if [ "$ch" = $'\x7f' ] || [ "$ch" = $'\b' ]; then
      [ -n "$V_IN" ] && { V_IN=${V_IN%?}; printf '\b \b'; }
    else
      V_IN+=$ch
      printf '*'
    fi
  done
  printf '\n'
  ER=$((ER + $(rows $((${#1} + ${#V_IN} + 3)))))
}

resolve() {
  local p=$1
  case $p in
    [A-Za-z]:[\\/]*|*\\*) command -v cygpath >/dev/null 2>&1 && p=$(cygpath -u "$p") ;;
  esac
  case $p in
    "~"*) p=$HOME${p#"~"} ;;
    /*) ;;
    *) if [ -d "$HOME/storage/shared" ]; then p=$HOME/storage/shared/$p; else p=$PWD/$p; fi ;;
  esac
  printf '%s' "${p%/}"
}

usable() { [ -d "$1" ] && [ -w "$1" ] && [ -x "$1" ]; }

clean_url() {
  local u=$1
  case $u in git@github.com:*) u=https://github.com/${u#git@github.com:} ;; esac
  case $u in github.com/*) u=https://$u ;; esac
  u=$(printf '%s' "$u" | sed -E 's#^(https?://)[^/@]+@#\1#')
  printf '%s' "${u%/}"
}

norm_repo() {
  local u
  u=$(clean_url "$1")
  [[ $u =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] && u=https://github.com/$u
  printf '%s' "$u"
}

valid_repo() {
  [[ $1 =~ ^https://github\.com/([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)$ ]] || return 1
  case ${BASH_REMATCH[1]}:${BASH_REMATCH[2]} in .:*|..:*|*:.|*:..|*:.git) return 1 ;; esac
  return 0
}

api() {
  local out
  out=$(printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" | curl -sS -K - \
    --connect-timeout 6 --max-time 15 -H "Accept: application/vnd.github+json" \
    -w '\n%{http_code}' "https://api.github.com$1" 2>/dev/null)
  API_CODE=${out##*$'\n'}
  API_BODY=${out%$'\n'*}
}

spin() {
  local f='|/-\' i=0
  if [ "$FANCY" = 1 ]; then
    while kill -0 "$1" 2>/dev/null; do
      printf '\r  %s%s%s %s' "$Y" "${f:$((i++ % 4)):1}" "$R" "$2"
      sleep 0.1
    done
    printf '\r\033[2K'
  fi
  wait "$1" 2>/dev/null
}

wait_install() {
  [ -z "$INSTALL_PID" ] && return
  spin "$INSTALL_PID" "$1"
  INSTALL_PID=""
}

bar() {
  local p=$1 lab="  $LAB" pc f row
  pc=$(printf '%3d%%' "$p")
  f=$(( p * WD / 100 ))
  row=$(printf '%s%*s%s%*s%s' "$GBG" "$f" '' "$XBG" $((WD - f)) '' "$R")
  printf '\r\033[2A\033[2K%s%s%*s%s%s\n' "$WT" "$lab" $((WD - ${#lab} - ${#pc})) '' "$pc" "$R"
  printf '\033[2K%s\n\033[2K%s' "$row" "$row"
}

feed() {
  local c p=0 top=0
  local re_r='Receiving objects: +([0-9]+)%'
  local re_d='Resolving deltas: +([0-9]+)%'
  local re_c='Compressing objects: +([0-9]+)%'
  local re_n='Counting objects: +([0-9]+)%'
  while IFS= read -r -d $'\r' c || [ -n "$c" ]; do
    printf '%s\n' "$c" >>"$LOG"
    [ "$FANCY" = 1 ] || continue
    if   [[ $c =~ $re_r ]]; then p=$(( 20 + BASH_REMATCH[1] * 65 / 100 ))
    elif [[ $c =~ $re_d ]]; then p=$(( 85 + BASH_REMATCH[1] * 14 / 100 ))
    elif [[ $c =~ $re_c ]]; then p=$(( 10 + BASH_REMATCH[1] * 10 / 100 ))
    elif [[ $c =~ $re_n ]]; then p=$(( BASH_REMATCH[1] * 10 / 100 ))
    else continue
    fi
    [ "$p" -gt 99 ] && p=99
    if [ "$p" -gt "$top" ]; then top=$p; bar "$p"; fi
  done
}

hint() {
  if   grep -qiE 'not accessible by|returned error: 403' "$LOG"; then
    echo "The token cannot read this repository. It needs 'Contents: Read-only' (fine-grained) or the 'repo' scope (classic)."
  elif grep -qiE 'authentication failed|returned error: 401|invalid username|could not read username' "$LOG"; then
    echo "The token is wrong or has expired."
  elif grep -qiE 'repository .*not found|returned error: 404' "$LOG"; then
    echo "The repository was not found, or the token has no access to it."
  elif grep -qiE 'early eof|rpc failed|invalid index-pack|unexpected disconnect|connection reset|too slow|transfer closed' "$LOG"; then
    echo "The connection was interrupted. Try again on a stronger network."
  elif grep -qiE 'could not resolve|failed to connect|timed out' "$LOG"; then
    echo "No internet connection."
  elif grep -qiE 'no space left' "$LOG"; then
    echo "Not enough storage space on this device."
  elif grep -qiE 'already exists and is not an empty' "$LOG"; then
    echo "The destination folder is not empty."
  fi
}

retryable() {
  grep -qiE 'authentication failed|returned error: (401|403|404)|not found|no space left|already exists|could not read username' "$LOG" && return 1
  grep -qiE 'early eof|rpc failed|curl [0-9]+|connection (reset|timed out)|unexpected disconnect|transfer closed|hung up|timed out|could not resolve|failed to connect|too slow|invalid index-pack|ssl|tls' "$LOG"
}

show_log() {
  local m l
  [ -s "$LOG" ] || return
  m=$(tr '\r' '\n' <"$LOG" | grep -E '^(fatal|error|remote)' | tail -n 3)
  [ -z "$m" ] && m=$(tr '\r' '\n' <"$LOG" | grep -v '^$' | tail -n 3)
  while IFS= read -r l; do
    [ -n "$l" ] && printf '  %s%s%s\n' "$D" "$(fit "$(scrub "$l")" $((WD - 2)))" "$R"
  done <<<"$m"
}

fail_exit() {
  local code=${3:-1}
  [ "$BARON" = 1 ] && { printf '\r\033[2A\033[J'; BARON=0; }
  section 3 "$S_3"
  [ -n "$SLUG" ] && note Repo "$SLUG"
  [ -n "$BR" ] && note Branch "$BR"
  [ -n "$HASH" ] && note Commit "$HASH"
  [ -n "$DEST" ] && note Folder "$(tilde "$DEST")"
  fail_row "Error · $1"
  fail_row "Reason · $(scrub "$2")"
  show_log
  printf '\n'
  banner "$E" "$T_NO"
  printf '\n'
  exit "$code"
}

missing() {
  if is_termux; then echo "Run: pkg install $1"; else echo "Install $1, then run again."; fi
}

tok_err() {
  [ "$FROMENV" = 1 ] && fail_exit "$2" "$1" 2
  TOKEN=""
  err "$1"
}

[ "$FANCY" = 1 ] && [ "$NI" = 0 ] && clear
banner "$C" "$T_TITLE"

if is_termux && { ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; }; then
  ( pkg install -y git curl || { pkg update -y && pkg install -y git curl; } ) >/dev/null 2>&1 </dev/null &
  INSTALL_PID=$!
fi
if is_termux && [ ! -d "$HOME/storage/shared" ] && command -v termux-setup-storage >/dev/null 2>&1; then
  termux-setup-storage >/dev/null 2>&1
fi

section 1 "$S_1"

FOLDER=""
if [ -n "$A_FOLDER" ]; then
  P=$(resolve "$A_FOLDER")
  usable "$P" || fail_exit "Folder not found" "$A_FOLDER" 2
  FOLDER=$P
elif [ "$NI" = 1 ]; then
  FOLDER=$PWD
else
  if [ "$PWD" != "$HOME" ]; then
    info "$L_FOLDER:" "$(tilde "$PWD")"
    confirm "Use this folder?" && FOLDER=$PWD
  fi
  while [ -z "$FOLDER" ]; do
    ask "$L_FOLDER:"
    P=$(resolve "$V_IN")
    if [ -n "$V_IN" ] && usable "$P"; then
      FOLDER=$P
    else
      err "Folder not found. Enter the path again."
    fi
  done
  wipe
fi
field "$L_FOLDER" "$(tilde "$FOLDER")"

REPO=""
if [ -n "$A_REPO" ]; then
  U=$(norm_repo "$A_REPO")
  valid_repo "$U" || fail_exit "Invalid repo URL" "Use https://github.com/owner/repo" 2
  REPO=$U
elif [ "$NI" = 1 ]; then
  fail_exit "Repo URL missing" "Use --repo https://github.com/owner/repo" 2
else
  while [ -z "$REPO" ]; do
    ask "$L_REPO:"
    U=$(norm_repo "$V_IN")
    if valid_repo "$U"; then
      REPO=$U
    else
      err "Not a GitHub repo link (https://github.com/owner/repo)."
    fi
  done
  wipe
fi
field "$L_REPO" "$REPO"

SLUG=${REPO#https://github.com/}
SLUG=${SLUG%.git}
DIRNAME=${SLUG#*/}

command -v git >/dev/null 2>&1 || wait_install "Installing git (first run only)..."
command -v git >/dev/null 2>&1 || fail_exit "git is not installed" "$(missing git)" 2

probe() {
  GIT_TERMINAL_PROMPT=0 GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=15 \
    git -c credential.helper= ls-remote "$REPO" HEAD >"$LOG" 2>&1
}
probe &
spin $! "Checking repository..."
PRB=$?
if [ "$PRB" -eq 0 ]; then
  PUBLIC=1
elif grep -qiE 'could not resolve|failed to connect|timed out|network is unreachable' "$LOG"; then
  fail_exit "Cannot reach GitHub" "Check your internet connection."
fi
: >"$LOG"

if [ "$PUBLIC" = 0 ]; then
  command -v curl >/dev/null 2>&1 || wait_install "Preparing tools..."
  command -v curl >/dev/null 2>&1 || fail_exit "curl is not installed" "$(missing curl)" 2
  CAND=${AUTOCLONE_TOKEN:-}
  [ "$TOKSTDIN" = 1 ] && IFS= read -r CAND
  [ -n "$CAND" ] && FROMENV=1
  [ "$NI" = 0 ] && [ -z "$CAND" ] && info "Private repo:" "a token is required"
  while [ -z "$TOKEN" ]; do
    if [ -n "$CAND" ]; then
      T=$CAND; CAND=""
    else
      [ "$NI" = 1 ] && fail_exit "Access token missing" "This repository is private. Set AUTOCLONE_TOKEN or use --token-stdin" 2
      ask_secret "$L_TOKEN:"
      T=$V_IN
    fi
    if [ "${#T}" -lt 20 ] || [[ $T == *[[:space:]]* ]]; then
      tok_err "That does not look like a GitHub token." "Invalid token"
      continue
    fi
    TOKEN=$T
    api /user
    case $API_CODE in
      200) GH_LOGIN=$(sed -n 's/.*"login": *"\([^"]*\)".*/\1/p' <<<"$API_BODY" | head -n 1) ;;
      401) tok_err "GitHub rejected this token." "Token rejected" ;;
      000|"") tok_err "Cannot reach GitHub. Check your internet." "No connection" ;;
      *) tok_err "GitHub returned HTTP $API_CODE." "GitHub error" ;;
    esac
  done
  wipe
  field "$L_TOKEN" "$(rep '*' $(( ${#TOKEN} > 24 ? 24 : ${#TOKEN} )))"
fi

section 2 "$S_2"

step "Git ready" "v$(git --version | awk '{print $3}')"

VIS=public
if [ "$PUBLIC" = 0 ]; then
  VIS=private
  step "Account verified" "$GH_LOGIN"
  api "/repos/$SLUG"
  case $API_CODE in
    200) ;;
    404) fail_exit "Repository not found" "Check the URL, and make sure the token has access to this repository." ;;
    401|403) fail_exit "Token cannot access this repository" "Check the token's repository access and expiry." ;;
    000|"") fail_exit "Cannot reach GitHub" "Check your internet connection." ;;
    *) fail_exit "GitHub returned HTTP $API_CODE" "Try again in a moment." ;;
  esac
  grep -Eq '"pull": *false' <<<"$API_BODY" && fail_exit "No read access to $SLUG" "The token cannot read this repository."
fi
step "Repository found" "$SLUG"
step "Visibility" "$VIS"

DEST=$FOLDER/$DIRNAME
N=2
while [ -e "$DEST" ] && { [ ! -d "$DEST" ] || [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; }; do
  [ "$N" -gt 999 ] && fail_exit "Destination unavailable" "Too many folders named $DIRNAME."
  DEST=$FOLDER/$DIRNAME-$N
  N=$((N + 1))
done
step "Destination ready" "$(tilde "$DEST")"

GARGS=(-c credential.helper= -c http.version=HTTP/1.1 -c http.lowSpeedLimit=500 -c http.lowSpeedTime=120)
[ "$PUBLIC" = 0 ] && GARGS+=(-c 'credential.helper=!f() { test "$1" = get && printf "username=x-access-token\npassword=%s\n" "$AUTOCLONE_PW"; }; f')
CARGS=(--progress)
[ "$FULL" = 0 ] && CARGS+=(--depth 1)

MAXTRY=4
ATT=1
CLONING=1
T0=$(now)
if [ "$FANCY" = 1 ]; then
  printf '\n\n'
  BARON=1
  ctl -echoctl
  bar 0
fi
while :; do
  : >"$LOG"
  AUTOCLONE_PW=$TOKEN GIT_TERMINAL_PROMPT=0 \
    git "${GARGS[@]}" clone "${CARGS[@]}" "$REPO" "$DEST" 2>&1 | feed
  PS=${PIPESTATUS[0]}
  [ "$PS" -eq 0 ] && break
  [ "$ATT" -ge "$MAXTRY" ] && break
  retryable || break
  rm -rf "$DEST"
  ATT=$((ATT + 1))
  LAB="Retrying download ($ATT/$MAXTRY)"
  [ "$FANCY" = 1 ] && bar 0
  sleep $((ATT * 2))
done
CLONING=0
ctl echoctl
T1=$(now)
if [ "$PS" -eq 0 ]; then
  if [ "$FANCY" = 1 ]; then
    bar 100
    sleep 0.3
    printf '\r\033[2A\033[J'
    BARON=0
  fi
  BR=$(git -C "$DEST" symbolic-ref --short -q HEAD)
  BR=${BR:-main}
  step "Cloned from GitHub" "$BR"
else
  WHY=$(hint)
  rm -rf "$DEST"
  fail_exit "Clone failed" "${WHY:-Unknown error. See the log below.}"
fi

HASH=$(git -C "$DEST" rev-parse --short HEAD 2>/dev/null)
NFILES=$(git -C "$DEST" ls-files | wc -l | tr -d ' ')
SECS=$(elapsed "$T0" "$T1")
HIST="latest commit"
[ "$FULL" = 1 ] && HIST="full history"

section 3 "$S_3"
res Repo "$SLUG"
res Branch "$BR"
[ -n "$HASH" ] && res Commit "$HASH"
res Files "$NFILES"
res History "$HIST"
res Folder "$(tilde "$DEST")"
res Time "${SECS}s"
printf '\n'
banner "$G" "$T_OK"
printf '\n'
)
