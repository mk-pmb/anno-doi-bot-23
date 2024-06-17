#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function scan_and_assign () {
  local RSS_URL="bot-auth:by/has_stamp;rss=vh/_ubhd:doiAssign"
  logts P: "Scan RSS feed: $RSS_URL"
  local RSS_RAW="$(webfetch "$RSS_URL")"
  local RSS_XML="${RSS_RAW//[$'\r\n \t']/ }"
  if ! rssfeed_has_channel <<<"$RSS_XML"; then
    log_dump rss.xml <<<"$RSS_RAW"
    echo E: "No RSS channel in feed response." >&2
    return 2
  fi
  local RSS_LINKS=()
  readarray -t RSS_LINKS < <(<<<"$RSS_XML" grep -oPe '<link>[^<>]+')

  local MANDATORY_VH_ENTRY_FIELDS=(
    id
    created
    )
  local VH_LINK=
  local N_RSS_LINKS="${#RSS_LINKS[@]}"
  local ERR_CNT=0
  for VH_LINK in "${RSS_LINKS[@]}"; do
    VH_LINK="${VH_LINK#*>}"
    scan_and_assign__found_link && continue
    echo W: "$FUNCNAME: Failure (rv=$?) for VH link: $VH_LINK" >&2
    (( ERR_CNT += 1 ))
  done

  [ "$ERR_CNT" == 0 ] || return 4$(
    echo E: "$FUNCNAME: Encountered problems with $ERR_CNT VH links." >&2)
  logts P: "Success. Processed $N_RSS_LINKS VH links."
}


function scan_and_assign__found_link () {
  logts P: "Follow VH link: $VH_LINK"
  [[ "$VH_LINK" == "${CFG[anno_public_baseurl]}"* ]] || return 3$(
    echo E: 'Link not inside anno_public_baseurl!' >&2)

  local RGX='/([A-Za-z0-9_.-]+)/versions$'
  local ANNO_BASE_ID=
  [[ "$VH_LINK" =~ $RGX ]] && ANNO_BASE_ID="${BASH_REMATCH[1]}"
  [ -n "$ANNO_BASE_ID" ] || return 5$(
    echo E: "Failed to detect anno base ID from VH link." >&2)

  local ORIG_VH_REPLY="$(webfetch -- "$VH_LINK")"
  # log_dump <<<"$ORIG_VH_REPLY" "vh-reply.$ANNO_BASE_ID.json" || return $?

  local LIST=()
  readarray -t LIST < <(runjs_eval DATA="$ORIG_VH_REPLY" \
    CODE='data.first.items.forEach(x => clog(toBashDictSp(x)));'
    ) || return 6$(echo E: "Failed to parse VH reply." >&2)

  local -A VH_INFO=()
  # local VH_ACCUM=
  # local RETRACTED_ANNO_JSON='false' # A literal JSON value.
  local FIRST_CREATED=
  local VHE_NUM=0 VH_LENGTH="${#LIST[@]}"
  local -A VHE_MEM=( [n_total_new_dois]=0 )
  for DATA in "${LIST[@]}"; do
    VH_INFO=()
    eval "VH_INFO=( $DATA )"
    # ^-- e.g. [created]=2023-06…Z [as:deleted]=2023-09…Z [id]='http://…~3'
    # echo D: "  >> VH entry: $DATA <<"
    DATA=
    (( VHE_NUM += 1 ))
    scan_and_assign__vh_entry || return $?$(
      echo E: "Scanning version history failed:" \
        "Error while processing VH entry #$VHE_NUM" >&2)
  done
  [ "$VHE_NUM" -ge 1 ] || return 4$(echo E: 'Found no VH entries.' >&2)
  [ "${VHE_MEM[lvr:anno_id_url]}" == 0 ] \
    || scan_and_assign__reg_lvr_doi || return $?

  scan_and_assign__stamp_newly_registered_dois || return $?

  # VH_ACCUM="[$VH_ACCUM]"
  # local ACCUM_DUMP="${CFG[doibot_log_dest_dir]}/vh-accum.$ANNO_BASE_ID.json"
  # echo "$VH_ACCUM" >"$ACCUM_DUMP" || return 5$(
  #   echo E: 'Failed to dump the accumulated VH.' >&2)
}


function scan_and_assign__vh_entry () {
  local TRACE_ENT="entry #$VHE_NUM"
  local KEY= VAL=
  for KEY in "${MANDATORY_VH_ENTRY_FIELDS[@]}"; do
    [ -n "${VH_INFO[$KEY]}" ] || return 4$(
      echo E: "$TRACE_ENT has no '$KEY' field!" >&2)
  done

  local ANNO_ID_URL="${VH_INFO[id]}"
  local ANNO_VER_NUM="$(detect_anno_ver_num_from_id_url "$ANNO_ID_URL")"
  [ -n "$ANNO_VER_NUM" ] || return 4

  local EXPECTED_SUFFIX="/$ANNO_BASE_ID${CFG[anno_url_versep]}$ANNO_VER_NUM"
  [[ "$ANNO_ID_URL" == *"$EXPECTED_SUFFIX" ]] || return 6$(
    echo E: "Unexpected anno ID URL (expected suffix '$EXPECTED_SUFFIX'):" \
      "$ANNO_ID_URL" >&2)

  [ -n "$FIRST_CREATED" ] || FIRST_CREATED="${VH_INFO[created]}"

  # [ -z "$VH_ACCUM" ] || VH_ACCUM+=$',\n'
  if [ -n "${VH_INFO[as:deleted]}" ]; then
    echo P: "  • $TRACE_ENT: retracted. skip."
    # VH_ACCUM+="$RETRACTED_ANNO_JSON"
    return 0
  fi

  echo P: "  • $TRACE_ENT: download…"
  local ANNO_JSON="$(webfetch -- "$ANNO_ID_URL")"
  case "$ANNO_JSON" in
    '' )
      echo E: "Failed to request anno: $ANNO_ID_URL" >&2
      return 6;;
    *'{'*'"@context":'*'"'*'"'*'}' ) ;;
    'Gone: Annotation was unpublished'* )
      # Version history not already announcing the retraction may happen
      # due to race condition, bug, or configuration.
      echo P: '    • retracted. skip.'
      # VH_ACCUM+="$RETRACTED_ANNO_JSON"
      return 0;;
    * )
      ANNO_JSON="${ANNO_JSON//$'\n'/¶ }"
      [ "${#ANNO_JSON}" -lt 128 ] || ANNO_JSON="${ANNO_JSON:0:127}…"
      echo E: "Response seems to not be an annotation: $ANNO_JSON" >&2
      return 6;;
  esac
  # log_dump <<<"$ANNO_JSON" "anno.$ANNO_BASE_ID~$VHE_NUM.json" || return $?

  local OLD_DOI="${VH_INFO[dc:identifier]}"
  local REG_DOI="$OLD_DOI"
  local DOI_TARGET_URL="$ANNO_ID_URL"
  VHE_MEM["$VHE_NUM":anno_id_url]="$ANNO_ID_URL"
  VHE_MEM[lvr:anno_id_url]="$ANNO_ID_URL"
  VHE_MEM[lvr:anno_json]="$ANNO_JSON"
  VHE_MEM["$VHE_NUM":doi_target_url]="$DOI_TARGET_URL"
  if [ -n "$OLD_DOI" ]; then
    echo P: "    • adapter: update existing DOI: <$OLD_DOI>"
  else
    echo P: "    • adapter: register new DOI:"
    REG_DOI="$(scan_and_assign__decide_versep)"
    [ -n "$REG_DOI" ] || return 4$(
      echo E: $FUNCNAME: "Failed to decide the version separator." >&2)
    REG_DOI="${CFG[anno_doi_prefix]}$ANNO_BASE_ID$(
      )$REG_DOI$ANNO_VER_NUM${CFG[anno_doi_suffix]}"
    VHE_MEM["$VHE_NUM":stamp_doi]="$REG_DOI"
    (( VHE_MEM[n_total_new_dois] += 1 ))
  fi
  scan_and_assign__reg_one_doi || return $?

  # VH_ACCUM+="$ANNO_JSON"
}


function scan_and_assign__decide_versep () {
  local E="The version separator exception for anno base ID '$ANNO_BASE_ID'"
  # ^-- Keep that list of de-deblanked versions around for potential error
  # reporting.
  local VS="${CFG[anno_doi_versep_exceptions]//$'\r'/}"

  local FOUND="$( echo "${VS//[$' \t']/}" | cut -d '#' -f 1 \
    | grep -Fine "/$ANNO_BASE_ID/" )"
  # ^-- Using `cut` `grep -Pose '^[^#]*'` would not accept lines that
  #     start with something else. However, we want all lines printed
  #     in order to have reliable line numbers.

  case "$FOUND" in
    '' ) echo "${CFG[anno_doi_versep]}"; return 0;;
    *$'\n'* ) echo "$E is defined more than once!" >&2; return 20;;
  esac
  local LNUM="${FOUND%%:*}"
  FOUND="${FOUND#*:}"
  case "$FOUND" in
    '' ) ;;
    */ ) echo "$E must not end with slash." >&2; return 4;;
    */*/* ) FOUND="${FOUND#*/*/}";;
    * ) echo "$E Exotic flow control or grep failed." >&2; return 60;;
  esac
  case "$FOUND" in
    *'%'* | *'?'* )
      echo "$E contains inacceptable character(s): '$(
        sed -nre "$LNUM"p <<<"$VS" )'" >&2
      return 20;;
  esac
  echo "$FOUND"
}


function scan_and_assign__reg_one_doi () {
  [ -n "$FIRST_CREATED" ] || return 4$(
    echo E: $FUNCNAME: "Missing creation date of first anno version!" >&2)
  [ -n "$DOI_TARGET_URL" ] || return 4$(
    echo E: $FUNCNAME: "Missing target URL for DOI!" >&2)
  local REG_CMD=(
    env_export_anno_cfg env
    anno_initial_version_date="$FIRST_CREATED"
    # anno_base_id="$ANNO_BASE_ID"
    # anno_ver_num="$VHE_NUM"
    anno_doi_expect="$REG_DOI"
    )
  case "$DOI_TARGET_URL" in
    'anno-fx:latest' )
      REG_CMD+=(
        anno_ver_fx='lvr'
        anno_custom_url="$DOI_TARGET_URL"
        )
      DOI_TARGET_URL="${VHE_MEM[lvr:anno_id_url]}"
      ;;
  esac
  REG_CMD+=(
    anno_doi_targeturl="$DOI_TARGET_URL"
    "${CFG[doibot_adapter_prog]}"
    ${CFG[doibot_adapter_args]}
    )
  [ "$DBGLV" -lt 4 ] || local -p | sed -re 's~^~\t~' \
    | fmt --width=120 --goal=115 | sed -rf <(echo '
    s~^(\s+)(\[)~\1  \2~
    s~\S~\x1b[2m&~
    /\x1b/s~$~\x1b[0m~
    ')
  local REG_MSG= REG_RV= # pre-declare
  REG_MSG="$(<<<"$ANNO_JSON" "${REG_CMD[@]}" 2>&1)"; REG_RV=$?
  local LAST_LINE="${REG_MSG##*$'\n'}"
  local DOI_NS='urn:doi:'
  local LL_EXPECTED="+OK reg/upd <$DOI_NS$REG_DOI>"
  case "$REG_RV:$LAST_LINE" in
    "0:$LL_EXPECTED" )
      scan_and_assign__report_warnings "${REG_MSG%$'\n'*}"
      echo P: "    • adapter succeeded. <$DOI_NS$REG_DOI>"
      return 0;;
    "0:+OK reg/upd <$DOI_NS"*'>' )
      scan_and_assign__report_warnings "${REG_MSG%$'\n'*}"
      echo E: "Adapter says it has registered this (wrong) DOI:" \
        "<${LAST_LINE#*<}, expected: <$DOI_NS$REG_DOI>" >&2
      return 6;;
  esac
  if [ -n "$REG_MSG" ]; then
    echo E: "    • adapter failed with exit code $REG_RV and this message:" >&2
    nl -ba <<<"$REG_MSG" | sed -re 's~^~E: > ~' >&2
    echo E: $'Expected:\t'"$LL_EXPECTED"
  else
    echo E: "    • adapter silently failed with exit code $REG_RV." >&2
  fi
  return "$REG_RV"
}


function scan_and_assign__stamp_newly_registered_dois () {
  local N_NEW="${VHE_MEM[n_total_new_dois]}"
  # [ "$N_NEW" == 0 ] && return 0

  echo P: "  • We need to stamp $N_NEW new DOIs."
  local VHE_NUM=0 FAILS=0 ANNO_VERS_ID= DOI=
  local -A STAMP_META=()
  while [ "$VHE_NUM" -lt "$VH_LENGTH" ]; do
    (( VHE_NUM += 1 ))
    DOI="${VHE_MEM["$VHE_NUM":stamp_doi]}"
    [ -n "$DOI" ] || continue
    # dc:identifier = https://doi.org/$DOI"
    echo P: "    • submit DOI stamp for entry #$VHE_NUM: $DOI"
    ANNO_VERS_ID="${VHE_MEM["$VHE_NUM":anno_id_url]##*/}"
    STAMP_META=(
      [anno_id_url]="${VHE_MEM["$VHE_NUM":anno_id_url]}"
      [anno_vers_id]="$ANNO_VERS_ID"
      [bare_doi]="$DOI"
      [dest_url]="${VHE_MEM["$VHE_NUM":doi_target_url]}"
      )
    stamp_one_newly_registered_doi "$ANNO_VERS_ID" "$DOI" && continue
    echo "E: Failed to stamp anno '$ANNO_VERS_ID' with DOI '$DOI'!" >&2
    (( FAILS += 1 ))
  done
  [ "$FAILS" == 0 ] || return 4 # Flatrate severity per base ID.
}


function scan_and_assign__report_warnings () {
  local MSG="$1"
  case $'\n'"$MSG" in
    *$'\n'[EW]:* )
      echo W: "    • adapter output seems to include warnings:" >&2
      <<<"$MSG" sed -re '/^P: /d' | nl -ba | sed -re 's~^~W: > ~' >&2
      ;;
  esac
}


function scan_and_assign__reg_lvr_doi () {
  # lvr = Latest Version Redirect
  local ANNO_JSON="${VHE_MEM[lvr:anno_json]}"
  [ -n "$ANNO_JSON" ] || return 4$(
    echo E: $FUNCNAME: 'No cached ANNO_JSON for LVR!' >&2)
  local REG_DOI="${CFG[anno_doi_prefix]}$ANNO_BASE_ID${CFG[anno_doi_suffix]}"
  local DOI_TARGET_URL='anno-fx:latest'
  scan_and_assign__reg_one_doi || return $?$(
    echo E: 'Failed to update LVR DOI.' >&2)
}











return 0
