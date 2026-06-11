#!/usr/bin/env bash
# deploy.sh — Clean Pro full-stack deployment
#
# Usage:
#   ./deploy.sh [OPTIONS]
#
# Options:
#   --env       dev | prod        Deploy environment (default: dev)
#   --target    backend|mobile|all  Deploy target (default: backend)
#   --dry-run                     Print commands without executing
#   --help                        Show this message
#
# Required env vars for --target mobile or all:
#   RC_APPLE_API_KEY       RevenueCat Apple API key
#   RC_GOOGLE_API_KEY      RevenueCat Google API key
#   SENTRY_DSN             Sentry DSN
#
# Auto-populated from CDK outputs when --target all:
#   API_BASE_URL           Clean Pro API base URL
#   COGNITO_USER_POOL_ID   Cognito user pool ID
#   COGNITO_CLIENT_ID      Cognito mobile client ID
#
# Set these explicitly when running --target mobile standalone:
#   API_BASE_URL           (defaults to https://api.cleanpro.app/v1 if unset)
#   COGNITO_USER_POOL_ID
#   COGNITO_CLIENT_ID
set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Lambda artifact path — must match Code.FromAsset("../backend/publish") in
# CleanProStack.cs, resolved relative to the CDK app root (infrastructure/cdk/).
BACKEND_PUBLISH_DIR="$REPO_ROOT/infrastructure/backend/publish"
CDK_DIR="$REPO_ROOT/infrastructure/cdk"
MOBILE_DIR="$REPO_ROOT/mobile"
STACK_NAME="CleanProStack"
AWS_REGION="ap-southeast-1"
SYMBOLS_DIR="build/symbols"

# ── Color output ──────────────────────────────────────────────────────────────
if [[ -t 1 ]] && [[ "${NO_COLOR:-}" == "" ]]; then
  BOLD="\033[1m"; RESET="\033[0m"
  RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"
else
  BOLD=""; RESET=""; RED=""; GREEN=""; YELLOW=""; CYAN=""
fi

log_info()  { echo -e "${CYAN}[INFO]${RESET}  $*"; }
log_step()  { echo -e "${BOLD}[STEP]${RESET}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${RESET}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_dry()   { echo -e "${YELLOW}[DRY]${RESET}   $*"; }
die()       { log_error "$*"; exit 1; }

# ── Defaults ──────────────────────────────────────────────────────────────────
ENV="dev"
TARGET="backend"
DRY_RUN=false

# ── Argument parsing ──────────────────────────────────────────────────────────
usage() {
  cat <<EOF

Usage: $(basename "$0") [OPTIONS]

Options:
  --env <dev|prod>                  Deploy environment (default: dev)
  --target <backend|mobile|all>     Deploy target     (default: backend)
  --dry-run                         Print commands without executing
  --help                            Show this message

Targets:
  backend   Publish .NET Lambda artifact, then CDK deploy (DynamoDB, Cognito,
            Lambda, API Gateway). Prints stack outputs after deploy.
  mobile    Flutter build appbundle (Android) + build ios (macOS only).
            Requires RC_APPLE_API_KEY, RC_GOOGLE_API_KEY, SENTRY_DSN.
  all       backend then mobile. CDK outputs (API URL, Cognito IDs) are
            automatically injected into the mobile build.

Examples:
  ./deploy.sh                                  # deploy backend to dev
  ./deploy.sh --env prod --target backend      # deploy backend to prod
  ./deploy.sh --env dev  --target all          # deploy backend, then build mobile
  ./deploy.sh --env dev  --target mobile       # build mobile only (set env vars first)
  ./deploy.sh --env prod --dry-run             # preview prod backend deploy
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)      ENV="$2"; shift 2 ;;
    --target)   TARGET="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=true; shift ;;
    --help|-h)  usage; exit 0 ;;
    *)          die "Unknown option: $1. Run with --help for usage." ;;
  esac
done

[[ "$ENV" =~ ^(dev|prod)$ ]] \
  || die "--env must be 'dev' or 'prod', got: '$ENV'"
[[ "$TARGET" =~ ^(backend|mobile|all)$ ]] \
  || die "--target must be 'backend', 'mobile', or 'all', got: '$TARGET'"

# ── Dry-run executor ──────────────────────────────────────────────────────────
# run  CMD [ARGS...] — execute directly (or print in dry-run mode)
# rund DIR CMD [ARGS...] — cd into DIR then execute
run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry "$*"
  else
    "$@"
  fi
}

rund() {
  local dir="$1"; shift
  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry "(cd $dir) $*"
  else
    (cd "$dir" && "$@")
  fi
}

# ── Prerequisite checks ───────────────────────────────────────────────────────
check_prereqs() {
  log_step "Checking prerequisites..."
  local missing=0

  require() {
    if ! command -v "$1" &>/dev/null; then
      log_error "Missing: $1${2:+ ($2)}"
      missing=1
    fi
  }

  require aws "AWS CLI v2"

  if [[ "$TARGET" == "backend" || "$TARGET" == "all" ]]; then
    require dotnet ".NET 8 SDK"
    require cdk   "AWS CDK CLI (npm i -g aws-cdk)"
  fi

  if [[ "$TARGET" == "mobile" || "$TARGET" == "all" ]]; then
    require flutter "Flutter SDK"
  fi

  [[ $missing -eq 0 ]] || die "Install missing tools and retry."
  log_ok "All prerequisites found."
}

# ── Stack output helper ───────────────────────────────────────────────────────
get_stack_output() {
  local key="$1"
  aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region     "$AWS_REGION" \
    --query      "Stacks[0].Outputs[?OutputKey=='$key'].OutputValue" \
    --output     text 2>/dev/null || echo ""
}

# ── Backend deploy ────────────────────────────────────────────────────────────
deploy_backend() {
  echo ""
  log_step "── BACKEND DEPLOY (env=$ENV) ──────────────────────────────────────"

  # Step 1: publish Lambda artifact
  log_step "Publishing .NET Lambda artifact..."
  run dotnet publish \
    "$REPO_ROOT/backend/src/CleanPro.Api/CleanPro.Api.csproj" \
    --configuration Release \
    --runtime       linux-x64 \
    --no-self-contained \
    --output        "$BACKEND_PUBLISH_DIR"
  log_ok "Lambda artifact published to: $BACKEND_PUBLISH_DIR"

  # Step 2: CDK bootstrap (idempotent — creates S3 asset bucket once)
  log_step "Running CDK bootstrap (idempotent)..."
  rund "$CDK_DIR" cdk bootstrap \
    --context "env=$ENV" \
    --require-approval never
  log_ok "CDK bootstrap complete."

  # Step 3: CDK deploy
  log_step "Deploying CDK stack $STACK_NAME (env=$ENV)..."

  if [[ "$ENV" == "prod" ]] && [[ "$DRY_RUN" == "false" ]]; then
    log_warn "Targeting PRODUCTION. CloudFormation will proceed with --require-approval never."
    log_warn "Press Ctrl+C within 5 seconds to abort."
    sleep 5
  fi

  rund "$CDK_DIR" cdk deploy \
    --context "env=$ENV" \
    --require-approval never
  log_ok "CDK deploy complete."

  # Step 4: print + export stack outputs
  if [[ "$DRY_RUN" == "false" ]]; then
    echo ""
    log_step "Stack Outputs:"
    local api_url user_pool_id client_id table_name
    api_url="$(get_stack_output ApiUrl)"
    user_pool_id="$(get_stack_output UserPoolId)"
    client_id="$(get_stack_output UserPoolClientId)"
    table_name="$(get_stack_output DynamoDbTableName)"

    echo -e "  ${BOLD}API URL          :${RESET} $api_url"
    echo -e "  ${BOLD}User Pool ID     :${RESET} $user_pool_id"
    echo -e "  ${BOLD}User Pool Client :${RESET} $client_id"
    echo -e "  ${BOLD}DynamoDB Table   :${RESET} $table_name"
    echo ""

    # Export for mobile build when running --target all
    export API_BASE_URL="${api_url%/}"         # strip trailing slash
    export COGNITO_USER_POOL_ID="$user_pool_id"
    export COGNITO_CLIENT_ID="$client_id"
    log_ok "Exported API_BASE_URL, COGNITO_USER_POOL_ID, COGNITO_CLIENT_ID for mobile build."
  fi
}

# ── Mobile env var check ──────────────────────────────────────────────────────
check_mobile_env_vars() {
  local missing=0

  for var in RC_APPLE_API_KEY RC_GOOGLE_API_KEY SENTRY_DSN; do
    if [[ -z "${!var:-}" ]]; then
      log_error "Required env var not set: $var"
      missing=1
    fi
  done

  # Warn on optional vars (AppConstants has fallback defaults)
  for var in API_BASE_URL COGNITO_USER_POOL_ID COGNITO_CLIENT_ID; do
    if [[ -z "${!var:-}" ]]; then
      log_warn "Optional env var not set: $var (AppConstants default will apply)"
    fi
  done

  [[ $missing -eq 0 ]] || die "Set missing env vars and retry. See ./deploy.sh --help."
}

# ── Mobile build ──────────────────────────────────────────────────────────────
deploy_mobile() {
  echo ""
  log_step "── MOBILE BUILD (env=$ENV) ────────────────────────────────────────"

  check_mobile_env_vars

  # Collect --dart-define flags
  local dart_defines=(
    "--dart-define=RC_APPLE_API_KEY=${RC_APPLE_API_KEY:-}"
    "--dart-define=RC_GOOGLE_API_KEY=${RC_GOOGLE_API_KEY:-}"
    "--dart-define=SENTRY_DSN=${SENTRY_DSN:-}"
    "--dart-define=API_BASE_URL=${API_BASE_URL:-https://api.cleanpro.app/v1}"
    "--dart-define=COGNITO_USER_POOL_ID=${COGNITO_USER_POOL_ID:-}"
    "--dart-define=COGNITO_CLIENT_ID=${COGNITO_CLIENT_ID:-}"
  )

  # Android: App Bundle
  log_step "Building Android App Bundle..."
  rund "$MOBILE_DIR" flutter build appbundle \
    --release \
    "${dart_defines[@]}" \
    "--split-debug-info=$SYMBOLS_DIR/android" \
    "--obfuscate"
  log_ok "Android AAB: mobile/build/app/outputs/bundle/release/app-release.aab"

  # iOS: release archive (macOS only — Xcode required)
  local os_type
  os_type="$(uname -s)"
  if [[ "$os_type" == "Darwin" ]]; then
    log_step "Building iOS release..."
    rund "$MOBILE_DIR" flutter build ios \
      --release \
      --no-codesign \
      "${dart_defines[@]}" \
      "--split-debug-info=$SYMBOLS_DIR/ios" \
      "--obfuscate"
    log_ok "iOS app: mobile/build/ios/iphoneos/Runner.app"
  else
    log_warn "iOS build skipped — macOS + Xcode required (detected OS: $os_type)."
    log_info "Re-run this script on a macOS machine for a full release build."
  fi

  echo ""
  log_step "Mobile Artifacts:"
  echo "  Android AAB : mobile/build/app/outputs/bundle/release/app-release.aab"
  [[ "$os_type" == "Darwin" ]] && \
    echo "  iOS         : mobile/build/ios/iphoneos/Runner.app"
  echo "  Symbols     : mobile/build/symbols/ (upload to Sentry / Play Console)"
  echo ""
  log_info "Next step: upload AAB to Google Play Console or run Fastlane."
}

# ── Main ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}+---------------------------------------+"
echo -e "|     Clean Pro Deployment Script       |"
echo -e "+---------------------------------------+${RESET}"
echo -e "  Environment : ${BOLD}$ENV${RESET}"
echo -e "  Target      : ${BOLD}$TARGET${RESET}"
[[ "$DRY_RUN" == "true" ]] && echo -e "  ${YELLOW}Mode        : DRY RUN (no changes)${RESET}"
echo ""

check_prereqs

case "$TARGET" in
  backend) deploy_backend ;;
  mobile)  deploy_mobile ;;
  all)
    deploy_backend
    deploy_mobile
    ;;
esac

echo ""
log_ok "Deployment complete."
