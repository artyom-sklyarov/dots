#!/bin/bash
set -euo pipefail

PLACEHOLDER_CLASS=tile-placeholder
PLACEHOLDER_COMMAND="kitty --class $PLACEHOLDER_CLASS -o confirm_os_window_close=0"
PROGRAM=${0##*/}

usage() {
    printf 'usage: %s [--dry-run] [columns [rows]]\n' "$PROGRAM" >&2
    exit 2
}

DRY_RUN=
grid_columns=
grid_rows=
for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=--dry-run ;;
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

dispatch() {
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        printf 'hyprctl dispatch'
        printf ' %q' "$@"
        printf '\n'
    else
        hyprctl dispatch "$@"
    fi
}

ratio_for_parts() {
    awk -v parts="$1" 'BEGIN { printf "%.6f", 2 / parts }'
}

placeholder_is_idle() {
    local pid=$1 child
    [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 0 )) || return 1
    for child in $(pgrep -P "$pid" || true); do
        if pgrep -P "$child" >/dev/null; then
            return 1
        fi
    done
    return 0
}

workspace_json=$(hyprctl activeworkspace -j)
workspace_id=$(jq -er '.id' <<< "$workspace_json")
active_address=$(hyprctl activewindow -j | jq -r '.address // empty')
tiled_layout=$(jq -er '.tiledLayout' <<< "$workspace_json")

if [[ "$tiled_layout" != "dwindle" ]]; then
    printf '%s: active layout is %s, expected dwindle\n' "$PROGRAM" "$tiled_layout" >&2
    exit 1
fi

if (( workspace_id < 1 )); then
    printf '%s: special workspaces are not supported\n' "$PROGRAM" >&2
    exit 1
fi

clients_json=$(hyprctl clients -j | jq -c --argjson workspace "$workspace_id" '
    [ .[]
      | select(
          .workspace.id == $workspace
          and .mapped == true
          and .hidden == false
          and .pinned == false
          and ((.fullscreen // 0) == 0)
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
    exit 1
fi

if (( real_count == 0 )); then
    grid_slots=()
    for ((index = 0; index < cells; index++)); do
        grid_slots+=("")
    done
else
    mapfile -t grid_slots < <(jq -r \
        --argjson columns "$columns" --argjson rows "$rows" --argjson cells "$cells" '
        def cx: .at[0] + .size[0] / 2;
        def cy: .at[1] + .size[1] / 2;
        def bucket($value; $origin; $extent; $count):
            [ ([ (($value - $origin) / ($extent / $count) - 0.000001 | floor), $count - 1 ] | min), 0 ] | max;
        (map(.at[0]) | min) as $left
        | (map(.at[1]) | min) as $top
        | ([ (map(.at[0] + .size[0]) | max) - $left, 1 ] | max) as $width
        | ([ (map(.at[1] + .size[1]) | max) - $top, 1 ] | max) as $height
        | map(. + { want: (bucket(cy; $top; $height; $rows) * $columns + bucket(cx; $left; $width; $columns)) })
        | sort_by([.want, cy, cx, (.focusHistoryID // 999999), .address])
        | reduce .[] as $window ([range($cells) | null];
            . as $slots
            | ([range($window.want; $cells), range(0; $window.want)]
               | map(select($slots[.] == null)) | first) as $slot
            | .[$slot] = $window.address)
        | .[] | (. // "")
    ' <<< "$real_json")
fi

if (( ${#grid_slots[@]} != cells )); then
    printf '%s: failed to assign %d windows to a %dx%d grid\n' \
        "$PROGRAM" "$real_count" "$columns" "$rows" >&2
    exit 1
fi

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
        known_placeholder_addresses=$(jq -c --arg class "$PLACEHOLDER_CLASS" '
            [.[] | select(.class == $class) | .address]
        ' <<< "$clients_json")

        for ((index = 0; index < spawn_count; index++)); do
            dispatch exec "$PLACEHOLDER_COMMAND"
        done

        new_placeholders=()
        for ((attempt = 0; attempt < 50; attempt++)); do
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
