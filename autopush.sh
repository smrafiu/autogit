#!/usr/bin/env bash
(
VERSION="1.0.0"
NAME="autopush"

T_TITLE="GITHUB AUTO PUSHER"
T_OK="PUSHED SUCCESSFULLY"
T_NO="PUSH FAILED"
S_1="CONFIGURATION"
S_2="EXECUTION"
S_3="RESULT"
L_FOLDER="Folder Path"
L_REPO="Repo URL"
L_MSG="Commit Message"
L_DESC="Description (optional)"
L_TOKEN="Access Token"
L_PROG="Uploading to GitHub"

A_FOLDER=""; A_REPO=""; A_MSG=""; A_DESC=""
NI=0; NOCOLOR=0; TOKSTDIN=0

usage() {
  printf 'Usage: %s [options]\n\n' "$NAME"
  printf '  --folder PATH     folder to push\n'
  printf '  --repo URL        https://github.com/owner/repo\n'
  printf '  --message TEXT    commit message\n'
  printf '  --desc TEXT       commit description\n'
  printf '  --token-stdin     read the token from stdin\n'
  printf '  --yes             never prompt\n'
  printf '  --no-color        plain output\n'
  printf '  --version, --help\n\n'
  printf 'Token: AUTOPUSH_TOKEN environment variable or --token-stdin\n'
}

need() { [ "$1" -ge 2 ] || { usage; exit 2; }; }

while [ $# -gt 0 ]; do
  case $1 in
    --folder)  need $#; A_FOLDER=$2; shift 2 ;;
    --repo)    need $#; A_REPO=$2; shift 2 ;;
    --message) need $#; A_MSG=$2; shift 2 ;;
    --desc)    need $#; A_DESC=$2; shift 2 ;;
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

LOG=$(mktemp 2>/dev/null || echo "$HOME/.autopush.log")
trap 'rm -f "$LOG"' EXIT
quit() { stty echo 2>/dev/null; printf '\n'; exit 130; }
trap quit INT

TOKEN=""; SLUG=""; BR=""; HASH=""; NFILES=""; MSG=""; DESC=""
BARON=0; ER=0; INSTALL_PID=""; FROMENV=0

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
step()  { ok "${WT}$1${R} ${D}· $2${R}"; }
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

clean_url() {
  local u=$1
  case $u in git@github.com:*) u=https://github.com/${u#git@github.com:} ;; esac
  u=$(printf '%s' "$u" | sed -E 's#^(https?://)[^/@]+@#\1#')
  printf '%s' "${u%/}"
}

valid_repo() { [[ $1 =~ ^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; }

api() {
  local out
  out=$(printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" | curl -sS -K - \
    --connect-timeout 6 --max-time 15 -H "Accept: application/vnd.github+json" \
    -w '\n%{http_code}' "https://api.github.com$1" 2>/dev/null)
  API_CODE=${out##*$'\n'}
  API_BODY=${out%$'\n'*}
}

wait_install() {
  [ -z "$INSTALL_PID" ] && return
  local f='|/-\' i=0
  while kill -0 "$INSTALL_PID" 2>/dev/null; do
    printf '\r  %s%s%s %s' "$Y" "${f:$((i++ % 4)):1}" "$R" "$1"
    sleep 0.1
  done
  wait "$INSTALL_PID" 2>/dev/null
  INSTALL_PID=""
  printf '\r\033[2K'
}

bar() {
  local p=$1 lab="  $L_PROG" pc f row
  pc=$(printf '%3d%%' "$p")
  f=$(( p * WD / 100 ))
  row=$(printf '%s%*s%s%*s%s' "$GBG" "$f" '' "$XBG" $((WD - f)) '' "$R")
  printf '\r\033[2A\033[2K%s%s%*s%s%s\n' "$WT" "$lab" $((WD - ${#lab} - ${#pc})) '' "$pc" "$R"
  printf '\033[2K%s\n\033[2K%s' "$row" "$row"
}

feed() {
  local c p=0 top=0
  local re_w='Writing objects: +([0-9]+)%'
  local re_c='Compressing objects: +([0-9]+)%'
  local re_n='Counting objects: +([0-9]+)%'
  while IFS= read -r -d $'\r' c || [ -n "$c" ]; do
    printf '%s\n' "$c" >>"$LOG"
    [ "$FANCY" = 1 ] || continue
    if   [[ $c =~ $re_w ]]; then p=$(( 45 + BASH_REMATCH[1] * 55 / 100 ))
    elif [[ $c =~ $re_c ]]; then p=$(( 15 + BASH_REMATCH[1] * 30 / 100 ))
    elif [[ $c =~ $re_n ]]; then p=$(( BASH_REMATCH[1] * 15 / 100 ))
    else continue
    fi
    [ "$p" -gt 99 ] && p=99
    if [ "$p" -gt "$top" ]; then top=$p; bar "$p"; fi
  done
}

hint() {
  if   grep -qiE 'GH006|protected branch' "$LOG"; then
    echo "The branch is protected and does not accept direct pushes."
  elif grep -qiE 'GH001|exceeds GitHub|large files detected' "$LOG"; then
    echo "A file is larger than the 100 MB limit of GitHub."
  elif grep -qiE 'refusing to allow .* workflow' "$LOG"; then
    echo "The token needs the 'workflow' scope to push workflow files."
  elif grep -qiE 'not accessible by|permission to .* denied|returned error: 403' "$LOG"; then
    echo "The token cannot write to this repository. It needs 'Contents: Read and write' (fine-grained) or the 'repo' scope (classic)."
  elif grep -qiE 'authentication failed|returned error: 401|invalid username' "$LOG"; then
    echo "The token is wrong or has expired."
  elif grep -qiE 'rejected|fetch first|non-fast-forward|unrelated histor' "$LOG"; then
    echo "The repository already has commits that this folder does not have."
  elif grep -qiE 'could not resolve|failed to connect|timed out' "$LOG"; then
    echo "No internet connection."
  elif grep -qiE 'src refspec' "$LOG"; then
    echo "There is nothing committed to push."
  fi
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
  [ -n "$MSG" ] && note Message "$MSG"
  [ -n "$DESC" ] && note Details "$DESC"
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
  { [ -d "$P" ] && [ -x "$P" ]; } || fail_exit "Folder not found" "$A_FOLDER" 2
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
    if [ -n "$V_IN" ] && [ -d "$P" ] && [ -x "$P" ]; then
      FOLDER=$P
    else
      err "Folder not found. Enter the path again."
    fi
  done
  wipe
fi
field "$L_FOLDER" "$(tilde "$FOLDER")"
cd "$FOLDER" || fail_exit "Cannot open the folder" "$FOLDER" 2

EXIST=""
[ -f .git/config ] && EXIST=$(awk '/^\[remote "origin"\]/{f=1;next} /^\[/{f=0} f && /url *=/{sub(/^[^=]*= */,""); print; exit}' .git/config 2>/dev/null)
EXIST=$(clean_url "$EXIST")
valid_repo "$EXIST" || EXIST=""
REPO=""
if [ -n "$A_REPO" ]; then
  U=$(clean_url "$A_REPO")
  valid_repo "$U" || fail_exit "Invalid repo URL" "Use https://github.com/owner/repo" 2
  REPO=$U
elif [ "$NI" = 1 ]; then
  [ -n "$EXIST" ] || fail_exit "Repo URL missing" "Use --repo https://github.com/owner/repo" 2
  REPO=$EXIST
else
  if [ -n "$EXIST" ]; then
    info "$L_REPO:" "$EXIST"
    confirm "Use this repo?" && REPO=$EXIST
  fi
  while [ -z "$REPO" ]; do
    ask "$L_REPO:"
    U=$(clean_url "$V_IN")
    if valid_repo "$U"; then
      REPO=$U
    else
      err "Not a GitHub repo link (https://github.com/owner/repo)."
    fi
  done
  wipe
fi
field "$L_REPO" "$REPO"

if [ -n "$A_MSG" ]; then MSG=$A_MSG
elif [ "$NI" = 0 ]; then ask "$L_MSG:"; MSG=$V_IN; wipe
fi
[ -z "$MSG" ] && MSG="Update $(date '+%Y-%m-%d %H:%M')"
field "$L_MSG" "$MSG"

if [ -n "$A_DESC" ]; then DESC=$A_DESC
elif [ "$NI" = 0 ]; then ask "$L_DESC:"; DESC=$V_IN; wipe
fi
if [ -n "$DESC" ]; then field "$L_DESC" "$DESC"; else field "$L_DESC" none "$D"; fi

command -v curl >/dev/null 2>&1 || wait_install "Preparing tools..."
command -v curl >/dev/null 2>&1 || fail_exit "curl is not installed" "$(missing curl)" 2

CAND=${AUTOPUSH_TOKEN:-}
[ "$TOKSTDIN" = 1 ] && IFS= read -r CAND
[ -n "$CAND" ] && FROMENV=1
while [ -z "$TOKEN" ]; do
  if [ -n "$CAND" ]; then
    T=$CAND; CAND=""
  else
    [ "$NI" = 1 ] && fail_exit "Access token missing" "Set AUTOPUSH_TOKEN or use --token-stdin" 2
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
    200)
      GH_LOGIN=$(sed -n 's/.*"login": *"\([^"]*\)".*/\1/p' <<<"$API_BODY" | head -n 1)
      GH_ID=$(sed -n 's/.*"id": *\([0-9][0-9]*\).*/\1/p' <<<"$API_BODY" | head -n 1)
      ;;
    401) tok_err "GitHub rejected this token." "Token rejected" ;;
    000|"") tok_err "Cannot reach GitHub. Check your internet." "No connection" ;;
    *) tok_err "GitHub returned HTTP $API_CODE." "GitHub error" ;;
  esac
done
wipe
field "$L_TOKEN" "$(rep '*' $(( ${#TOKEN} > 24 ? 24 : ${#TOKEN} )))"

section 2 "$S_2"

command -v git >/dev/null 2>&1 || wait_install "Installing git (first run only)..."
command -v git >/dev/null 2>&1 || fail_exit "git is not installed" "$(missing git)"
step "Git ready" "v$(git --version | awk '{print $3}')"

git config --global --get-all safe.directory 2>/dev/null | grep -qx '\*' || git config --global --add safe.directory '*'

SLUG=${REPO#https://github.com/}
SLUG=${SLUG%.git}

if [ -d .git ]; then
  BR=$(git symbolic-ref --short -q HEAD)
  BR=${BR:-main}
  step "Repository detected" "branch $BR"
else
  { git init -q -b main 2>/dev/null || { git init -q && git checkout -q -b main; }; } || fail_exit "Cannot initialize the repository" "git init failed in this folder"
  BR=main
  step "Repository initialized" "branch $BR"
fi

git config user.name "$GH_LOGIN"
git config user.email "${GH_ID}+${GH_LOGIN}@users.noreply.github.com"
step "Account verified" "$GH_LOGIN"

api "/repos/$SLUG"
case $API_CODE in
  200) ;;
  404) fail_exit "Repository not found" "Check the URL, and make sure the token has access to this repository." ;;
  401|403) fail_exit "Token cannot access this repository" "Check the token's repository access and expiry." ;;
  000|"") fail_exit "Cannot reach GitHub" "Check your internet connection." ;;
  *) fail_exit "GitHub returned HTTP $API_CODE" "Try again in a moment." ;;
esac
grep -Eq '"push": *false' <<<"$API_BODY" && fail_exit "No write access to $SLUG" "The token can read this repository but not push to it."
step "Repository found" "$SLUG"

: >"$LOG"
git add -A >"$LOG" 2>&1 || fail_exit "Staging failed" "git add returned an error"
NFILES=$(git diff --cached --name-only | wc -l | tr -d ' ')
NOUN=files; [ "$NFILES" = 1 ] && NOUN=file
step "Files staged" "$NFILES $NOUN"

CARGS=(-m "$MSG")
[ -n "$DESC" ] && CARGS+=(-m "$DESC")
if git commit -q "${CARGS[@]}" >"$LOG" 2>&1; then
  HASH=$(git rev-parse --short HEAD)
  step "Commit created" "$HASH"
elif grep -qi 'nothing to commit' "$LOG"; then
  HASH=$(git rev-parse --short HEAD 2>/dev/null) || fail_exit "Nothing to commit" "This folder has no files to push."
  step "No new changes" "pushing commit $HASH"
else
  fail_exit "Commit failed" "git commit returned an error"
fi

git remote remove origin >/dev/null 2>&1
git remote add origin "$REPO"

: >"$LOG"
T0=$(now)
if [ "$FANCY" = 1 ]; then
  printf '\n\n'
  BARON=1
  bar 0
fi
AUTOPUSH_PW=$TOKEN GIT_TERMINAL_PROMPT=0 \
  git -c credential.helper= \
      -c 'credential.helper=!f() { test "$1" = get && printf "username=x-access-token\npassword=%s\n" "$AUTOPUSH_PW"; }; f' \
      push --progress -u origin "$BR" 2>&1 | feed
PS=${PIPESTATUS[0]}
T1=$(now)
if [ "$PS" -eq 0 ]; then
  if [ "$FANCY" = 1 ]; then
    bar 100
    sleep 0.3
    printf '\r\033[2A\033[J'
    BARON=0
  fi
  step "Pushed to GitHub" "$BR"
else
  WHY=$(hint)
  fail_exit "Push failed" "${WHY:-Unknown error. See the log below.}"
fi

SECS=$(elapsed "$T0" "$T1")

section 3 "$S_3"
res Repo "$SLUG"
res Branch "$BR"
res Commit "$HASH"
res Files "$NFILES"
res Message "$MSG"
[ -n "$DESC" ] && res Details "$DESC"
res Time "${SECS}s"
printf '\n'
banner "$G" "$T_OK"
printf '\n'
)
