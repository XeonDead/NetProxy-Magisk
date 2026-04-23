#!/system/bin/sh
# Clash API Helper function

#######################################
# Read controller address
#######################################
api_controller() {
  printf "%s" "${CLASH_API:-127.0.0.1:9999}"
}

#######################################
# Read controller key
#######################################
api_secret() {
  printf "%s" "${CLASH_SECRET:-singbox}"
}

#######################################
# Read main selector name
#######################################
api_selector_group() {
  printf "%s" "${SELECTOR_GROUP:-Proxy}"
}

#######################################
# Read speed test address
#######################################
api_delay_url() {
  printf "%s" "${DELAY_URL:-https://www.gstatic.com/generate_204}"
}

#######################################
# Simple URL coding
#######################################
url_encode_simple() {
  printf "%s" "$1" | sed 's/%/%25/g; s/ /%20/g; s/#/%23/g; s/?/%3F/g; s/&/%26/g; s/\//%2F/g; s/+/%2B/g'
}

#######################################
# extract JSON string field
#######################################
json_get_string() {
  local text="$1"
  local key="$2"

  printf "%s" "$text" | tr ',{}' '\n' | grep -m 1 "\"$key\"" | sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

#######################################
# initiate Clash API ask
#######################################
api_request() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local controller secret

  command_exists curl || return 1

  controller="$(api_controller)"
  secret="$(api_secret)"

  if [ -n "$data" ]; then
    curl -fsS --connect-timeout 3 --max-time 10 \
      -X "$method" \
      -H "Authorization: Bearer $secret" \
      -H "Content-Type: application/json" \
      -d "$data" \
      "http://$controller$path"
  else
    curl -fsS --connect-timeout 3 --max-time 10 \
      -X "$method" \
      -H "Authorization: Bearer $secret" \
      "http://$controller$path"
  fi
}

#######################################
# Determine whether the control interface is available
#######################################
api_is_available() {
  api_request GET "/configs" > /dev/null 2>&1
}

#######################################
# Wait for the control interface to be ready
#######################################
api_wait_available() {
  local retries="${1:-5}"
  local delay="${2:-1}"
  local i=0

  while [ "$i" -lt "$retries" ]; do
    api_is_available && return 0
    sleep "$delay"
    i=$((i + 1))
  done

  return 1
}

#######################################
# Module mode switch Clash model
#######################################
module_mode_to_clash_mode() {
  case "$1" in
    rule) printf "%s" "Rule" ;;
    global) printf "%s" "Global" ;;
    direct) printf "%s" "Direct" ;;
    *) return 1 ;;
  esac
}

#######################################
# Read the current operating mode
#######################################
api_get_mode() {
  local result

  result="$(api_request GET "/configs" 2> /dev/null)" || return 1
  json_get_string "$result" "mode"
}

#######################################
# Set current operating mode
#######################################
api_set_mode() {
  local mode="$1"
  local clash_mode payload

  clash_mode="$(module_mode_to_clash_mode "$mode")" || return 1
  payload="{\"mode\":\"$(json_escape "$clash_mode")\"}"

  api_request PATCH "/configs" "$payload" > /dev/null 2>&1
}

#######################################
# Read agent group data
#######################################
api_get_proxies() {
  api_request GET "/proxies"
}

#######################################
# Extract proxy group raw fragments
#######################################
api_selector_block() {
  local text="$1"
  local group="${2:-$(api_selector_group)}"
  local compact

  compact="$(printf "%s" "$text" | tr -d '\n')"
  printf "%s" "$compact" | sed -n 's/.*"'"$group"'":{\([^}]*\)}.*/\1/p'
}

#######################################
# Read the current node of the agent group
#######################################
api_selector_current() {
  local text="$1"
  local group="${2:-$(api_selector_group)}"
  local block

  block="$(api_selector_block "$text" "$group")"
  [ -n "$block" ] || return 1
  printf "%s" "$block" | sed -n 's/.*"now":"\([^"]*\)".*/\1/p'
}

#######################################
# List optional nodes for agent group
#######################################
api_selector_options() {
  local text="$1"
  local group="${2:-$(api_selector_group)}"
  local block list

  block="$(api_selector_block "$text" "$group")"
  [ -n "$block" ] || return 1

  list="$(printf "%s" "$block" | sed -n 's/.*"all":\[\([^]]*\)\].*/\1/p')"
  [ -n "$list" ] || return 1

  printf "%s" "$list" | sed 's/^"//; s/"$//; s/","/\n/g'
}

#######################################
# Switch nodes through the control interface
#######################################
api_select_proxy() {
  local tag="$1"
  local group="${2:-$(api_selector_group)}"
  local payload

  payload="{\"name\":\"$(json_escape "$tag")\"}"
  api_request PUT "/proxies/$(url_encode_simple "$group")" "$payload" > /dev/null 2>&1
}

#######################################
# Test node latency
#######################################
api_test_delay() {
  local tag="$1"
  local url="${2:-$(api_delay_url)}"
  local timeout="${3:-5000}"

  api_request GET "/proxies/$(url_encode_simple "$tag")/delay?timeout=$timeout&url=$(url_encode_simple "$url")"
}

#######################################
# Get connection information
#######################################
api_get_connections() {
  api_request GET "/connections"
}

#######################################
# Close specified connection
#######################################
api_close_connection() {
  local connection_id="$1"

  api_request DELETE "/connections/$(url_encode_simple "$connection_id")" > /dev/null 2>&1
}

#######################################
# Close all connections
#######################################
api_close_all_connections() {
  api_request DELETE "/connections" > /dev/null 2>&1
}
