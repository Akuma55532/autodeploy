#!/bin/bash

# autodeploy usage
# --list
#   List all modules and profiles.
# --profile <name>
#   Show the resolved execution plan for one profile.
# --modules <a,b,c>
#   Show the resolved execution plan for selected modules.
# --list --profile <name>
#   List all modules and profiles, then show one profile plan.
# --list --modules <a,b,c>
#   List all modules and profiles, then show one custom module plan.
# --validate
#   Validate all profiles, module references, dependencies, and required functions.
# --validate --profile <name>
#   Validate one profile only.
# --validate --modules <a,b,c>
#   Validate one custom module set only.
# --profile <name> --run
#   Run one profile in dependency order and record completed modules.
# --modules <a,b,c> --run
#   Run selected modules in dependency order and record completed modules.
# --profile <name> --run --force
#   Run one profile and ignore recorded state/check short-circuiting.
# --modules <a,b,c> --run --force
#   Run selected modules and ignore recorded state/check short-circuiting.

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MODULE_DIR="$ROOT_DIR/modules"
PROFILE_DIR="$ROOT_DIR/profiles"
STATE_DIR="$ROOT_DIR/state"
STATE_FILE="$STATE_DIR/installed.state"

declare -A MODULE_DEPS_MAP
declare -A MODULE_DESC_MAP
declare -A MODULE_FILE_MAP
declare -A MODULE_SEEN
declare -A MODULE_VISITING
declare -A MODULE_DONE_MAP

PROFILE_NAME=""
MODULES_ARG=""
SHOW_LIST=0
VALIDATE_ONLY=0
RUN_PROFILE=0
FORCE_RUN=0

usage() {
    cat <<EOF
Usage:
  $(basename "$0") --list
  $(basename "$0") --profile <name>
  $(basename "$0") --modules <a,b,c>
  $(basename "$0") --list --profile <name>
  $(basename "$0") --list --modules <a,b,c>
  $(basename "$0") --validate
  $(basename "$0") --validate --profile <name>
  $(basename "$0") --validate --modules <a,b,c>
  $(basename "$0") --profile <name> --run
  $(basename "$0") --modules <a,b,c> --run
  $(basename "$0") --profile <name> --run --force
  $(basename "$0") --modules <a,b,c> --run --force
EOF
}

append_if_missing() {
    local text=$1
    local file=$2
    grep -qxF "$text" "$file" 2>/dev/null || echo "$text" >> "$file"
}

require_path() {
    local target=$1
    if [ ! -e "$target" ]; then
        echo "Missing required path: $target"
        exit 1
    fi
}

ensure_dir_from_zip() {
    local dir_path=$1
    local zip_path=$2
    local parent_dir=$3

    if [ -d "$dir_path" ]; then
        return 0
    fi

    if [ -f "$zip_path" ]; then
        unzip -q "$zip_path" -d "$parent_dir"
        return $?
    fi

    return 1
}

ensure_dir_from_tbz2() {
    local dir_path=$1
    local archive_path=$2
    local parent_dir=$3

    if [ -d "$dir_path" ]; then
        return 0
    fi

    if [ -f "$archive_path" ]; then
        tar -xjf "$archive_path" -C "$parent_dir"
        return $?
    fi

    return 1
}

load_module_file() {
    local module_file=$1
    local meta
    local name
    local deps
    local desc

    meta=$(
        unset MODULE_NAME MODULE_DEPS MODULE_DESC
        source "$module_file"
        printf '%s|%s|%s\n' "${MODULE_NAME:-}" "${MODULE_DEPS:-}" "${MODULE_DESC:-}"
    )

    IFS='|' read -r name deps desc <<< "$meta"

    if [ -z "$name" ]; then
        echo "Invalid module file: $module_file"
        exit 1
    fi

    if [ -n "${MODULE_FILE_MAP[$name]:-}" ]; then
        echo "Duplicate module name: $name"
        echo "  first:  ${MODULE_FILE_MAP[$name]}"
        echo "  second: $module_file"
        exit 1
    fi

    MODULE_DEPS_MAP["$name"]=$deps
    MODULE_DESC_MAP["$name"]=$desc
    MODULE_FILE_MAP["$name"]=$module_file
}

load_modules() {
    local module_file

    for module_file in "$MODULE_DIR"/*.sh; do
        [ -e "$module_file" ] || continue
        load_module_file "$module_file"
    done
}

load_profile_modules() {
    local profile_file=$1
    local modules

    modules=$(
        unset MODULES
        source "$profile_file"
        printf '%s\n' "${MODULES:-}"
    )

    if [ -z "$modules" ]; then
        echo "Profile is empty: $profile_file"
        exit 1
    fi

    printf '%s\n' "$modules"
}

load_cli_modules() {
    local modules=$1

    modules=${modules//,/ }
    modules=$(echo "$modules" | xargs)

    if [ -z "$modules" ]; then
        echo "Modules argument is empty."
        exit 1
    fi

    printf '%s\n' "$modules"
}

list_modules() {
    local module_name

    echo "Modules:"
    for module_name in "${!MODULE_FILE_MAP[@]}"; do
        printf '  %-12s deps: %-12s desc: %s\n' \
            "$module_name" \
            "${MODULE_DEPS_MAP[$module_name]:--}" \
            "${MODULE_DESC_MAP[$module_name]}"
    done | sort
}

list_profiles() {
    local profile_file
    local profile_name
    local profile_modules

    echo "Profiles:"
    for profile_file in "$PROFILE_DIR"/*.conf; do
        [ -e "$profile_file" ] || continue
        profile_name=$(basename "$profile_file" .conf)
        profile_modules=$(load_profile_modules "$profile_file")
        printf '  %-12s modules: %s\n' "$profile_name" "$profile_modules"
    done | sort
}

append_plan_module() {
    local module_name=$1
    local deps=${MODULE_DEPS_MAP[$module_name]:-}
    local dep

    if [ "${MODULE_VISITING[$module_name]:-0}" = "1" ]; then
        echo "Circular dependency detected at module: $module_name"
        exit 1
    fi

    if [ "${MODULE_SEEN[$module_name]:-0}" = "1" ]; then
        return
    fi

    MODULE_VISITING["$module_name"]=1

    for dep in $deps; do
        if [ -z "${MODULE_FILE_MAP[$dep]:-}" ]; then
            echo "Missing module dependency: $module_name -> $dep"
            exit 1
        fi
        append_plan_module "$dep"
    done

    MODULE_VISITING["$module_name"]=0
    MODULE_SEEN["$module_name"]=1
    PLAN_MODULES+=("$module_name")
}

reset_resolution_state() {
    MODULE_SEEN=()
    MODULE_VISITING=()
    PLAN_MODULES=()
}

resolve_module_plan() {
    local requested_modules=$1
    local module_name
    reset_resolution_state

    for module_name in $requested_modules; do
        if [ -z "${MODULE_FILE_MAP[$module_name]:-}" ]; then
            echo "Missing module: $module_name"
            exit 1
        fi
        append_plan_module "$module_name"
    done
}

resolve_profile_plan() {
    local profile_name=$1
    local profile_file="$PROFILE_DIR/$profile_name.conf"
    local requested_modules

    [ -f "$profile_file" ] || {
        echo "Profile not found: $profile_name"
        exit 1
    }

    requested_modules=$(load_profile_modules "$profile_file")
    resolve_module_plan "$requested_modules"
}

resolve_cli_plan() {
    local requested_modules

    requested_modules=$(load_cli_modules "$MODULES_ARG")
    resolve_module_plan "$requested_modules"
}

show_profile_plan() {
    local index=1
    local module_name

    resolve_profile_plan "$PROFILE_NAME"

    echo "Execution plan for profile: $PROFILE_NAME"
    for module_name in "${PLAN_MODULES[@]}"; do
        printf '  %d. %-12s deps: %-12s desc: %s\n' \
            "$index" \
            "$module_name" \
            "${MODULE_DEPS_MAP[$module_name]:--}" \
            "${MODULE_DESC_MAP[$module_name]}"
        index=$((index + 1))
    done
}

show_modules_plan() {
    local index=1
    local module_name

    resolve_cli_plan

    echo "Execution plan for modules: $(load_cli_modules "$MODULES_ARG")"
    for module_name in "${PLAN_MODULES[@]}"; do
        printf '  %d. %-12s deps: %-12s desc: %s\n' \
            "$index" \
            "$module_name" \
            "${MODULE_DEPS_MAP[$module_name]:--}" \
            "${MODULE_DESC_MAP[$module_name]}"
        index=$((index + 1))
    done
}

validate_profile() {
    local profile_name=$1

    resolve_profile_plan "$profile_name"
    validate_plan_functions
    printf 'Validated profile: %-12s modules: %s\n' "$profile_name" "${PLAN_MODULES[*]}"
}

validate_modules() {
    resolve_cli_plan
    validate_plan_functions
    printf 'Validated modules: %s\n' "${PLAN_MODULES[*]}"
}

validate_all() {
    local profile_file
    local profile_name
    local profile_count=0

    [ -d "$MODULE_DIR" ] || {
        echo "Module directory not found: $MODULE_DIR"
        exit 1
    }

    [ -d "$PROFILE_DIR" ] || {
        echo "Profile directory not found: $PROFILE_DIR"
        exit 1
    }

    for profile_file in "$PROFILE_DIR"/*.conf; do
        [ -e "$profile_file" ] || continue
        profile_name=$(basename "$profile_file" .conf)
        validate_profile "$profile_name"
        profile_count=$((profile_count + 1))
    done

    echo
    echo "Validation passed."
    echo "Profiles checked: $profile_count"
    echo "Modules loaded: ${#MODULE_FILE_MAP[@]}"
}

ensure_state_file() {
    mkdir -p "$STATE_DIR"
    [ -f "$STATE_FILE" ] || : > "$STATE_FILE"
}

load_state() {
    local line
    local key
    local value

    ensure_state_file
    MODULE_DONE_MAP=()

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        key=${line%%=*}
        value=${line#*=}
        MODULE_DONE_MAP["$key"]=$value
    done < "$STATE_FILE"
}

is_module_done() {
    local module_name=$1
    [ "${MODULE_DONE_MAP[$module_name]:-}" = "done" ]
}

mark_module_done() {
    local module_name=$1
    local tmp_file
    local existing

    ensure_state_file
    tmp_file=$(mktemp)

    while IFS= read -r existing; do
        [ -n "$existing" ] || continue
        [ "${existing%%=*}" = "$module_name" ] && continue
        printf '%s\n' "$existing" >> "$tmp_file"
    done < "$STATE_FILE"

    printf '%s=done\n' "$module_name" >> "$tmp_file"
    mv "$tmp_file" "$STATE_FILE"
    MODULE_DONE_MAP["$module_name"]="done"
}

validate_plan_functions() {
    local module_name
    local module_file
    local check_fn
    local install_fn

    for module_name in "${PLAN_MODULES[@]}"; do
        module_file=${MODULE_FILE_MAP[$module_name]}
        check_fn="check_${module_name}"
        install_fn="install_${module_name}"

        unset MODULE_NAME MODULE_DEPS MODULE_DESC
        unset -f "$check_fn" "$install_fn" 2>/dev/null || true
        source "$module_file"

        if ! declare -F "$check_fn" >/dev/null; then
            echo "Missing function in $module_file: $check_fn"
            exit 1
        fi

        if ! declare -F "$install_fn" >/dev/null; then
            echo "Missing function in $module_file: $install_fn"
            exit 1
        fi
    done
}

run_profile_plan() {
    local module_name
    local module_file
    local check_fn
    local install_fn

    resolve_profile_plan "$PROFILE_NAME"
    validate_plan_functions
    load_state

    echo "Running profile: $PROFILE_NAME"

    for module_name in "${PLAN_MODULES[@]}"; do
        module_file=${MODULE_FILE_MAP[$module_name]}
        check_fn="check_${module_name}"
        install_fn="install_${module_name}"

        if [ "$FORCE_RUN" != "1" ] && is_module_done "$module_name"; then
            echo "Skip $module_name: recorded as done."
            continue
        fi

        unset MODULE_NAME MODULE_DEPS MODULE_DESC
        unset -f "$check_fn" "$install_fn" 2>/dev/null || true
        source "$module_file"

        if [ "$FORCE_RUN" != "1" ] && "$check_fn"; then
            echo "Skip $module_name: check passed."
            mark_module_done "$module_name"
            continue
        fi

        echo "Install $module_name ..."
        "$install_fn"
        mark_module_done "$module_name"
        echo "Done $module_name."
    done
}

run_modules_plan() {
    local module_name
    local module_file
    local check_fn
    local install_fn

    resolve_cli_plan
    validate_plan_functions
    load_state

    echo "Running modules: $(load_cli_modules "$MODULES_ARG")"

    for module_name in "${PLAN_MODULES[@]}"; do
        module_file=${MODULE_FILE_MAP[$module_name]}
        check_fn="check_${module_name}"
        install_fn="install_${module_name}"

        if [ "$FORCE_RUN" != "1" ] && is_module_done "$module_name"; then
            echo "Skip $module_name: recorded as done."
            continue
        fi

        unset MODULE_NAME MODULE_DEPS MODULE_DESC
        unset -f "$check_fn" "$install_fn" 2>/dev/null || true
        source "$module_file"

        if [ "$FORCE_RUN" != "1" ] && "$check_fn"; then
            echo "Skip $module_name: check passed."
            mark_module_done "$module_name"
            continue
        fi

        echo "Install $module_name ..."
        "$install_fn"
        mark_module_done "$module_name"
        echo "Done $module_name."
    done
}

while [ $# -gt 0 ]; do
    case "$1" in
        --list)
            SHOW_LIST=1
            shift
            ;;
        --profile)
            [ $# -ge 2 ] || {
                echo "--profile requires a name"
                usage
                exit 1
            }
            PROFILE_NAME=$2
            shift 2
            ;;
        --modules)
            [ $# -ge 2 ] || {
                echo "--modules requires a module list"
                usage
                exit 1
            }
            MODULES_ARG=$2
            shift 2
            ;;
        --validate)
            VALIDATE_ONLY=1
            shift
            ;;
        --run)
            RUN_PROFILE=1
            shift
            ;;
        --force)
            FORCE_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

if [ -n "$PROFILE_NAME" ] && [ -n "$MODULES_ARG" ]; then
    echo "Use either --profile or --modules, not both."
    usage
    exit 1
fi

load_modules

if [ "$SHOW_LIST" = "1" ]; then
    list_modules
    echo
    list_profiles
fi

if [ "$VALIDATE_ONLY" = "1" ]; then
    [ "$SHOW_LIST" = "1" ] && echo
    if [ -n "$PROFILE_NAME" ]; then
        validate_profile "$PROFILE_NAME"
        echo
        echo "Validation passed."
        echo "Profiles checked: 1"
        echo "Modules loaded: ${#MODULE_FILE_MAP[@]}"
    elif [ -n "$MODULES_ARG" ]; then
        validate_modules
        echo
        echo "Validation passed."
        echo "Module set checked: 1"
        echo "Modules loaded: ${#MODULE_FILE_MAP[@]}"
    else
        validate_all
    fi
    exit 0
fi

if [ "$RUN_PROFILE" = "1" ]; then
    if [ -n "$PROFILE_NAME" ]; then
        run_profile_plan
        exit 0
    fi
    if [ -n "$MODULES_ARG" ]; then
        run_modules_plan
        exit 0
    fi
    echo "--run requires --profile or --modules"
    usage
    exit 1
fi

if [ -n "$PROFILE_NAME" ]; then
    [ "$SHOW_LIST" = "1" ] && echo
    show_profile_plan
fi

if [ -n "$MODULES_ARG" ]; then
    [ "$SHOW_LIST" = "1" ] && echo
    show_modules_plan
fi

if [ "$SHOW_LIST" = "0" ] && [ -z "$PROFILE_NAME" ] && [ -z "$MODULES_ARG" ]; then
    usage
    exit 1
fi
