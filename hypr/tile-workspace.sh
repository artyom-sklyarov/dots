#!/bin/bash
set -euo pipefail

PLACEHOLDER_CLASS=tile-placeholder
PLACEHOLDER_COMMAND="kitty --class $PLACEHOLDER_CLASS -o confirm_os_window_close=0"
PROGRAM=${0##*/}
SELF=$(readlink -f "$0")
STATE_DIR=${XDG_RUNTIME_DIR:-/tmp}/makegrid
SIZE_TOLERANCE=0.2

usage() {
    printf 'usage: %s [-w workspace] [--dry-run] [columns [rows]]\n' "$PROGRAM" >&2
    printf '       %s [-w workspace] columns rows --manage [--bg]  keep the workspace gridded\n' "$PROGRAM" >&2
    printf '                     (foreground, Ctrl+C stops it; --bg detaches)\n' >&2
    printf '       %s [-w workspace] --unmanage                  stop managing the workspace\n' "$PROGRAM" >&2
    printf '       %s --status                                   list managed workspaces\n' "$PROGRAM" >&2
    printf 'With -w, nothing happens unless that workspace is the active one; without it,\n' >&2
    printf 'the active workspace is used.\n' >&2
    exit 2
}

mkdir -p "$STATE_DIR"

manager_file() { printf '%s/ws-%s.manager' "$STATE_DIR" "$1"; }
order_file() { printf '%s/ws-%s.order' "$STATE_DIR" "$1"; }

read_manager() {
    local file pid columns rows
    file=$(manager_file "$1")
    [[ -f "$file" ]] || return 1
    read -r pid columns rows < "$file" || true
    if [[ -z "${pid:-}" ]] || ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$file"
        return 1
    fi
    printf '%s %s %s\n' "$pid" "${columns:--}" "${rows:--}"
}

stop_manager() {
    local info pid
    info=$(read_manager "$1") || return 1
    read -r pid _ <<< "$info"
    kill "$pid" 2>/dev/null || true
    for _ in {1..20}; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.05
    done
    rm -f "$(manager_file "$1")"
}

DRY_RUN=
BACKGROUND=
MODE=apply
TARGET_WORKSPACE=
grid_columns=
grid_rows=
expect_workspace=0
for arg in "$@"; do
    if (( expect_workspace )); then
        [[ "$arg" =~ ^[1-9][0-9]*$ ]] || usage
        TARGET_WORKSPACE=$arg
        expect_workspace=0
        continue
    fi
    case $arg in
        --dry-run) DRY_RUN=--dry-run ;;
        --manage) MODE=manage ;;
        --bg) BACKGROUND=1 ;;
        --unmanage) MODE=unmanage ;;
        --status) MODE=status ;;
        -w|--workspace) expect_workspace=1 ;;
        --workspace=*) set -- "${arg#*=}"; [[ "$1" =~ ^[1-9][0-9]*$ ]] || usage; TARGET_WORKSPACE=$1 ;;
        --tick) MODE=tick ;;
        -h|--help) usage ;;
        *)
            [[ "$arg" =~ ^[1-9][0-9]*$ ]] || usage
            if [[ -z "$grid_columns" ]]; then
                grid_columns=$arg
            elif [[ -z "$grid_rows" ]]; then
                grid_rows=$arg
            else
                usage
            fi
            ;;
    esac
done
(( ! expect_workspace )) || usage
[[ "$MODE" != tick || -n "$TARGET_WORKSPACE" ]] || usage

case $MODE in
    status)
        shopt -s nullglob
        for file in "$STATE_DIR"/ws-*.manager; do
            workspace=${file##*/ws-}
            workspace=${workspace%.manager}
            if info=$(read_manager "$workspace"); then
                read -r pid columns rows <<< "$info"
                printf 'workspace %s: %sx%s (pid %s)\n' "$workspace" "$columns" "$rows" "$pid"
            fi
        done
        exit 0
        ;;
    unmanage)
        workspace_id=${TARGET_WORKSPACE:-$(hyprctl activeworkspace -j | jq -er '.id')}
        stop_manager "$workspace_id" || printf '%s: workspace %s is not managed\n' "$PROGRAM" "$workspace_id" >&2
        exit 0
        ;;
    manage)
        workspace_id=${TARGET_WORKSPACE:-$(hyprctl activeworkspace -j | jq -er '.id')}
        if (( workspace_id < 1 )); then
            printf '%s: special workspaces are not supported\n' "$PROGRAM" >&2
            exit 1
        fi
        if [[ -z "$grid_columns" || -z "$grid_rows" ]]; then
            printf '%s: --manage needs columns and rows, e.g. %s 8 4 --manage\n' "$PROGRAM" "$PROGRAM" >&2
            exit 2
        fi
        stop_manager "$workspace_id" || true
        manager=("${SELF%/*}/makegrid-manage.py" "$workspace_id" "$grid_columns" "$grid_rows")
        if [[ -n "$BACKGROUND" ]]; then
            setsid "${manager[@]}" >> "$STATE_DIR/ws-$workspace_id.log" 2>&1 < /dev/null &
            disown
            printf '%s: managing workspace %s in the background, log: %s\n' "$PROGRAM" \
                "$workspace_id" "$STATE_DIR/ws-$workspace_id.log"
            exit 0
        fi
        exec "${manager[@]}"
        ;;
esac

lua_str() {
    local s=${1//\\/\\\\}
    s=${s//\"/\\\"}
    printf '"%s"' "$s"
}

dispatch() {
    local lua workspace
    case "$1" in
        exec)        lua="hl.dsp.exec_cmd($(lua_str "$2"))" ;;
        settiled)    lua="hl.dsp.window.float({ window = $(lua_str "$2"), action = \"disable\" })" ;;
        closewindow) lua="hl.dsp.window.close({ window = $(lua_str "$2") })" ;;
        focuswindow) lua="hl.dsp.focus({ window = $(lua_str "$2") })" ;;
        layoutmsg)   lua="hl.dsp.layout($(lua_str "$2"))" ;;
        movetoworkspacesilent)  # "WORKSPACE,WINDOW"
            workspace=${2%%,*}
            [[ "$workspace" =~ ^-?[0-9]+$ ]] || workspace=$(lua_str "$workspace")
            lua="hl.dsp.window.move({ window = $(lua_str "${2#*,}"), workspace = $workspace, follow = false })"
            ;;
        *)
            printf '%s: no Lua mapping for dispatcher %s\n' "$PROGRAM" "$1" >&2
            return 1
            ;;
    esac
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        printf 'hyprctl dispatch %q\n' "$lua"
    else
        hyprctl dispatch "$lua" >/dev/null
    fi
}

ratio_for_parts() {
    awk -v parts="$1" 'BEGIN { printf "%.6f", 2 / parts }'
}

placeholder_is_idle() {
    local pid=$1 child comm stat pgrp tpgid
    [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 0 )) || return 1
    for child in $(pgrep -P "$pid" || true); do
        comm=$(< "/proc/$child/comm") 2>/dev/null || continue
        stat=$(< "/proc/$child/stat") 2>/dev/null || continue
        [[ "$comm" == kitten ]] && continue
        case $comm in
            fish|bash|zsh|sh|dash) ;;
            *) return 1 ;;
        esac
        read -r _ _ pgrp _ _ tpgid _ <<< "${stat##*) }"
        if (( tpgid > 0 && tpgid != pgrp )); then
            return 1
        fi
    done
    return 0
}

workspace_json=$(hyprctl activeworkspace -j)
workspace_id=$(jq -er '.id' <<< "$workspace_json")
active_address=$(hyprctl activewindow -j | jq -r '.address // empty')
tiled_layout=$(jq -er '.tiledLayout' <<< "$workspace_json")

if [[ -n "$TARGET_WORKSPACE" && "$workspace_id" != "$TARGET_WORKSPACE" ]]; then
    exit 0
fi

if [[ "$MODE" == tick ]]; then
    [[ "$tiled_layout" == "dwindle" ]] || exit 0
elif [[ -z "$grid_columns" ]] && info=$(read_manager "$workspace_id"); then
    read -r _ columns rows <<< "$info"
    [[ "$columns" != - ]] && grid_columns=$columns
    [[ "$rows" != - ]] && grid_rows=$rows
fi

if [[ "$tiled_layout" != "dwindle" ]]; then
    printf '%s: active layout is %s, expected dwindle\n' "$PROGRAM" "$tiled_layout" >&2
    exit 1
fi

if (( workspace_id < 1 )); then
    printf '%s: special workspaces are not supported\n' "$PROGRAM" >&2
    exit 1
fi

clients_json=$(hyprctl clients -j | jq -c --argjson workspace "$workspace_id" \
    --argjson tiled_only "$([[ "$MODE" == tick ]] && echo true || echo false)" '
    [ .[]
      | select(
          .workspace.id == $workspace
          and .mapped == true
          and .hidden == false
          and .pinned == false
          and ((.fullscreen // 0) == 0)
          and (($tiled_only and .floating) | not)
        )
      | {address, pid, at, size, class, focusHistoryID}
    ]
')

idle_placeholders=()
while IFS=$'\t' read -r address pid; do
    if placeholder_is_idle "$pid"; then
        idle_placeholders+=("$address")
    fi
done < <(jq -r --arg class "$PLACEHOLDER_CLASS" '
    .[] | select(.class == $class) | [.address, (.pid // 0)] | @tsv
' <<< "$clients_json")

idle_json=$(jq -nc '$ARGS.positional' --args "${idle_placeholders[@]}")
real_json=$(jq -c --argjson idle "$idle_json" '
    [ .[] | select(.address as $address | $idle | index($address) | not) ]
' <<< "$clients_json")
real_count=$(jq 'length' <<< "$real_json")

if (( real_count == 0 )) && [[ -z "$grid_columns" ]]; then
    exit 0
fi

if [[ -n "$grid_columns" ]]; then
    columns=$grid_columns
else
    columns=$(awk -v n="$real_count" 'BEGIN { c = int(sqrt(n)); if (c * c < n) c++; print c }')
fi
if [[ -n "$grid_rows" ]]; then
    rows=$grid_rows
else
    rows=$(( (real_count + columns - 1) / columns ))
fi
cells=$(( columns * rows ))
spacers_needed=$(( cells - real_count ))

if (( cells == 0 )); then
    exit 0
fi

if (( spacers_needed < 0 )); then
    printf '%s: %d windows do not fit in a %dx%d grid\n' "$PROGRAM" "$real_count" "$columns" "$rows" >&2
    exit 4
fi

previous_order='[]'
if [[ -s "$(order_file "$workspace_id")" ]]; then
    previous_order=$(jq -c 'if type == "array" then . else [] end' "$(order_file "$workspace_id")" 2>/dev/null || echo '[]')
fi

GRID_JQ='
    def cx: .at[0] + .size[0] / 2;
    def cy: .at[1] + .size[1] / 2;
    def bucket($value; $origin; $extent; $count):
        [ ([ (($value - $origin) / ($extent / $count) - 0.000001 | floor), $count - 1 ] | min), 0 ] | max;
    def frame:
        (map(.at[0]) | min) as $left
        | (map(.at[1]) | min) as $top
        | { left: $left, top: $top,
            width: ([ (map(.at[0] + .size[0]) | max) - $left, 1 ] | max),
            height: ([ (map(.at[1] + .size[1]) | max) - $top, 1 ] | max) };
    def cell($f):
        bucket(cy; $f.top; $f.height; $rows) * $columns + bucket(cx; $f.left; $f.width; $columns);
'

mapfile -t real_order < <(jq -r --argjson all "$clients_json" --argjson order "$previous_order" \
    --argjson columns "$columns" --argjson rows "$rows" "$GRID_JQ"'
    ($all | frame) as $f
    | ($order | length > 0) as $has_order
    | map(. + { cell: cell($f),
                known: (if $has_order then (.address as $address | $order | index($address)) else 0 end) })
    | sort_by(
        if .known == null
        then [1, 0, 0, -(.focusHistoryID // 0), cy, cx, .address]
        else [0, .cell, .known, 0, cy, cx, .address]
        end)
    | .[].address
' <<< "$real_json")

if [[ "$DRY_RUN" != "--dry-run" ]]; then
    jq -nc '$ARGS.positional' --args "${real_order[@]}" > "$(order_file "$workspace_id")"
fi

if [[ "$MODE" == tick ]]; then
    order_json=$(jq -nc '$ARGS.positional' --args "${real_order[@]}")
    tiled_json=$(jq -c --argjson idle "$idle_json" --arg class "$PLACEHOLDER_CLASS" '
        [ .[] | select(.class != $class or (.address as $address | $idle | index($address))) ]
    ' <<< "$clients_json")
    if jq -e --argjson order "$order_json" --argjson columns "$columns" --argjson rows "$rows" \
        --argjson tolerance "$SIZE_TOLERANCE" "$GRID_JQ"'
        def off($a; $b): ($a - $b) | if . < 0 then -. else . end;
        frame as $f
        | ($f.width / $columns) as $cw
        | ($f.height / $rows) as $ch
        | length == ($columns * $rows)
          and all(.[]; off(.size[0]; $cw) <= $cw * $tolerance and off(.size[1]; $ch) <= $ch * $tolerance)
          and ([.[] | cell($f)] | unique | length) == ($columns * $rows)
          and (. as $windows
               | [range($order | length)]
               | all(. as $i | $windows[] | select(.address == $order[$i]) | cell($f) == $i))
    ' <<< "$tiled_json" >/dev/null; then
        exit 0
    fi
fi

if (( ${#real_order[@]} != real_count )); then
    printf '%s: failed to order %d windows, not touching anything\n' "$PROGRAM" "$real_count" >&2
    exit 1
fi

if [[ "$DRY_RUN" != "--dry-run" ]]; then
    rebuild_lock="$STATE_DIR/ws-$workspace_id.rebuilding"
    printf '%s\n' "$$" > "$rebuild_lock"
    trap 'rm -f "$rebuild_lock"' EXIT
fi

grid_slots=("${real_order[@]}")
for ((index = real_count; index < cells; index++)); do
    grid_slots+=("")
done

reuse_count=$(( ${#idle_placeholders[@]} < spacers_needed ? ${#idle_placeholders[@]} : spacers_needed ))
spawn_count=$(( spacers_needed - reuse_count ))
spacer_addresses=("${idle_placeholders[@]:0:reuse_count}")
surplus_placeholders=("${idle_placeholders[@]:reuse_count}")

if (( spawn_count > 0 )); then
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        for ((index = 0; index < spawn_count; index++)); do
            dispatch exec "$PLACEHOLDER_COMMAND"
            spacer_addresses+=("placeholder-$index")
        done
    else
        known_placeholder_addresses=$(hyprctl clients -j | jq -c --arg class "$PLACEHOLDER_CLASS" '
            [.[] | select(.class == $class) | .address]
        ')

        for ((index = 0; index < spawn_count; index++)); do
            dispatch exec "$PLACEHOLDER_COMMAND"
        done

        new_placeholders=()
        for ((attempt = 0; attempt < 50 + 10 * spawn_count; attempt++)); do
            mapfile -t new_placeholders < <(
                hyprctl clients -j | jq -r \
                    --argjson workspace "$workspace_id" \
                    --argjson known "$known_placeholder_addresses" \
                    --arg class "$PLACEHOLDER_CLASS" '
                        [ .[]
                          | select(.workspace.id == $workspace and .mapped == true and .class == $class)
                          | .address as $address
                          | select($known | index($address) | not)
                          | $address
                        ]
                        | .[]
                    '
            )
            if (( ${#new_placeholders[@]} >= spawn_count )); then
                break
            fi
            sleep 0.1
        done

        if (( ${#new_placeholders[@]} < spawn_count )); then
            printf '%s: timed out waiting for Kitty placeholders\n' "$PROGRAM" >&2
            exit 1
        fi

        spacer_addresses+=("${new_placeholders[@]:0:spawn_count}")
    fi
fi

grid_addresses=()
spacer_index=0
for slot in "${grid_slots[@]}"; do
    if [[ -n "$slot" ]]; then
        grid_addresses+=("$slot")
    else
        grid_addresses+=("${spacer_addresses[$spacer_index]}")
        spacer_index=$((spacer_index + 1))
    fi
done

if (( ${#grid_addresses[@]} != cells )); then
    printf '%s: built %d of %d cells, not touching anything\n' "$PROGRAM" "${#grid_addresses[@]}" "$cells" >&2
    exit 1
fi
for address in "${grid_addresses[@]}"; do
    if [[ -z "$address" ]]; then
        printf '%s: empty grid cell, not touching anything\n' "$PROGRAM" >&2
        exit 1
    fi
done

column_tops=()
for ((column = 0; column < columns; column++)); do
    column_tops+=("${grid_addresses[$column]}")
done

for address in "${grid_addresses[@]}"; do
    dispatch settiled "address:$address"
done

scratch=2147483646
workspaces_json=$(hyprctl workspaces -j)
while jq -e --argjson scratch "$scratch" 'any(.[]; .id == $scratch)' <<< "$workspaces_json" >/dev/null; do
    scratch=$((scratch - 1))
done

for address in "${grid_addresses[@]}"; do
    dispatch movetoworkspacesilent "$scratch,address:$address"
done

for address in "${surplus_placeholders[@]}"; do
    dispatch movetoworkspacesilent "$scratch,address:$address"
    dispatch closewindow "address:$address"
done

insert_window() {
    local opening=$1
    local direction=$2
    local new_address=$3

    dispatch focuswindow "address:$opening"
    dispatch layoutmsg "preselect $direction"
    dispatch movetoworkspacesilent "$workspace_id,address:$new_address"
}

set_split_ratio() {
    local opening=$1
    local ratio=$2

    dispatch focuswindow "address:$opening"
    dispatch layoutmsg "splitratio $ratio exact"
}

rest_anchor=${column_tops[0]}
dispatch movetoworkspacesilent "$workspace_id,address:$rest_anchor"

for ((column = 1; column < columns; column++)); do
    new_top=${column_tops[$column]}
    insert_window "$rest_anchor" r "$new_top"
    set_split_ratio "$rest_anchor" "$(ratio_for_parts $((columns - column + 1)))"
    rest_anchor=$new_top
done

for ((column = 0; column < columns; column++)); do
    previous=${column_tops[$column]}
    for ((row = 1; row < rows; row++)); do
        new_address=${grid_addresses[$((row * columns + column))]}
        insert_window "$previous" d "$new_address"
        set_split_ratio "$previous" "$(ratio_for_parts $((rows - row + 1)))"
        previous=$new_address
    done
done

for address in "${grid_addresses[@]}"; do
    if [[ "$address" == "$active_address" ]]; then
        dispatch focuswindow "address:$active_address"
        break
    fi
done

[[ "$MODE" == tick ]] && exit 10
exit 0
