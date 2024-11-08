#!/bin/bash

# Create temporary files, sed wasn't allowing in place edits on the input files.
tmp1=$(mktemp)
tmp2=$(mktemp)

# The unified diff output includes timestamps, which causes non-deterministic diffs.
# This removes the timestamps from those lines (e.g. --- 2024-01-01 00:00:00.000000000 +0000)
sed -e '/^---/ s/\t.*//' -e '/^\+\+\+/ s/\t.*//' "$1" > "$tmp1"
sed -e '/^---/ s/\t.*//' -e '/^\+\+\+/ s/\t.*//' "$2" > "$tmp2"

# Move temporary files back to original files
mv "$tmp1" "$1"
mv "$tmp2" "$2"

diff "$1" "$2"
DIFF_EXIT_CODE=$?
if [ $DIFF_EXIT_CODE -eq 1 ]; then
  echo -e "To accept the differences, run: \n\tcp bazel-bin/$1 $1_expected"
fi
exit $DIFF_EXIT_CODE