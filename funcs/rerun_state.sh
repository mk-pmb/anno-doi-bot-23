#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function with_rerun_state () {
  [ -n "$RRS_TOPIC" ] || local RRS_TOPIC="${1:-noop}"
  local RRS_FILE="${CFG[doibot_rerun_state_dir]}"
  mkdir --parents -- "$RRS_FILE"
  RRS_FILE+="/$RRS_TOPIC.rc"
  >>"$RRS_FILE" || return 5$(
    echo "E: Failed write test for rerun state file: $RRS_FILE" >&2)
  local RRS_TMPF="$RRS_FILE.tmp-$$"
  >"$RRS_TMPF" || return 5$(
    echo "E: Failed write test for temporary rerun state file: $RRS_TMPF" >&2)

  # Pre-declare most vars used in with_rerun_state__inner_dict
  # so the only one it needs to declare itself is the dict itself
  # (so local -p will print only that):
  local RRS_RV= RRS_WAIT=
  with_rerun_state__inner_dict "$@"; RRS_RV=$?
  rm -- "$RRS_TMPF" 2>/dev/null || true # cleanup
  return "$RRS_RV"
}


function with_rerun_state__inner_dict () {
  local -A RERUN_STATE=( [earliest_next_run]='?' )

  while [ -n "${RERUN_STATE[earliest_next_run]}" ]; do
    RERUN_STATE=()
    source -- "$RRS_FILE" || return $?$(
      echo E: "Failed to read rerun state file: $RRS_FILE" >&2)
    if [ "$DBGLV" -ge 2 ]; then
      echo -n D: "Loaded rerun state for topic '$RRS_TOPIC': "
      local -p
    fi
    if [ "${RERUN_STATE[earliest_next_run]:-0}" -le "$EPOCHSECONDS" ]; then
      unset RERUN_STATE[earliest_next_run]
    else
      wait_until_uts "${RERUN_STATE[earliest_next_run]}" \
        'because the rerun state file says so.' || return 4$(
        echo E: "Failed to wait for earliest_next_run, rv=$?" >&2)
    fi
  done

  "$@"; RRS_RV=$?

  if [ "$DBGLV" -ge 2 ]; then
    echo -n D: "New rerun state for topic '$RRS_TOPIC'," \
      "to be saved to $RRS_TMPF: "
    local -p
  fi
  if [ "$RRS_TMPF" != '//rerun//nosave//' ]; then
    local -p >"$RRS_TMPF" || return 5$(
      echo "E: Failed save temporary rerun state file: $RRS_TMPF" >&2)
    mv --no-target-directory -- "$RRS_TMPF" "$RRS_FILE" || return 5$(
      echo "E: Failed activate temporary rerun state file: $RRS_TMPF" >&2)
  fi
  return "$RRS_RV"
}


function wait_until_uts () {
  local UNTIL="$1"; shift
  [ "${UNTIL:-0}" -ge 1 ] || return 0
  local WAIT=$(( UNTIL - EPOCHSECONDS ))
  [ "${WAIT:-0}" -ge 1 ] || return 0
  exec -a doibot-rerun-sleep sleep "$WAIT"s &
  local SLEEP_PID=$!
  logts P: "Waiting $WAIT seconds (until $(printf '%(%F %T %Z)T' "$UNTIL"
    ), sleep pid: $SLEEP_PID) $*"
  wait "$SLEEP_PID" 2>/dev/null
  local SLEEP_RV=$?
  local SIG=$(( SLEEP_RV - 128 ))
  if [ "$SIG" -lt 0 ]; then
    SIG=
  else
    # Our `sleep` was killed by a signal. Translate signal number to name
    # because the numbers differ accross CPU architectures.
    # (cf. man 7 signal, man 1 kill)
    SIG="$(kill -l $SIG)"
    SIG="${SIG#SIG}"
  fi
  case "${SIG:-$SLEEP_RV}" in
    USR1 | \
    ALRM ) return 0;;

    0 )
      [ "$EPOCHSECONDS" -ge "$UNTIL" ] || return 4$(
        echo E: $FUNCNAME: 'sleep finished too early.' >&2)
      return 0;;
  esac
  [ -z "$SIG" ] || SIG=" (probably killed by SIG$SIG)"
  echo E: $FUNCNAME: "failed to sleep, rv=$SLEEP_RV$SIG" >&2
  return 4
}


function with_rerun_state_fail_score () {
  [ -n "$RRS_TOPIC" ] || local RRS_TOPIC="$1"
  with_rerun_state with_rerun_state__inner_fail_score "$@" || return $?
}


function with_rerun_state__calc_next_earliest_rerun () {
  local WAIT="${CFG[doibot_rerun_min_delay]}"
  [ -n "$WAIT" ] || return 4$(
    echo E: $FUNCNAME: 'Empty doibot_rerun_min_delay' >&2)
  WAIT="$(date +%s --date="+$WAIT")"
  [ -n "$WAIT" ] || return 4$(
    echo E: $FUNCNAME: 'Failed to calculate date' >&2)
  RERUN_STATE[earliest_next_run]="$WAIT"
}


function with_rerun_state__inner_fail_score () {
  with_rerun_state__calc_next_earliest_rerun || return $?
  "$@"; local FAIL_SCORE=$?
  local OLD_FAIL_SCORE="${RERUN_STATE[fail_score]:-0}"
  local MAX_FAIL_SCORE=9009009009
  [ "$DBGLV" -lt 2 ] || echo D: $FUNCNAME: "Task $* -> fail='$FAIL_SCORE'" >&2
  if [ "$FAIL_SCORE" -lt 1 ]; then
    if [ "$OLD_FAIL_SCORE" != 0 ]; then
      RERUN_STATE[fail_score]=0
      echo D: "Cumulative fail score has been reset."
    fi
    with_rerun_state__set_rss healthy || true
  else
    (( FAIL_SCORE += OLD_FAIL_SCORE ))
    [ "$FAIL_SCORE" -ge "$OLD_FAIL_SCORE" ] || FAIL_SCORE="$MAX_FAIL_SCORE"$(
      echo W: "Cumulative fail score went beyond the limits of bash math!" >&2)
    [ "$FAIL_SCORE" -le "$MAX_FAIL_SCORE" ] || FAIL_SCORE="$MAX_FAIL_SCORE"
    RERUN_STATE[fail_score]="$FAIL_SCORE"
    echo W: "Cumulative fail score increased to $FAIL_SCORE." >&2
    if [ "$FAIL_SCORE" -lt "${CFG[doibot_rss_warnlevel]}" ]; then
      with_rerun_state__set_rss --no-replace 'minor trouble' || true
    else
      with_rerun_state__set_rss FAILING || true
    fi
  fi
  [ -z "$WAIT" ] || echo D: "Schedule for earliest next run is set to $(
    printf '%(%F %T %Z)T' "$WAIT")."
}


function with_rerun_state__set_rss () {
  local FEED='status'
  rssfeed_init || return $?
  # Now that $FEED has been adjusted to a full path, we can use that:
  local MSG='<item><title>'
  if [ "$1" == --no-replace ]; then
    shift
    grep -qFe "$MSG" -- "$FEED" && return 0
  fi
  MSG+="$1</title>"
  grep -qFe "$MSG" -- "$FEED" && return 0
  MSG="  $MSG<pubDate>$(date -R)</pubDate></item>"$'\n'
  rssfeed_init ITEMS="$MSG" || return $?
}




return 0
