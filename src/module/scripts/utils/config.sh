#!/system/bin/sh
# Configure Reading and Writing Support Functions

#######################################
# Remove quotes from the configuration value
#######################################
strip_quotes() {
  printf "%s" "${1:-}" | tr -d '"' | tr -d '\r'
}

#######################################
# Read Configuration Values
#######################################
read_conf() {
  local file="$1"
  local key="$2"
  local default="${3:-}"
  local line value

  if [ -f "$file" ]; then
    line="$(grep -m 1 "^${key}=" "$file" 2> /dev/null || true)"
    if [ -n "$line" ]; then
      value="${line#*=}"
      strip_quotes "$value"
      return 0
    fi
  fi

  printf "%s" "$default"
}

#######################################
# Writing Configuration Values
#######################################
set_conf() {
  local file="$1"
  local key="$2"
  local value="$3"

  require_file "$file" "Profile does not exist: $file"

  if grep -q "^${key}=" "$file" 2> /dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf "%s=%s\n" "$key" "$value" >> "$file"
  fi
}

#######################################
# Add double quotes to the configuration value
#######################################
quote_conf() {
  printf '"%s"' "$1"
}

#######################################
# Determines whether the list contains specified values
#######################################
list_contains() {
  local list="$1"
  local item="$2"
  local value

  for value in $list; do
    [ "$value" = "$item" ] && return 0
  done

  return 1
}

#######################################
# Add value to the list
#######################################
list_add() {
  local list="$1"
  local item="$2"

  if list_contains "$list" "$item"; then
    printf "%s" "$list"
  elif [ -n "$list" ]; then
    printf "%s %s" "$list" "$item"
  else
    printf "%s" "$item"
  fi
}

#######################################
# Remove value from list
#######################################
list_remove() {
  local list="$1"
  local item="$2"
  local value output=""

  for value in $list; do
    [ "$value" = "$item" ] && continue
    if [ -n "$output" ]; then
      output="$output $value"
    else
      output="$value"
    fi
  done

  printf "%s" "$output"
}
