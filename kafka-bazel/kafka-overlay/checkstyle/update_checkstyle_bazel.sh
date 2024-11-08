#!/usr/bin/env bash

set -euo pipefail

output_xml="$1"
checkstyle_xml="$2"
import_control_xml=$(basename "$3")
suppressions_xml=$(basename "$4")
java_header="${5:-}"

if [ -n "$java_header" ]; then
  java_header=$(basename "$java_header")
fi

cat "$checkstyle_xml" | sed \
  -e "s:\${config_loc}/\${importControlFile}:${import_control_xml}:g" \
  -e "s:\${config_loc}/suppressions.xml:${suppressions_xml}:g" \
  -e "s:\${config_loc}/java.header:${java_header}:g" \
  > "$output_xml"
