#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function cli_main () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local DBGLV="${DEBUGLEVEL:-0}"

  local -A CFG=() BOTRUN=( [start_uts]="$EPOCHSECONDS" )
  BOTRUN[task]="${1:-scan_and_assign}"; shift

  local BOT_PATH="$(readlink -m -- "$BASH_SOURCE"/..)"
  local BOT_FUNCD="$BOT_PATH/funcs"
  cd -- "$BOT_PATH" || return $?
  source -- "$BOT_FUNCD"/bot_init.sh || return $?
  source_these_libs "$BOT_FUNCD"/*.sh || return $?
  bot_init_before_config || return $?
  source_in_func "$BOT_FUNCD"/cfg.default.rc || return $?
  load_host_config doibot || return $?
  [ "$DBGLV" -lt 2 ] || echo D: "Gonna run bot task: ${BOTRUN[task]} $*" >&2
  "${BOTRUN[task]}" "$@" || return $?$(echo E: "Bot task failed (rv=$?):$(
    printf ' ‹%s›' "${BOTRUN[task]}" "$@")" >&2)
}



cli_main "$@"; exit $?
