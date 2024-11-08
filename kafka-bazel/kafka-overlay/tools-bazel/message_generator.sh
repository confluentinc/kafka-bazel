#! /usr/bin/env bash

SRCS=$1
OUT=$2
MESSAGE_GENERATOR=$3
ZIPPER=$4
# grab the rest as the args for messge_generator
MESSAGE_GENERATOR_ARGS=${@:5}

FIRST=$(echo $SRCS | awk '{print $1}')
FIRST_DIR=$(dirname $FIRST)

# check if SRCS is empty, if so, don't run $MESSAGE_GENERATOR
if [ -z "$SRCS" ]; then
  mkdir -p generated/srcs
  $ZIPPER fc $OUT generated/srcs
  exit 0
fi

$MESSAGE_GENERATOR $MESSAGE_GENERATOR_ARGS -i $FIRST_DIR
$ZIPPER fc $OUT generated/srcs/*