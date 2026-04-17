#!/bin/bash

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

DEFAULT_TEMPLATE_DIR="$ROOT_DIR/infra/nginx/templates"
DEFAULT_OUTPUT_FILE="$ROOT_DIR/infra/nginx/default.conf.lb.template"

OUTPUT_FILE="$DEFAULT_OUTPUT_FILE"
MODE=""
REPLACE_TARGET=0

declare -a TEMPLATE_INPUTS=()
declare -a TEMPLATE_FILES=()
declare -a VAR_ASSIGNMENTS=()
declare -a ENV_FILE_INPUTS=()

ensure_output_is_file() {
  local target="$1"
  local normalized="${target%/}"

  if [ -z "$normalized" ]; then
    echo -e "${RED}[ERROR]${NC} Output path is invalid: '$target'"
    exit 1
  fi

  if [ -d "$normalized" ]; then
    if [ -n "$(ls -A "$normalized" 2>/dev/null)" ]; then
      echo -e "${RED}[ERROR]${NC} Output path is a non-empty directory: $normalized"
      echo -e "${YELLOW}[HINT]${NC} Remove or rename the directory, then run again."
      exit 1
    fi

    rmdir "$normalized"
    echo -e "${YELLOW}[FIX]${NC} Removed empty directory at output path: $normalized"
  fi

  mkdir -p "$(dirname "$normalized")"
  OUTPUT_FILE="$normalized"
}

usage() {
  cat <<'USAGE'
Usage: $0 -o OUTPUT -t TEMPLATE_PATH [-t TEMPLATE_PATH ...] -v KEY=VALUE [KEY=VALUE ...] (-a | -f) [-r]

Generic nginx template renderer.

Options:
  -o, --output PATH      Output file location and name
  -t, --template PATH    Template file or directory. Can be repeated.
                         Default: infra/nginx/templates
  -E, --env-file PATH    Load variables from env file. Can be repeated.
  -v, --var KEY=VALUE    Variable assignment(s). After -v, keep adding KEY=VALUE
                         until the next flag.
  -a, --append           Append rendered template block(s) to the output file
  -f, --force            Replace the output file with the rendered template block(s)
  -r, --replace-target   When used with -a, replace previously injected block(s)
                         for the same template instead of appending duplicates
  -h, --help             Show this help

Placeholders:
  Supports both ${VAR_NAME} and {{VAR_NAME}}

Examples:
  Create or replace the target file:
  $0 -o infra/nginx/default.conf.lb.template -t infra/nginx/templates/base.conf -v APP_DOMAIN=app.test APP_SERVICE=nextjs APP_PORT=3000 -f

  Append another template later with different variables:
  $0 -o infra/nginx/default.conf.lb.template -t infra/nginx/templates/pma.conf -v PMA_DOMAIN=pma.app.test -a

  Replace a previously injected block for the same template:
  $0 -o infra/nginx/default.conf.lb.template -t infra/nginx/templates/pma.conf -v PMA_DOMAIN=new-pma.app.test -a -r
USAGE
}

load_env() {
  local file="$1"
  if [ -f "$file" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$file"
    set +a
  fi
}

load_custom_env_files() {
  local env_input resolved

  for env_input in "${ENV_FILE_INPUTS[@]}"; do
    resolved="$(resolve_path "$env_input")"

    if [ ! -f "$resolved" ]; then
      echo -e "${RED}[ERROR]${NC} Env file not found: $env_input"
      exit 1
    fi

    load_env "$resolved"
  done
}

resolve_path() {
  local input="$1"

  if [ -z "$input" ]; then
    echo ""
    return
  fi

  if [[ "$input" = /* ]]; then
    printf '%s\n' "$input"
    return
  fi

  if [ -e "$input" ]; then
    printf '%s\n' "$input"
    return
  fi

  printf '%s\n' "$ROOT_DIR/$input"
}

template_id() {
  local path="$1"

  if [[ "$path" == "$ROOT_DIR"/* ]]; then
    printf '%s\n' "${path#$ROOT_DIR/}"
  else
    printf '%s\n' "$path"
  fi
}

collect_template_files() {
  local input resolved

  if [ "${#TEMPLATE_INPUTS[@]}" -eq 0 ]; then
    TEMPLATE_INPUTS+=("$DEFAULT_TEMPLATE_DIR")
  fi

  for input in "${TEMPLATE_INPUTS[@]}"; do
    resolved="$(resolve_path "$input")"

    if [ -d "$resolved" ]; then
      while IFS= read -r file; do
        TEMPLATE_FILES+=("$file")
      done < <(find "$resolved" -maxdepth 1 -type f | sort)
      continue
    fi

    if [ -f "$resolved" ]; then
      TEMPLATE_FILES+=("$resolved")
      continue
    fi

    echo -e "${RED}[ERROR]${NC} Template path not found: $input"
    exit 1
  done

  if [ "${#TEMPLATE_FILES[@]}" -eq 0 ]; then
    echo -e "${RED}[ERROR]${NC} No template files found"
    exit 1
  fi
}

collect_placeholders() {
  local template_file="$1"

  grep -oE '(\$\{[A-Za-z_][A-Za-z0-9_]*\}|\{\{[A-Za-z_][A-Za-z0-9_]*\}\})' "$template_file" 2>/dev/null \
    | sed -E 's/^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$/\1/; s/^\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}$/\1/' \
    | sort -u || true
}

parse_assignments() {
  local assignment key value

  declare -gA CLI_VARS=()

  for assignment in "${VAR_ASSIGNMENTS[@]}"; do
    if [[ "$assignment" != *=* ]]; then
      echo -e "${RED}[ERROR]${NC} Invalid variable assignment: $assignment"
      echo -e "${YELLOW}[HINT]${NC} Use KEY=VALUE without spaces around '='."
      exit 1
    fi

    key="${assignment%%=*}"
    value="${assignment#*=}"

    if ! [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      echo -e "${RED}[ERROR]${NC} Invalid variable name: $key"
      exit 1
    fi

    CLI_VARS["$key"]="$value"
  done
}

resolve_value() {
  local key="$1"

  if [ "${CLI_VARS[$key]+_}" = "_" ]; then
    printf '%s\n' "${CLI_VARS[$key]}"
    return
  fi

  if [ "${!key+x}" = "x" ]; then
    printf '%s\n' "${!key}"
    return
  fi

  return 1
}

render_template() {
  local template_file="$1"
  local content shell_pattern double_brace_pattern key value
  local -a placeholders=()
  local -a missing=()

  content="$(<"$template_file")"

  mapfile -t placeholders < <(collect_placeholders "$template_file")

  for key in "${placeholders[@]}"; do
    if ! value="$(resolve_value "$key")"; then
      missing+=("$key")
      continue
    fi

    shell_pattern="\${${key}}"
    double_brace_pattern="{{${key}}}"

    content="${content//${shell_pattern}/${value}}"
    content="${content//${double_brace_pattern}/${value}}"
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo -e "${RED}[ERROR]${NC} Missing variables for $(template_id "$template_file"): ${missing[*]}"
    exit 1
  fi

  printf '%s\n' "$content"
}

build_block() {
  local template_file="$1"
  local rendered="$2"
  local id

  id="$(template_id "$template_file")"

  printf '# >>> GENERATED TEMPLATE: %s\n%s\n# <<< GENERATED TEMPLATE: %s\n' "$id" "$rendered" "$id"
}

replace_block_in_file() {
  local file="$1"
  local id="$2"
  local replacement="$3"
  local temp_file
  local start_marker="# >>> GENERATED TEMPLATE: ${id}"
  local end_marker="# <<< GENERATED TEMPLATE: ${id}"

  temp_file="$(mktemp)"

  awk -v start="$start_marker" -v end="$end_marker" -v replacement="$replacement" '
    BEGIN {
      in_block = 0
      replaced = 0
    }
    $0 == start {
      if (replaced == 0) {
        print replacement
        replaced = 1
      }
      in_block = 1
      next
    }
    $0 == end && in_block == 1 {
      in_block = 0
      next
    }
    in_block == 0 {
      print
    }
    END {
      if (replaced == 0) {
        if (NR > 0) {
          print ""
        }
        print replacement
      }
    }
  ' "$file" > "$temp_file"

  mv "$temp_file" "$file"
}

write_blocks() {
  local temp_output
  local first_block=1
  local index id

  ensure_output_is_file "$OUTPUT_FILE"

  if [ "$MODE" = "replace-file" ]; then
    temp_output="$(mktemp)"
    : > "$temp_output"

    for index in "${!RENDERED_BLOCKS[@]}"; do
      if [ "$first_block" -eq 0 ]; then
        printf '\n' >> "$temp_output"
      fi
      printf '%s' "${RENDERED_BLOCKS[$index]}" >> "$temp_output"
      first_block=0
    done

    mv "$temp_output" "$OUTPUT_FILE"
    echo -e "${GREEN}[OK]${NC} Replaced $OUTPUT_FILE"
    return
  fi

  touch "$OUTPUT_FILE"

  for index in "${!RENDERED_BLOCKS[@]}"; do
    id="${RENDERED_IDS[$index]}"

    if [ "$REPLACE_TARGET" -eq 1 ]; then
      replace_block_in_file "$OUTPUT_FILE" "$id" "${RENDERED_BLOCKS[$index]}"
      echo -e "${GREEN}[OK]${NC} Upserted template block ${id} into $OUTPUT_FILE"
      continue
    fi

    if [ -s "$OUTPUT_FILE" ]; then
      printf '\n' >> "$OUTPUT_FILE"
    fi

    printf '%s' "${RENDERED_BLOCKS[$index]}" >> "$OUTPUT_FILE"
    echo -e "${GREEN}[OK]${NC} Appended template block ${id} into $OUTPUT_FILE"
  done
}

load_env "$ROOT_DIR/.env"
load_env "$ROOT_DIR/.env.backend"
load_env "$ROOT_DIR/.env.devops"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -o|--output)
      [ "$#" -lt 2 ] && { echo -e "${RED}[ERROR]${NC} Missing value for $1"; exit 1; }
      OUTPUT_FILE="$2"
      shift 2
      ;;
    -t|--template)
      [ "$#" -lt 2 ] && { echo -e "${RED}[ERROR]${NC} Missing value for $1"; exit 1; }
      TEMPLATE_INPUTS+=("$2")
      shift 2
      ;;
    -E|--env-file)
      [ "$#" -lt 2 ] && { echo -e "${RED}[ERROR]${NC} Missing value for $1"; exit 1; }
      ENV_FILE_INPUTS+=("$2")
      shift 2
      ;;
    -v|--var|--vars)
      shift
      while [ "$#" -gt 0 ]; do
        case "$1" in
          -o|--output|-t|--template|-E|--env-file|-v|--var|--vars|-a|--append|-f|--force|-r|--replace-target|-h|--help)
            break
            ;;
          *)
            VAR_ASSIGNMENTS+=("$1")
            shift
            ;;
        esac
      done
      ;;
    -a|--append)
      if [ -n "$MODE" ] && [ "$MODE" != "append" ]; then
        echo -e "${RED}[ERROR]${NC} Use either -a or -f, not both"
        exit 1
      fi
      MODE="append"
      shift
      ;;
    -f|--force)
      if [ -n "$MODE" ] && [ "$MODE" != "replace-file" ]; then
        echo -e "${RED}[ERROR]${NC} Use either -a or -f, not both"
        exit 1
      fi
      MODE="replace-file"
      shift
      ;;
    -r|--replace-target)
      REPLACE_TARGET=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo -e "${RED}[ERROR]${NC} Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [ -z "$MODE" ]; then
  echo -e "${RED}[ERROR]${NC} Choose exactly one write mode: -a or -f"
  usage
  exit 1
fi

if [ "$MODE" = "replace-file" ] && [ "$REPLACE_TARGET" -eq 1 ]; then
  echo -e "${YELLOW}[WARN]${NC} Ignoring -r because -f already replaces the whole output file"
  REPLACE_TARGET=0
fi

parse_assignments
load_custom_env_files
collect_template_files

declare -a RENDERED_BLOCKS=()
declare -a RENDERED_IDS=()

for template_file in "${TEMPLATE_FILES[@]}"; do
  rendered_content="$(render_template "$template_file")"
  RENDERED_IDS+=("$(template_id "$template_file")")
  RENDERED_BLOCKS+=("$(build_block "$template_file" "$rendered_content")")
done

write_blocks
