#!/usr/bin/env bash
# publish.sh — One-command wrapper for fastlane publishing
#
# Usage: ./publish.sh <platform> <action> [--dry-run]
#
# Platforms: ios, android
# Actions:
#   beta       Build and upload to TestFlight / internal track
#   metadata   Push store listing metadata only
#   submit     Submit for review / push to production
#   release    Full pipeline (metadata + beta + submit)
#   promote    (Android only) Promote internal to production
#   screenshots (iOS only) Upload screenshots
#   review     (iOS only) Create review detail record for new version

set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────

info()    { printf '\033[1;34m→ %s\033[0m\n' "$*"; }
success() { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
error()   { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; }

# ─── Usage ───────────────────────────────────────────────────────────────────

usage() {
  cat <<'USAGE'
Usage: ./publish.sh <platform> <action> [--dry-run]

Platforms:
  ios          Apple App Store (via fastlane deliver/pilot)
  android      Google Play Store (via fastlane supply)

Actions:
  beta         Build + upload to TestFlight (iOS) or internal track (Android)
  metadata     Push store listing text only (no binary, no screenshots)
  submit       Submit for App Store review (iOS) or push to production (Android)
  release      Full pipeline: metadata + beta + submit
  promote      (Android) Promote internal track to production
  screenshots  (iOS) Upload screenshots from ./fastlane/screenshots
  review       (iOS) Create review detail record for a new app version

Examples:
  ./publish.sh ios beta
  ./publish.sh ios metadata
  ./publish.sh android metadata
  ./publish.sh android promote
  ./publish.sh android release

USAGE
  exit 1
}

# ─── Args ────────────────────────────────────────────────────────────────────

[[ $# -lt 2 ]] && usage

PLATFORM="$1"
ACTION="$2"
DRY_RUN=false
[[ "${3:-}" == "--dry-run" ]] && DRY_RUN=true

# Validate platform
case "$PLATFORM" in
  ios|android) ;;
  *) error "Unknown platform: $PLATFORM (use 'ios' or 'android')"; exit 1 ;;
esac

# Validate action
case "$ACTION" in
  beta|metadata|submit|release) ;;
  promote)
    [[ "$PLATFORM" != "android" ]] && { error "'promote' is Android-only"; exit 1; }
    ;;
  screenshots|review)
    [[ "$PLATFORM" != "ios" ]] && { error "'$ACTION' is iOS-only"; exit 1; }
    ;;
  *) error "Unknown action: $ACTION"; usage ;;
esac

# ─── iOS: route metadata/screenshots/submit/release through publish.py ──────
# Bypass Ruby/fastlane entirely for these actions

PUBLISH_PY="$HOME/Documents/random-projects/dev-projects/apps/auto-listing-apps/publish.py"

if [[ "$PLATFORM" == "ios" && "$ACTION" =~ ^(metadata|screenshots|submit|release)$ ]]; then
  if [[ ! -f "$PUBLISH_PY" ]]; then
    error "publish.py not found at $PUBLISH_PY"
    exit 1
  fi
  if $DRY_RUN; then
    info "[DRY RUN] Would run: python3 $PUBLISH_PY ios $ACTION $(pwd)"
    exit 0
  fi
  python3 "$PUBLISH_PY" ios "$ACTION" "$(pwd)"
  exit $?
fi

# ─── Pre-flight Checks (fastlane path — beta + Android) ──────────────────────

# Check fastlane directory exists
if [[ ! -d "fastlane" ]]; then
  error "No fastlane/ directory found. Run setup.sh first."
  exit 1
fi

# Check Gemfile / bundler
if [[ ! -f "Gemfile" ]]; then
  error "No Gemfile found. Run setup.sh first."
  exit 1
fi

if ! command -v bundle &>/dev/null; then
  error "Bundler not found. Install with: gem install bundler"
  exit 1
fi

# Check if gems are installed
if ! bundle check &>/dev/null; then
  info "Installing gems..."
  bundle install --quiet
fi

# ─── Android: Environment Setup ──────────────────────────────────────────────

if [[ "$PLATFORM" == "android" ]]; then
  # Source signing env vars if available
  if [[ -f "keystore/.env" ]]; then
    info "Loading signing config from keystore/.env"
    set -a
    source "keystore/.env"
    set +a
  fi

  # Set JAVA_HOME if not set
  if [[ -z "${JAVA_HOME:-}" ]]; then
    AS_JDK="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
    if [[ -d "$AS_JDK" ]]; then
      export JAVA_HOME="$AS_JDK"
      info "JAVA_HOME set to Android Studio JDK"
    else
      warn "JAVA_HOME not set and Android Studio JDK not found at default path"
    fi
  fi
fi

# ─── Pre-flight: Metadata & Assets Validation ────────────────────────────────

warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$*"; }

WARNINGS=0
ERRORS=0

preflight_warn() { warn "$1"; WARNINGS=$((WARNINGS + 1)); }
preflight_error() { error "$1"; ERRORS=$((ERRORS + 1)); }

check_file_not_todo() {
  local file="$1"
  local label="$2"
  local required="${3:-warn}"  # "error" or "warn"
  if [[ ! -f "$file" ]]; then
    preflight_error "Missing: $label ($file)"
  elif grep -qi "^TODO" "$file" 2>/dev/null; then
    if [[ "$required" == "error" ]]; then
      preflight_error "$label still contains TODO placeholder — must be filled in before first submission"
    else
      preflight_warn "$label still contains TODO placeholder"
    fi
  elif [[ ! -s "$file" ]]; then
    if [[ "$required" == "error" ]]; then
      preflight_error "$label is empty — must be filled in before first submission"
    else
      preflight_warn "$label is empty"
    fi
  fi
}

# Detect first-time submission (no prior App Store version) by checking if
# the metadata description is still a placeholder or if no screenshots exist yet
is_first_submission() {
  local meta="fastlane/metadata/en-US"
  # If description is TODO/empty, assume first submission
  if [[ ! -f "$meta/description.txt" ]] || grep -qi "^TODO" "$meta/description.txt" 2>/dev/null || [[ ! -s "$meta/description.txt" ]]; then
    echo "true"
    return
  fi
  # If no screenshots exist at all, assume first submission
  if [[ ! -d "fastlane/screenshots" ]] || [[ -z "$(find fastlane/screenshots -name '*.png' 2>/dev/null | head -1)" ]]; then
    echo "true"
    return
  fi
  echo "false"
}

if [[ "$ACTION" != "promote" && "$ACTION" != "review" ]]; then
  info "Running pre-flight checks..."

  if [[ "$PLATFORM" == "ios" ]]; then
    META="fastlane/metadata/en-US"

    # Determine if this is a first-time submission — hard block if so
    FIRST_SUB=$(is_first_submission)
    SUBMIT_LEVEL="warn"
    if [[ "$FIRST_SUB" == "true" && ("$ACTION" == "submit" || "$ACTION" == "release") ]]; then
      SUBMIT_LEVEL="error"
      info "First submission detected — all metadata and screenshots are required"
    fi

    check_file_not_todo "$META/name.txt" "App name" "error"
    check_file_not_todo "$META/subtitle.txt" "Subtitle" "$SUBMIT_LEVEL"
    check_file_not_todo "$META/description.txt" "Description" "error"
    check_file_not_todo "$META/keywords.txt" "Keywords" "error"
    check_file_not_todo "$META/release_notes.txt" "Release notes" "error"
    check_file_not_todo "$META/privacy_url.txt" "Privacy URL" "error"
    check_file_not_todo "$META/support_url.txt" "Support URL" "$SUBMIT_LEVEL"

    # Check privacy URL is not a placeholder
    if [[ -f "$META/privacy_url.txt" ]]; then
      URL=$(cat "$META/privacy_url.txt" | tr -d '[:space:]')
      if [[ "$URL" == *"TODO"* || "$URL" == *"example.com"* || -z "$URL" ]]; then
        preflight_error "Privacy URL is a placeholder — must be a real URL before submitting"
      fi
    fi

    # Screenshots: hard block on first submission, warn on updates
    if [[ "$ACTION" == "beta" || "$ACTION" == "submit" || "$ACTION" == "release" ]]; then
      SCREENSHOTS_EXIST=false
      if [[ -d "fastlane/screenshots" ]] && [[ -n "$(find fastlane/screenshots -name '*.png' 2>/dev/null | head -1)" ]]; then
        SCREENSHOTS_EXIST=true
      fi
      if [[ "$SCREENSHOTS_EXIST" == "false" ]]; then
        if [[ "$FIRST_SUB" == "true" && ("$ACTION" == "submit" || "$ACTION" == "release") ]]; then
          preflight_error "No screenshots found — screenshots are required for first App Store submission. Add PNGs to fastlane/screenshots/en-US/ and run ./publish.sh ios screenshots first."
        else
          preflight_warn "No screenshots found in fastlane/screenshots/ — App Store listing will have no images"
        fi
      fi
    fi

    # Check API key exists
    if [[ ! -f "$HOME/.appstoreconnect/AuthKey_G8CBGNXR6R.p8" ]]; then
      preflight_error "API key not found at ~/.appstoreconnect/AuthKey_G8CBGNXR6R.p8"
    fi
  fi

  if [[ "$PLATFORM" == "android" ]]; then
    META="fastlane/metadata/android/en-US"
    check_file_not_todo "$META/title.txt" "App title"
    check_file_not_todo "$META/short_description.txt" "Short description"
    check_file_not_todo "$META/full_description.txt" "Full description"

    # Check short description length (80 char limit)
    if [[ -f "$META/short_description.txt" ]]; then
      LEN=$(wc -c < "$META/short_description.txt" | tr -d ' ')
      if [[ $LEN -gt 80 ]]; then
        preflight_warn "Short description is $LEN chars (limit: 80)"
      fi
    fi

    # Check full description length (4000 char limit)
    if [[ -f "$META/full_description.txt" ]]; then
      LEN=$(wc -c < "$META/full_description.txt" | tr -d ' ')
      if [[ $LEN -gt 4000 ]]; then
        preflight_error "Full description is $LEN chars (limit: 4000)"
      fi
    fi

    # Check JSON key exists
    if [[ -f "fastlane/Appfile" ]]; then
      KEY_PATH=$(grep 'json_key_file' fastlane/Appfile | sed 's/.*"\(.*\)".*/\1/' | sed "s|~|$HOME|")
      if [[ ! -f "$KEY_PATH" ]]; then
        preflight_error "Google Play JSON key not found at $KEY_PATH"
      fi
    fi

    # Check signing env vars for build actions
    if [[ "$ACTION" == "beta" || "$ACTION" == "submit" || "$ACTION" == "release" ]]; then
      if [[ -z "${KEYSTORE_PATH:-}" && ! -f "keystore/.env" ]]; then
        preflight_warn "No signing config: set KEYSTORE_PATH or create keystore/.env"
      fi
    fi
  fi

  # Report
  if [[ $ERRORS -gt 0 ]]; then
    echo ""
    error "$ERRORS error(s) found. Fix them before publishing."
    exit 1
  fi

  if [[ $WARNINGS -gt 0 ]]; then
    echo ""
    warn "$WARNINGS warning(s) found. Proceeding anyway..."
    echo ""
  else
    success "Pre-flight checks passed"
  fi
fi

# ─── Run (fastlane — beta + Android) ─────────────────────────────────────────

# Map action to fastlane lane
LANE="$ACTION"
case "$ACTION" in
  screenshots) LANE="upload_screenshots" ;;
  review)      LANE="create_review_detail" ;;
  release)     LANE="release" ;;
esac

if $DRY_RUN; then
  info "[DRY RUN] Would run: LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 bundle exec fastlane $LANE"
  exit 0
fi

# ─── Screenshots: apply overlay then upload ───────────────────────────────────
if [[ "$ACTION" == "screenshots" && "$PLATFORM" == "ios" ]]; then
  # Locate the auto-listing-apps toolkit (same dir as this publish.sh was copied from,
  # or fall back to the well-known path).
  TOOLKIT_DIR=""
  # If TOOLKIT_DIR is stamped in at setup time we use it; otherwise fall back.
  if [[ -z "$TOOLKIT_DIR" || ! -f "$TOOLKIT_DIR/screenshot-overlay.py" ]]; then
    TOOLKIT_DIR="$HOME/Documents/random-projects/dev-projects/apps/auto-listing-apps"
  fi
  OVERLAY_SCRIPT="$TOOLKIT_DIR/screenshot-overlay.py"

  # ── Pre-flight: spec file ──
  if [[ ! -f "APP_STORE_SCREENSHOT_SPEC.md" ]]; then
    error "APP_STORE_SCREENSHOT_SPEC.md not found in $(pwd)"
    echo ""
    echo "  Create one from the template:"
    echo "    cp $TOOLKIT_DIR/templates/APP_STORE_SCREENSHOT_SPEC.md ./APP_STORE_SCREENSHOT_SPEC.md"
    echo "  Then fill in your headlines and copy."
    exit 1
  fi

  # ── Pre-flight: raw screenshots ──
  # Check screenshots/raw/ first (preferred), fall back to fastlane/screenshots/en-US/
  if [[ -d "screenshots/raw" ]] && [[ -n "$(find screenshots/raw -maxdepth 1 -name '*.png' 2>/dev/null | head -1)" ]]; then
    RAW_DIR="screenshots/raw"
  else
    RAW_DIR="fastlane/screenshots/en-US"
  fi
  RAW_COUNT=$(find "$RAW_DIR" -maxdepth 1 -name "*.png" 2>/dev/null | grep -v "framed" | wc -l | tr -d ' ')
  if [[ "$RAW_COUNT" -eq 0 ]]; then
    error "No raw screenshots found"
    echo ""
    echo "  Drop your raw simulator screenshots into:"
    echo "    screenshots/raw/1_hero.png"
    echo "    screenshots/raw/2_features.png"
    echo "    screenshots/raw/3_something.png"
    echo "    ... (up to 10)"
    exit 1
  fi
  info "Found $RAW_COUNT raw screenshot(s) in $RAW_DIR"

  # ── Pre-flight: Python + Pillow ──
  if ! command -v python3 &>/dev/null; then
    error "python3 not found — install Python 3 to use screenshot overlays"
    exit 1
  fi
  if ! python3 -c "import PIL" 2>/dev/null; then
    warn "Pillow not installed. Installing now..."
    pip3 install --quiet Pillow || { error "Failed to install Pillow. Run: pip3 install Pillow"; exit 1; }
  fi

  if [[ ! -f "$OVERLAY_SCRIPT" ]]; then
    error "screenshot-overlay.py not found at $OVERLAY_SCRIPT"
    echo "  Ensure the auto-listing-apps toolkit is at: $TOOLKIT_DIR"
    exit 1
  fi

  # ── Step 1: Apply overlays ──
  info "Step 1/2: Applying marketing overlays to $RAW_COUNT raw screenshot(s)..."
  echo ""

  FRAMED_OUT="screenshots/framed"
  mkdir -p "$FRAMED_OUT"

  if $DRY_RUN; then
    python3 "$OVERLAY_SCRIPT" \
      --spec "APP_STORE_SCREENSHOT_SPEC.md" \
      --input "$RAW_DIR" \
      --output "$FRAMED_OUT" \
      --dry-run
    info "[DRY RUN] Would then run: fastlane upload_screenshots"
    exit 0
  fi

  python3 "$TOOLKIT_DIR/composite-screenshots.py" "$(pwd)" \
    || { error "composite-screenshots.py failed — aborting upload"; exit 1; }

  FRAMED_COUNT=$(find "$FRAMED_OUT" -name "*.png" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$FRAMED_COUNT" -eq 0 ]]; then
    error "No framed screenshots were generated — check errors above"
    exit 1
  fi

  success "Generated $FRAMED_COUNT framed screenshot(s) in $FRAMED_OUT/"
  echo ""

  # ── Step 2: Upload via fastlane ──
  info "Step 2/2: Uploading screenshots to App Store Connect..."
  echo ""

  export LANG=en_US.UTF-8
  export LC_ALL=en_US.UTF-8

  if bundle exec fastlane upload_screenshots; then
    echo ""
    success "Done! Screenshots uploaded to App Store Connect."
  else
    EXIT_CODE=$?
    echo ""
    error "fastlane upload_screenshots failed (exit code $EXIT_CODE)"
    echo ""
    echo "  Framed screenshots are in: $FRAMED_OUT/"
    echo "  You can upload them manually via App Store Connect if needed."
    exit $EXIT_CODE
  fi
  exit 0
fi

info "Running: fastlane $LANE ($PLATFORM)"
echo ""

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

if bundle exec fastlane "$LANE"; then
  echo ""
  success "Done! fastlane $LANE completed successfully."
else
  EXIT_CODE=$?
  echo ""
  error "fastlane $LANE failed (exit code $EXIT_CODE)"
  echo ""
  echo "  Common fixes:"
  echo "    - Run 'bundle install' to update gems"
  echo "    - Check your API key / service account JSON is valid"
  if [[ "$PLATFORM" == "android" ]]; then
    echo "    - Verify KEYSTORE_PATH, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD are set"
    echo "    - See docs/google-play-setup.md for service account setup"
  fi
  if [[ "$PLATFORM" == "ios" ]]; then
    echo "    - Verify ~/.appstoreconnect/AuthKey_G8CBGNXR6R.p8 exists"
    echo "    - For new versions, run: ./publish.sh ios review"
  fi
  exit $EXIT_CODE
fi
