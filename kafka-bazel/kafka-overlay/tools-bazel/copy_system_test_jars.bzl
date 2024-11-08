"""Segregate the module and its dependant JARs into the respective module folder.

copy_lib_jars:
Copies the target label's output JARs into the output_directory.
It also supports renaming the JAR name to a custom name via the jar_name parameter.

copy_dependent_lib_jars:
Copies the dependant libs of the target label and its test target labels into the output directory.
It also supports include and exclude functionality for dependent JARs.
If the include_scala_version parameter is set to true, the rule will add the Scala full version to the output_directory suffix.

"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("//dependencies:dependencies.bzl", "defaultScala212Version", "defaultScala213Version")
load("@scala_multiverse//:cross_scala_config.bzl", "BASE_SCALA_VERSION")

# Set scala full version based on BASE_SCALA_VERSION
SCALA_FULL_VERSION = defaultScala212Version if BASE_SCALA_VERSION == "2.12" else defaultScala213Version

BUILD_DIR = "build/"
JAR_EXTENSTION = ".jar"

# Define the list of excluded dependency jar paths.
EXCLUDE_DEP_JAR_PATHS = [
    "bin/external/com_google_protobuf",
    "bin/external/contrib_rules_jvm_deps",
    "bin/external/io_grpc_grpc_java",
    "bin/external/flatbuffers_deps",
]

def _get_target_jar_name(jar):
    if "external/" in jar.path:
        return jar.basename.replace("processed_", "")
    return jar.short_path.replace("/", "_")

def _get_include_jars(output_jar_dict, include_target_list):
    if not include_target_list:
        return output_jar_dict
    include_jar_dict = {}
    for target in include_target_list:
        java_provider = target[JavaInfo]
        for java_output in java_provider.java_outputs:
            target_jar_name = _get_target_jar_name(java_output.class_jar)
            if target_jar_name not in include_jar_dict and target_jar_name in output_jar_dict:
                include_jar_dict[target_jar_name] = java_output.class_jar

        for jar in java_provider.transitive_runtime_jars.to_list():
            target_jar_name = _get_target_jar_name(jar)
            if target_jar_name not in include_jar_dict and target_jar_name in output_jar_dict:
                include_jar_dict[target_jar_name] = jar

    return include_jar_dict

def is_excluded_dep(libs_jar):
    for exclude_path in EXCLUDE_DEP_JAR_PATHS:
        if exclude_path in libs_jar.path:
            return True
    return False

def _get_output_jars(libs_target, include_target_list, exclude_target_list):
    if not libs_target:
        return {}

    exclude_jar_dict = {}
    output_jar_dict = {}

    for target in exclude_target_list:
        java_provider = target[JavaInfo]
        for java_output in java_provider.java_outputs:
            target_jar_name = _get_target_jar_name(java_output.class_jar)
            if target_jar_name not in exclude_jar_dict:
                exclude_jar_dict[target_jar_name] = java_output.class_jar

    libs_java_provider = libs_target[JavaInfo]

    # exclude libs jar from dependant-libs folder
    for java_output in libs_java_provider.java_outputs:
        target_jar_name = _get_target_jar_name(java_output.class_jar)
        if target_jar_name not in exclude_jar_dict:
            exclude_jar_dict[target_jar_name] = java_output.class_jar

    for libs_jar in libs_java_provider.transitive_runtime_jars.to_list():
        target_jar_name = _get_target_jar_name(libs_jar)

        if not is_excluded_dep(libs_jar) and target_jar_name not in output_jar_dict and target_jar_name not in exclude_jar_dict:
            output_jar_dict[target_jar_name] = libs_jar

    return _get_include_jars(output_jar_dict, include_target_list)

def _add_targets_without_runtime_classpath(output_jars, targets_without_runtime_classpath):
    for target in targets_without_runtime_classpath:
        java_provider = target[JavaInfo]
        for java_output in java_provider.java_outputs:
            target_jar_name = _get_target_jar_name(java_output.class_jar)
            if target_jar_name not in output_jars:
                output_jars[target_jar_name] = java_output.class_jar

def _copy_dependant_lib_jars_impl(ctx):
    libs_target = ctx.attr.libs_target
    libs_target_include_list = ctx.attr.libs_target_include_list
    libs_target_exclude_list = ctx.attr.libs_target_exclude_list
    include_scala_version = ctx.attr.include_scala_version

    testlibs_target = ctx.attr.testlibs_target
    testlibs_target_include_list = ctx.attr.testlibs_target_include_list
    testlibs_target_exclude_list = ctx.attr.testlibs_target_exclude_list

    targets_without_runtime_classpath = ctx.attr.targets_without_runtime_classpath

    if include_scala_version:
        output_deps_dir = "{build_dir}{output_directory}-{scala_version}".format(build_dir = BUILD_DIR, output_directory = ctx.attr.output_directory, scala_version = SCALA_FULL_VERSION)
    else:
        output_deps_dir = "{build_dir}{output_directory}".format(build_dir = BUILD_DIR, output_directory = ctx.attr.output_directory)
    output = ctx.actions.declare_directory(output_deps_dir)

    # get the dependant libs of target label
    libs_output_jars = _get_output_jars(libs_target, libs_target_include_list, libs_target_exclude_list)
    testlibs_output_jars = {}

    # get the dependant libs of test target labels
    for target in testlibs_target:
        testlibs_output_jars = _get_output_jars(target, testlibs_target_include_list, testlibs_target_exclude_list)

    # merge libs and test-libs dependant JARs dict.
    libs_output_jars.update(testlibs_output_jars)

    # add targets without runtime classpath to the final output jar dict
    _add_targets_without_runtime_classpath(libs_output_jars, targets_without_runtime_classpath)

    unique_jars = list(libs_output_jars.values())
    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    cmds = ["mkdir -p {dirname};".format(dirname = output.path)] + ["cp {src} {dest}".format(src = jar.path, dest = output.path + "/" + _get_target_jar_name(jar)) for jar in unique_jars]
    cmds_str = "\n".join(cmds)
    ctx.actions.write(output = script, content = cmds_str, is_executable = True)

    ctx.actions.run(
        executable = script,
        inputs = [script] + unique_jars,
        outputs = [output],
    )

    return [
        DefaultInfo(
            files = depset([output]),
        ),
    ]

copy_dependant_lib_jars = rule(
    implementation = _copy_dependant_lib_jars_impl,
    attrs = {
        "include_scala_version": attr.bool(
            mandatory = False,
            doc = "If True, adds the full Scala version as a suffix to the output directory.",
        ),
        "libs_target": attr.label(
            mandatory = False,
            doc = "module's target label",
        ),
        "libs_target_include_list": attr.label_list(
            mandatory = False,
            doc = "List of targets that need to be included in the output directory; by default, it includes all dependent JARs of libs target",
        ),
        "libs_target_exclude_list": attr.label_list(
            mandatory = False,
            doc = "list of targets need to be excluded from output_directory folder, which are dependant of libs target",
        ),
        "testlibs_target": attr.label_list(
            mandatory = False,
            doc = "module's test targets list",
        ),
        "testlibs_target_include_list": attr.label_list(
            mandatory = False,
            doc = "List of targets that need to be included in the output directory; by default, it includes all dependent JARs of test libs target",
        ),
        "testlibs_target_exclude_list": attr.label_list(
            mandatory = False,
            doc = "list of targets need to be excluded from output_directory folder, which are dependant of testlibs target",
        ),
        "targets_without_runtime_classpath": attr.label_list(
            mandatory = False,
            doc = "list of target labels, whose only output JARs included in output_directory.(Note: exclude won't apply to these JARs)",
        ),
        "output_directory": attr.string(
            mandatory = False,
            doc = "output directory to which all the dependant libs will be copied",
            default = "dependant-libs",
        ),
    },
)

def _add_libs_jars(target, jar_name, version, test_suffix, output_jars):
    if target:
        target_files = target.files.to_list()
        if not target_files:
            print("Target {} has no files in its output.".format(target))
            return
        if len(target_files) > 1:
            print("WARNING: Target {} has more than one file in its output, using the first one.".format(target))
        libs_file = target_files[0]
        if libs_file not in output_jars:
            output_jars[libs_file] = "{file_name}-{version}{suffix}{extension}".format(file_name = jar_name, version = version, suffix = test_suffix, extension = JAR_EXTENSTION) if jar_name else libs_file.basename

def _copy_lib_jars_impl(ctx):
    MAVEN_VERSION = ctx.var.get("maven_version", "unknown")
    jar_name = ctx.attr.jar_name
    libs_target = ctx.attr.libs_target
    jar_suffix = ctx.attr.jar_suffix

    # e.g. build/libs
    output_dir = "{build_dir}{output_directory}".format(build_dir = BUILD_DIR, output_directory = ctx.attr.output_directory)

    output = ctx.actions.declare_directory(output_dir)

    output_jars = {}

    # adds libs jar to the output_jars dict
    _add_libs_jars(libs_target, jar_name, MAVEN_VERSION, jar_suffix, output_jars)

    output_jars_list = list(output_jars.keys())
    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    cmds = ["mkdir -p {dirname};".format(dirname = output.path)] + ["cp {src} {dest}".format(src = jar.path, dest = output.path + "/" + output_jars[jar]) for jar in output_jars]
    cmds_str = "\n".join(cmds)
    ctx.actions.write(output = script, content = cmds_str, is_executable = True)

    ctx.actions.run(
        executable = script,
        inputs = [script] + output_jars_list,
        outputs = [output],
    )

    return [
        DefaultInfo(
            files = depset([output]),
        ),
    ]

copy_lib_jars = rule(
    implementation = _copy_lib_jars_impl,
    attrs = {
        "jar_name": attr.string(
            mandatory = False,
            doc = "output jar name. if not mentioned, same name as source will be used",
        ),
        "jar_suffix": attr.string(
            mandatory = False,
            doc = "suffix name to be added to the output jar name.",
            default = "",
        ),
        "libs_target": attr.label(
            mandatory = False,
            doc = "module's target label",
        ),
        "output_directory": attr.string(
            mandatory = False,
            doc = "output directory to which the output JARs will be copied",
            default = "libs",
        ),
    },
)

def conditional_copy_dep_jars(name, **kwargs):
    native.alias(
        name = name,
        actual = select({
            "//:copy_jars": name + "-impl",
            "//conditions:default": ":empty",
        }),
    )

    copy_dependant_lib_jars(
        name = name + "-impl",
        tags = ["manual"],
        **kwargs
    )

    if native.existing_rule("empty") == None:
        native.sh_library(
            name = "empty",
            srcs = [],
        )

def conditional_copy_lib_jars(name, **kwargs):
    native.alias(
        name = name,
        actual = select({
            "//:copy_jars": name + "-impl",
            "//conditions:default": ":empty",
        }),
    )

    copy_lib_jars(
        name = name + "-impl",
        tags = ["manual"],
        **kwargs
    )

    if native.existing_rule("empty") == None:
        native.sh_library(
            name = "empty",
            srcs = [],
        )
