#!/usr/bin/env bash
# env_loader.sh — source this; it locates and sources blender-env/env.sh
# (created by setup.sh) from any reasonable location.
if [ -z "${_ENV_LOADER_DONE:-}" ]; then
  _ENV_LOADER_DONE=1
  _FOUND_ENV=""
  for _cand in \
    "${WORKDIR:-}/blender-env/env.sh" \
    "/kaggle/working/blender-env/env.sh" \
    "$HOME/blender-work/blender-env/env.sh" \
    "$HOME/blender-kaggle/blender-env/env.sh"
  do
    if [ -n "$_cand" ] && [ -f "$_cand" ]; then _FOUND_ENV="$_cand"; break; fi
  done
  if [ -z "$_FOUND_ENV" ]; then
    echo "❌ blender-env/env.sh not found — run setup.sh first." >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$_FOUND_ENV"
  unset _FOUND_ENV _cand
fi
