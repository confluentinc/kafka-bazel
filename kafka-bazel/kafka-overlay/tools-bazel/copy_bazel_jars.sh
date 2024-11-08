#!/bin/bash

# This script helps in copying the bazel package JARs and it's dependant JARs from bazel environment to the respective package folder.

bazel_dir="bazel-bin"
build_regex="/BUILD.bazel"
bazel_build_dir="build"

bazel_libs_dir="${bazel_build_dir}/libs"
bazel_dep_libs_dir="${bazel_build_dir}/dependant-libs"
bazel_dep_testlibs_dir="${bazel_build_dir}/dependant-testlibs"

# fetch all the directories which contains BUILD.bazel file
for file in $(find . -name BUILD.bazel);
do
  module_folder=${file%${build_regex}} # get the package folder path
  if [ -d "${bazel_dir}/${module_folder}/${bazel_build_dir}" ] ; then
    if [ -d "${bazel_dir}/${module_folder}/${bazel_libs_dir}" ] ; then
      mkdir -p "${module_folder}/${bazel_libs_dir}"
      # copy package JARs into build/libs folder
      cp ${bazel_dir}/${module_folder}/${bazel_libs_dir}/*.jar ${module_folder}/${bazel_libs_dir}
    fi
    if [ -d "${bazel_dir}/${module_folder}/${bazel_build_dir}/testlibs" ] ; then
      mkdir -p "${module_folder}/${bazel_libs_dir}"
      # copy package test JARs into build/libs folder
      cp ${bazel_dir}/${module_folder}/${bazel_build_dir}/testlibs/*.jar ${module_folder}/${bazel_libs_dir}
    fi
    if [ -d "${bazel_dir}/${module_folder}/${bazel_build_dir}/testlibs-scala" ] ; then
      mkdir -p "${module_folder}/${bazel_libs_dir}"
      # copy package scala test JARs into build/libs folder
      cp ${bazel_dir}/${module_folder}/${bazel_build_dir}/testlibs-scala/*.jar ${module_folder}/${bazel_libs_dir}
    fi

    # copy dependant-libs and dependant-libs-{scala_version} folder to build folder
    for dir in ${bazel_dir}/${module_folder}/${bazel_dep_libs_dir}*;
    do
      if [ -d $dir ];then
        cp -R $dir ${module_folder}/${bazel_build_dir}
      fi
    done
  fi
done

# copy core module's test dependant JARs
if [ -d "${bazel_dir}/core/${bazel_dep_testlibs_dir}" ] ; then
  mkdir -p core/${bazel_dep_testlibs_dir}
  cp ${bazel_dir}/core/${bazel_dep_testlibs_dir}/*.jar core/${bazel_dep_testlibs_dir}
fi

# copy kafka-stream-version properties file
mkdir -p streams/${bazel_build_dir}/kafka
cp -f "${bazel_dir}/kafka/kafka-streams-version.properties" "streams/${bazel_build_dir}/kafka/kafka-streams-version.properties"

# copy kafka-version.properties file to the below modules build/kafka folder
version_dep_modules='clients tools/tools-api server-common server storage storage/api raft'
for module in $version_dep_modules; do
  mkdir "${module}/${bazel_build_dir}/kafka"
  cp -f "${bazel_dir}/kafka/kafka-version.properties" "${module}/${bazel_build_dir}/kafka/kafka-version.properties"
done
