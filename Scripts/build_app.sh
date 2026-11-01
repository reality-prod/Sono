#!/bin/bash
# Compiles Sono in release mode and wraps it into build/Sono.app with Apple Help Book.
set -eo pipefail
cd "$(dirname "$0")/.."

# ─────────────────────────────────────────────────────────────
#  Styling (auto-disabled when not a TTY or NO_COLOR is set)
# ─────────────────────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    RST=$'\033[0m';  BOLD=$'\033[1m';  DIM=$'\033[2m'
    RED=$'\033[38;5;203m';   GREEN=$'\033[38;5;114m'; YELLOW=$'\033[38;5;221m'
    BLUE=$'\033[38;5;75m';   PURPLE=$'\033[38;5;141m'; CYAN=$'\033[38;5;80m'
    GRAY=$'\033[38;5;245m';  ORANGE=$'\033[38;5;209m'
else
    RST=; BOLD=; DIM=; RED=; GREEN=; YELLOW=; BLUE=; PURPLE=; CYAN=; GRAY=; ORANGE=
fi

TOTAL_STEPS=6
STEP=0
START=$SECONDS
STEP_START=$SECONDS

rule()    { printf "${GRAY}%s${RST}\n" "────────────────────────────────────────────────────────────"; }
step()    { STEP=$((STEP+1)); STEP_START=$SECONDS
            printf "\n${BOLD}${PURPLE}[%d/%d]${RST} ${BOLD}%s${RST}\n" "$STEP" "$TOTAL_STEPS" "$1"; }
info()    { printf "  ${BLUE}›${RST} %s\n" "$1"; }
detail()  { printf "  ${GRAY}  %s${RST}\n" "$1"; }
ok()      { printf "  ${GREEN}✔${RST} %s ${GRAY}(%ds)${RST}\n" "$1" "$((SECONDS-STEP_START))"; }
skip()    { printf "  ${YELLOW}↷${RST} ${YELLOW}%s${RST}\n" "$1"; }
warn()    { printf "  ${YELLOW}⚠${RST} %s\n" "$1"; }
indent()  { sed "s/^/  ${GRAY}│${RST} ${DIM}/; s/\$/${RST}/"; }
human()   { du -sh "$1" 2>/dev/null | awk '{print $1}'; }

trap 'printf "\n${RED}${BOLD}✘ Build failed${RST} ${GRAY}(line %s, after %ds)${RST}\n" "$LINENO" "$((SECONDS-START))"' ERR

# ─────────────────────────────────────────────────────────────
#  Banner
# ─────────────────────────────────────────────────────────────
APP=build/Sono.app
printf "\n"
rule
printf "  ${BOLD}${CYAN}♪  Sono${RST} ${BOLD}— release build${RST}\n"
printf "  ${GRAY}%s · %s${RST}\n" "$(date '+%a %b %d, %H:%M')" "$(uname -m)"
rule
info "Project root: ${BOLD}$(pwd)${RST}"
info "Swift:        ${BOLD}$(swift --version 2>&1 | head -n1)${RST}"
info "Output:       ${BOLD}${APP}${RST}"

# ─────────────────────────────────────────────────────────────
#  1. Help index
# ─────────────────────────────────────────────────────────────
step "Building Apple Help Book index"
if [ -x help/build_help.sh ]; then
    help/build_help.sh 2>&1 | indent
    ok "Help index up to date"
else
    skip "help/build_help.sh not found or not executable — skipping"
fi

# ─────────────────────────────────────────────────────────────
#  2. Compile
# ─────────────────────────────────────────────────────────────
step "Compiling with Swift (release)"
info "swift build -c release -vv"
detail "Verbose mode: full compiler/linker invocations will be shown"
swift build -c release -vv 2>&1 | indent
BIN_SIZE=$(human .build/release/Sono)
ok "Compiled binary ${GRAY}(${BIN_SIZE})${RST}"

# ─────────────────────────────────────────────────────────────
#  3. Bundle skeleton
# ─────────────────────────────────────────────────────────────
step "Creating app bundle"
if [ -d "$APP" ]; then
    info "Removing previous bundle"
    rm -rf "$APP"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
detail "$APP/Contents/MacOS"
detail "$APP/Contents/Resources"
ok "Bundle skeleton created"

# ─────────────────────────────────────────────────────────────
#  4. Copy payload
# ─────────────────────────────────────────────────────────────
step "Copying executable and resources"
cp .build/release/Sono "$APP/Contents/MacOS/Sono"
info "Executable  ${GREEN}copied${RST}"

if [ -f Design/Sono.icns ]; then
    cp Design/Sono.icns "$APP/Contents/Resources/"
    info "App icon    ${GREEN}copied${RST}"
else
    warn "Design/Sono.icns not found — app will use the default icon"
fi

if [ -d help/Sono.help ]; then
    cp -R help/Sono.help "$APP/Contents/Resources/"
    info "Help Book   ${GREEN}copied${RST}"
else
    warn "help/Sono.help not found — Help menu will be empty"
fi
ok "Resources in place"

# ─────────────────────────────────────────────────────────────
#  5. Info.plist
# ─────────────────────────────────────────────────────────────
step "Writing Info.plist"
cat > "$APP/Contents/Info.plist" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Sono</string>
    <key>CFBundleDisplayName</key><string>Sono</string>
    <key>CFBundleExecutable</key><string>Sono</string>
    <key>CFBundleIdentifier</key><string>app.sono.mac</string>
    <key>CFBundleIconFile</key><string>Sono</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>CFBundleHelpBookFolder</key><string>Sono.help</string>
    <key>CFBundleHelpBookName</key><string>app.sono.mac.help</string>
    <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
P
detail "Identifier : app.sono.mac"
detail "Version    : 1.0 (build 1)"
detail "Min macOS  : 14.0"
detail "Help Book  : app.sono.mac.help"
if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$APP/Contents/Info.plist" 2>&1 | sed "s/^/  ${GRAY}  /; s/\$/${RST}/"
fi
ok "Info.plist written"

# ─────────────────────────────────────────────────────────────
#  6. Verify
# ─────────────────────────────────────────────────────────────
step "Verifying bundle"
check() { if [ -e "$APP/$1" ]; then printf "  ${GREEN}✔${RST} %s\n" "$1"
          else printf "  ${RED}✘${RST} %s ${RED}(missing)${RST}\n" "$1"; fi; }
check "Contents/MacOS/Sono"
check "Contents/Info.plist"
check "Contents/Resources/Sono.icns"
check "Contents/Resources/Sono.help"
ok "Verification complete"

# ─────────────────────────────────────────────────────────────
#  Summary
# ─────────────────────────────────────────────────────────────
printf "\n"
rule
printf "  ${GREEN}${BOLD}✔ Build succeeded${RST}  ${GRAY}in %ds${RST}\n" "$((SECONDS-START))"
rule
printf "  ${BOLD}Bundle${RST}  ${CYAN}%s${RST}  ${GRAY}(%s)${RST}\n" "$APP" "$(human "$APP")"
printf "  ${BOLD}Binary${RST}  %s\n" "$BIN_SIZE"
printf "  ${BOLD}Help${RST}    Apple Help Book included\n"
printf "\n  ${GRAY}Run it:${RST}  ${BOLD}open %s${RST}\n\n" "$APP"