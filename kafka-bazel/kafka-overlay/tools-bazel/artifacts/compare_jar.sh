#!/bin/bash
set -e

left_jar=$1
right_jar=$2
left_dir=$3
right_dir=$4
diff_name=$5

left_name=$(basename "$left_dir")
right_name=$(basename "$right_dir")

echo "Comparing $left_jar and $right_jar"
echo "Output will be written to $diff_name"
echo "Extracting jars to $left_dir and $right_dir"

rm -fr "$left_dir" "$right_dir"
unzip -q "$left_jar" -d "$left_dir"
unzip -q "$right_jar" -d "$right_dir"

# Gradle includes empty directories in the jar, but Bazel does not. This causes diff noise.
find "$left_dir" -type d -empty -delete
find "$right_dir" -type d -empty -delete

# Bazel includes a build-data.properties file in some jars, which causes diff noise.
rm -f "$left_dir"/build-data.properties

# If the name contains 'javadoc', remove the meta-inf directory to reduce diff noise.
if [[ "$left_jar" == *"-docs"* ]]; then
  rm -rf "$left_dir/META-INF"
  rm -rf "$right_dir/META-INF"

  # Remove the following lines from every html file to reduce diff noise.
  # I'm not sure what causes these differences, but it seems to just be the default aria-labelledby value is different
  # and is not that important. It could be a slight difference in the javadoc tool used to generate the docs between
  # the two systems.
  find . -name "*.html" -type f -exec sed -i'.bak' '/<div id="method-summary-table.tabpanel" role="tabpanel">/d' {} \;
  find . -name "*.html" -type f -exec sed -i'.bak' '/<div id="method-summary-table.tabpanel" role="tabpanel" aria-labelledby="method-summary-table-tab0">/d' {} \;

  find . -name "*.html" -type f -exec sed -i'.bak' '/<div class="summary-table three-column-summary">/d' {} \;
  find . -name "*.html" -type f -exec sed -i'.bak' '/<div class="summary-table three-column-summary" aria-labelledby="method-summary-table-tab0">/d' {} \;

  find . -name "*.html" -type f -exec sed -i'.bak' '/<div id="all-classes-table.tabpanel" role="tabpanel">/d' {} \;
  find . -name "*.html" -type f -exec sed -i'.bak' '/<div id="all-classes-table.tabpanel" role="tabpanel" aria-labelledby="all-classes-table-tab0">/d' {} \;

  find . -name "*.html" -type f -exec sed -i'.bak' '/<div class="summary-table two-column-summary">/d' {} \;
  find . -name "*.html" -type f -exec sed -i'.bak' '/<div class="summary-table two-column-summary" aria-labelledby="class-summary-tab0">/d' {} \;
  find . -name "*.html" -type f -exec sed -i'.bak' '/<div class="summary-table two-column-summary" aria-labelledby="all-classes-table-tab0">/d' {} \;

  find . -name "*.html" -type f -exec sed -i'.bak' '/<div id="class-summary.tabpanel" role="tabpanel">/d' {} \;
  find . -name "*.html" -type f -exec sed -i'.bak' '/<div id="class-summary.tabpanel" role="tabpanel" aria-labelledby="class-summary-tab0">/d' {} \;

  find . -name "*.js" -type f -exec sed -i'.bak' "/document.getElementById(tableId + '.tabpanel')/d" {} \;
  find . -name "*.js" -type f -exec sed -i'.bak' "/document.querySelector('div#' + tableId +' .summary-table')/d" {} \;


  find . -name '*.bak' -exec rm {} \;
fi

echo -e '### File paths contained in only one jar ###' > "$diff_name"
echo -e "### $right_name is indented. $left_name is left justified. ###\n" >> "$diff_name"
comm -3 <(cd "$left_dir"; find . | sort) <(cd "$right_dir"; find . | sort) >> "$diff_name"

echo -e '\n### File diff ###' >> "$diff_name"
echo -e '### excluding class files ###' >> "$diff_name"
echo -e '### does not show missing files inside missing directories) ###\n' >> "$diff_name"

if [ -f "$left_dir/META-INF/MANIFEST.MF" ]; then
  # These get added by Bazel and cause additional noise
  sed -i'.bak' '/Created-By: mergejars/d' "$left_dir/META-INF/MANIFEST.MF"
  sed -i'.bak' '/Created-By: singlejar/d' "$left_dir/META-INF/MANIFEST.MF"
  sed -i'.bak' '/Created-By: bazel/d' "$left_dir/META-INF/MANIFEST.MF"
  sed -i'.bak' '/Injecting-Rule-Kind: java_proto_library/d' "$left_dir/META-INF/MANIFEST.MF"
  sed -i'.bak' '/Class-Path: /d' "$left_dir/META-INF/MANIFEST.MF"
  sed -i'.bak' '/Target-Label: /d' "$left_dir/META-INF/MANIFEST.MF"
  sed -i'.bak' '/Multi-Release: true/d' "$left_dir/META-INF/MANIFEST.MF"
  sed -i'.bak' '/Main-Class: none/d' "$left_dir/META-INF/MANIFEST.MF"

  # https://(broken link)
  if [[ "$left_jar" == *"core"* ]]; then
    sed -i'.bak' '/^Version: /d' "$right_dir/META-INF/MANIFEST.MF"
    rm "$right_dir/META-INF/MANIFEST.MF.bak"
  fi

  rm "$left_dir/META-INF/MANIFEST.MF.bak"
fi

# Ensure that META-INF/services and kafka-version files end with 1 newline to reduce diff noise.
for file in "$left_dir/META-INF/services"/* "$right_dir/META-INF/services"/* "$left_dir/kafka"/* "$right_dir/kafka"/*; do
  if [ -f "$file" ]; then
    awk '/^$/ {n=n "\n";next;} {printf "%s",n; n=""; print;}' "$file" > temp_file && mv temp_file "$file"
    if [ -n "$(tail -c 1 "$file")" ]; then
      printf '\n' >> "$file"
    fi
  fi
done

diff -r -u --exclude="*.class" "$left_dir" "$right_dir" >> "$diff_name" || true

# The unified diff output includes timestamps, which causes non-deterministic diffs.
# This removes the timestamps from those lines (e.g. --- 2024-01-01 00:00:00.000000000 +0000)
sed -i'.bak' -e '/^---/ s/\t.*//' -e '/^\+\+\+/ s/\t.*//' "$diff_name"

# Uncomment these lines to compare disassembled class files
# echo -e "\n### File diff (Using disassembled class file data) ###\n" >> "$diff_name"
# find "$left_dir" -name '*.class' -exec javap -c -v {} \; > "$left_dir"/disassembled
# find "$right_dir" -name '*.class' -exec javap -c -v {} \; > "$right_dir"/disassembled
# diff -r -u "$left_dir"/disassembled "$right_dir"/disassembled >> "$diff_name" || true
