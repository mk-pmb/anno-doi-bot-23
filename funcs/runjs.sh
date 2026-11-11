#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function runjs_eval () {
  runjs__core "$@" nodejs -r enveval2401-pmb -e 0 || return $?
}


function runjs__core () {
  local ENV_CMD=( env_export_anno_cfg env )
  local KEY= VAL=
  for KEY in CODE DATA TEXT; do
    eval "VAL=\"\$$KEY\""
    [ -n "$VAL" ] || continue
    ENV_CMD+=( "$KEY=$VAL" )
  done
  "${ENV_CMD[@]}" "$@" || return $?
}


function runmjs_file () { runjs__core nodejs "$@"; return $?; }





return 0
