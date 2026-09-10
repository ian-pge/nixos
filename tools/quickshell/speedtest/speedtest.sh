generation="${1:-0}"
temp_dir="$(mktemp -d)"
output_pipe="$temp_dir/output"
stderr_file="$temp_dir/stderr"
speedtest_pid=""
parser_pid=""
mkfifo "$output_pipe"

cleanup() {
  rm -rf "$temp_dir"
}

terminate() {
  for pid in "$speedtest_pid" "$parser_pid"; do
    if [[ -n "$pid" ]]; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  for pid in "$speedtest_pid" "$parser_pid"; do
    if [[ -n "$pid" ]]; then
      wait "$pid" 2>/dev/null || true
    fi
  done
  cleanup
  exit 143
}

trap terminate TERM INT
trap cleanup EXIT

jq --unbuffered -c --arg generation "$generation" \
  '. + {generation: $generation}' <"$output_pipe" &
parser_pid="$!"

speedtest --accept-license --accept-gdpr --format=json --progress=yes \
  --progress-update-interval=500 >"$output_pipe" 2>"$stderr_file" &
speedtest_pid="$!"

speedtest_status=0
wait "$speedtest_pid" || speedtest_status="$?"
parser_status=0
wait "$parser_pid" || parser_status="$?"

if [[ "$speedtest_status" -ne 0 || "$parser_status" -ne 0 ]]; then
  error="$(cat "$stderr_file")"
  jq -cn --arg generation "$generation" \
    --arg error "${error:-Speed test failed}" \
    '{type: "error", generation: $generation, error: $error}'
fi
