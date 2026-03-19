#!/usr/bin/env bash

set -euo pipefail

MODE="${1:-}"

if [[ "${MODE}" != "update" && "${MODE}" != "validate" ]]; then
  echo "Usage: $0 <update|validate>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

UPSTREAM_BASE="https://raw.githubusercontent.com/redhat-ai-dev/lightspeed-configs/main"
CONFIG_URL="${UPSTREAM_BASE}/llama-stack-configs/config.yaml"
DEFAULT_ENV_URL="${UPSTREAM_BASE}/env/default-values.env"
LIGHTSPEED_STACK_URL="${UPSTREAM_BASE}/lightspeed-core-configs/lightspeed-stack.yaml"
IMAGES_URL="${UPSTREAM_BASE}/images.yaml"

BUILDER_IMAGE_PATTERN='/^FROM / && $3=="AS" && $4=="builder"'
RAG_IMAGE_PATTERN='/^RAG_CONTENT_IMAGE[[:space:]]*\?=/'

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fetch() {
  curl -fsSL "$1" -o "$2"
}

# Keeps the repository-specific llama_stack library-client config,
# even though upstream lightspeed-stack.yaml uses direct URL mode.
apply_lightspeed_stack_override() {
  local file_path="$1"
  local tmp_file
  tmp_file="$(mktemp)"
  awk '
    BEGIN { in_block=0; replaced=0 }
    /^llama_stack:[[:space:]]*$/ {
      print "llama_stack:"
      print "  use_as_library_client: true"
      print "  library_client_config_path: /app-root/config.yaml"
      in_block=1
      replaced=1
      next
    }
    in_block && $0 ~ /^[^[:space:]]/ { in_block=0 }
    in_block { next }
    { print }
    END {
      if (replaced==0) {
        print "llama_stack:"
        print "  use_as_library_client: true"
        print "  library_client_config_path: /app-root/config.yaml"
      }
    }
  ' "${file_path}" > "${tmp_file}"
  mv "${tmp_file}" "${file_path}"
}

# Extracts the image value from a section in images.yaml (e.g. "lightspeed-core" -> "quay.io/...:tag")
extract_image_from_images_yaml() {
  local section="$1"
  local file_path="$2"
  awk -v section="${section}" '
    $0 ~ "^" section ":" { in_section=1; next }
    in_section && $0 ~ "^[^[:space:]]" { in_section=0 }
    in_section && $0 ~ "^[[:space:]]*image:[[:space:]]" {
      line=$0
      sub(/^[[:space:]]*image:[[:space:]]*/, "", line)
      print line
      exit
    }
  ' "${file_path}"
}

# Replaces the first line matching a pattern with a replacement string, fails if no match found
replace_line() {
  local file_path="$1"
  local pattern="$2"
  local replacement="$3"
  local tmp_file
  tmp_file="$(mktemp)"
  awk -v replacement="${replacement}" "
    BEGIN { replaced=0 }
    ${pattern} && replaced==0 {
      print replacement
      replaced=1
      next
    }
    { print }
    END {
      if (replaced==0) {
        exit 2
      }
    }
  " "${file_path}" > "${tmp_file}"
  mv "${tmp_file}" "${file_path}"
}

extract_builder_image() {
  awk "${BUILDER_IMAGE_PATTERN}"'{print $2; exit}' "$1"
}

extract_rag_image() {
  awk "${RAG_IMAGE_PATTERN}"'{line=$0; sub(/^RAG_CONTENT_IMAGE[[:space:]]*\?=[[:space:]]*/, "", line); print line; exit}' "$1"
}

compare_or_update_file() {
  local src="$1"
  local dest="$2"
  local label="$3"

  if [[ "${MODE}" == "update" ]]; then
    cp "${src}" "${dest}"
    echo "Updated ${label}"
    return 0
  fi

  if ! cmp -s "${src}" "${dest}"; then
    echo "Drift detected: ${label}" >&2
    return 1
  fi
}

compare_or_update_value() {
  local current="$1"
  local expected="$2"
  local label="$3"

  if [[ "${current}" != "${expected}" ]]; then
    echo "Drift detected: ${label} (${current}) != ${expected}" >&2
    return 1
  fi
}

fetch "${CONFIG_URL}" "${TMP_DIR}/config.yaml"
fetch "${DEFAULT_ENV_URL}" "${TMP_DIR}/default-values.env"
fetch "${LIGHTSPEED_STACK_URL}" "${TMP_DIR}/lightspeed-stack.yaml"
fetch "${IMAGES_URL}" "${TMP_DIR}/images.yaml"
apply_lightspeed_stack_override "${TMP_DIR}/lightspeed-stack.yaml"

lightspeed_core_image="$(extract_image_from_images_yaml "lightspeed-core" "${TMP_DIR}/images.yaml")"
rag_content_image="$(extract_image_from_images_yaml "rag-content" "${TMP_DIR}/images.yaml")"

config_path="${REPO_ROOT}/config.yaml"
default_env_path="${REPO_ROOT}/env/default-values.env"
lightspeed_stack_path="${REPO_ROOT}/lightspeed-stack.yaml"
containerfile_path="${REPO_ROOT}/Containerfile"
makefile_path="${REPO_ROOT}/Makefile"

status=0

compare_or_update_file "${TMP_DIR}/config.yaml" "${config_path}" "config.yaml" || status=1
compare_or_update_file "${TMP_DIR}/default-values.env" "${default_env_path}" "env/default-values.env" || status=1
compare_or_update_file "${TMP_DIR}/lightspeed-stack.yaml" "${lightspeed_stack_path}" "lightspeed-stack.yaml" || status=1

if [[ "${MODE}" == "update" ]]; then
  replace_line "${containerfile_path}" "${BUILDER_IMAGE_PATTERN}" "FROM ${lightspeed_core_image} AS builder"
  echo "Updated Containerfile builder image to ${lightspeed_core_image}"
  replace_line "${makefile_path}" "${RAG_IMAGE_PATTERN}" "RAG_CONTENT_IMAGE ?= ${rag_content_image}"
  echo "Updated Makefile RAG_CONTENT_IMAGE to ${rag_content_image}"
else
  current_builder_image="$(extract_builder_image "${containerfile_path}")"
  current_rag_image="$(extract_rag_image "${makefile_path}")"

  compare_or_update_value "${current_builder_image}" "${lightspeed_core_image}" "Containerfile builder image" || status=1
  compare_or_update_value "${current_rag_image}" "${rag_content_image}" "Makefile RAG_CONTENT_IMAGE" || status=1
fi

if [[ "${MODE}" == "validate" && "${status}" -eq 0 ]]; then
  echo "Upstream synced content is up to date."
fi

exit "${status}"
