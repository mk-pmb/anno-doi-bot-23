#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function rm_logs_older_than_one_hour () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local BOTDIR="$(readlink -m -- "$BASH_SOURCE"/../..)"
  cd -- "$BOTDIR" || return $?
  [ "${MINMIN:-0}" -ge 1 ] || local MINMIN=60
  # minmin: minimum age in minutes
  # mmin: modified n minutes ago
  exec find logs.@*/ -maxdepth 2 -type f -name 'cron_task.*.txt' \
    -mmin +"$MINMIN" -print -delete || true
  rmdir -- logs.@*/[0-9][0-9][0-9][0-9]/ 2>/dev/null || true
}



rm_logs_older_than_one_hour "$@"; exit $?
