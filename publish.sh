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
#   release    Full pipeline (beta + submit)
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
  release      Full pipeline: beta + submit
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

# ─── Pre-flight Checks ──────────────────────────────────────────────────────

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
  if [[ ! -f "$file" ]]; then
    preflight_error "Missing: $label ($file)"
  elif grep -qi "^TODO" "$file" 2>/dev/null; then
    preflight_warn "$label still contains TODO placeholder"
  elif [[ ! -s "$file" ]]; then
    preflight_warn "$label is empty"
  fi
}

if [[ "$ACTION" != "promote" && "$ACTION" != "review" ]]; then
  info "Running pre-flight checks..."

  if [[ "$PLATFORM" == "ios" ]]; then
    META="fastlane/metadata/en-US"
    check_file_not_todo "$META/name.txt" "App name"
    check_file_not_todo "$META/subtitle.txt" "Subtitle"
    check_file_not_todo "$META/description.txt" "Description"
    check_file_not_todo "$META/keywords.txt" "Keywords"
    check_file_not_todo "$META/release_notes.txt" "Release notes"
    check_file_not_todo "$META/privacy_url.txt" "Privacy URL"
    check_file_not_todo "$META/support_url.txt" "Support URL"

    # Check privacy URL is not a placeholder
    if [[ -f "$META/privacy_url.txt" ]]; then
      URL=$(cat "$META/privacy_url.txt" | tr -d '[:space:]')
      if [[ "$URL" == *"TODO"* || "$URL" == *"example.com"* || -z "$URL" ]]; then
        preflight_error "Privacy URL is a placeholder — must be a real URL before submitting"
      fi
    fi

    # Check for screenshots (warn only — not required for metadata push)
    if [[ "$ACTION" == "beta" || "$ACTION" == "submit" || "$ACTION" == "release" ]]; then
      if [[ ! -d "fastlane/screenshots" ]] || [[ -z "$(find fastlane/screenshots -name '*.png' 2>/dev/null)" ]]; then
        preflight_warn "No screenshots found in fastlane/screenshots/"
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

# ─── Run ─────────────────────────────────────────────────────────────────────

# Map action to fastlane lane
LANE="$ACTION"
case "$ACTION" in
  screenshots) LANE="upload_screenshots" ;;
  review)      LANE="create_review_detail" ;;
esac

if $DRY_RUN; then
  info "[DRY RUN] Would run: LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 bundle exec fastlane $LANE"
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
