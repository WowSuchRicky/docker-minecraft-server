#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
fixture=$(cd "$(dirname "$0")" && pwd)/versions.json

# Load only getGTNHdownloadPath from the production script. The rest of the
# startup script intentionally does not run during this focused unit test.
tmp_function=$(mktemp)
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"; rm -f "$tmp_function"' EXIT
awk '
  /^function getGTNHdownloadPath\(\)\{/ { in_function=1 }
  /^function deleteGTNHbackup\(\)\{/ { in_function=0 }
  in_function { print }
' "$repo_root/scripts/start-deployGTNH" > "$tmp_function"
[[ -s "$tmp_function" && "$(sed '/./!d' "$tmp_function" | tail -n1)" == '}' ]] || {
  echo 'failed to extract complete getGTNHdownloadPath function' >&2
  exit 1
}

log() { :; }
debug() { :; }
logError() { printf 'error: %s\n' "$*" >&2; }
curl() {
  [[ "$1" == "-fsSL" && "$2" == "https://downloads.gtnewhorizons.com/versions.json" ]] || return 1
  cat "$GTNH_VERSIONS_FIXTURE"
}
mc-image-helper() {
  if [[ "$1" == java-release ]]; then
    printf '%s\n' "$GTNH_TEST_JAVA"
  else
    return 1
  fi
}

# shellcheck source=/dev/null
source "$tmp_function"

assert_url() {
  local version=$1 java=$2 expected=$3 fixture_path=${4:-$fixture}
  local gtnh_download_path=""
  export GTNH_PACK_VERSION=$version
  export GTNH_TEST_JAVA=$java
  export GTNH_VERSIONS_FIXTURE=$fixture_path
  getGTNHdownloadPath
  [[ "$gtnh_download_path" == "$expected" ]] || {
    printf 'expected %s, got %s\n' "$expected" "$gtnh_download_path" >&2
    return 1
  }
}

assert_failure() {
  local version=$1 java=$2 fixture_path=$3
  export GTNH_PACK_VERSION=$version
  export GTNH_TEST_JAVA=$java
  export GTNH_VERSIONS_FIXTURE=$fixture_path
  if (getGTNHdownloadPath); then
    printf 'expected selection to fail for version=%s java=%s fixture=%s\n' "$version" "$java" "$fixture_path" >&2
    return 1
  fi
}

assert_url latest 21 'https://example.invalid/2.8.4-java17.zip'
assert_url latest-dev 21 'https://example.invalid/2.9.0-rc-1-java17.zip'
assert_url latest-dev 21 'https://example.invalid/2.9.0-rc-1-java17.zip' "$(cd "$(dirname "$0")" && pwd)/versions-wrapper.json"
assert_url 2.9.0-beta-2 21 'https://example.invalid/2.9.0-beta-2-java17.zip'
assert_url 2.9.0-beta-2 8 'https://example.invalid/2.9.0-beta-2-java8.zip'

jq 'del(."2.9.0-beta-2".server.java17_2XUrl)' "$fixture" > "$fixture_dir/missing-java17.json"
jq 'del(."2.9.0-beta-2".server.java8Url)' "$fixture" > "$fixture_dir/missing-java8.json"
jq '."2.9.0-beta-2".maxJavaVersion = "25"' "$fixture" > "$fixture_dir/string-max-java.json"
jq '."2.9.0-beta-2".server.java17_2XUrl = "https://"' "$fixture" > "$fixture_dir/malformed-url.json"
printf '{not-json}\n' > "$fixture_dir/malformed.json"

assert_failure 2.9.0-beta-2 21 "$fixture_dir/missing-java17.json"
assert_failure 2.9.0-beta-2 8 "$fixture_dir/missing-java8.json"
assert_failure 2.9.0-beta-2 21 "$fixture_dir/string-max-java.json"
assert_failure 2.9.0-beta-2 21 "$fixture_dir/malformed-url.json"
assert_failure 2.9.0-beta-2 21 "$fixture_dir/malformed.json"
assert_failure 9.9.9 21 "$fixture"
assert_failure 2.9.0-beta-2 10 "$fixture"
assert_failure 2.9.0-beta-2 26 "$fixture"

if (
  GTNH_PACK_VERSION=2.9.0-beta-2
  GTNH_TEST_JAVA=21
  GTNH_VERSIONS_FIXTURE="$fixture_dir/does-not-exist.json"
  getGTNHdownloadPath
); then
  echo 'expected metadata retrieval failure' >&2
  exit 1
fi

echo 'GTNH versions.json selection tests passed'
