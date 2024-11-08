"""package jars with runtime classpath"""

def _should_exclude_jar(jar, prefix_excludes):
    for exclude in prefix_excludes:
        if jar.startswith(exclude):
            return True

    return False

def _get_target_jar_name(jar):
    if "external/" in jar.path:
        return jar.basename.replace("processed_", "")
    return jar.short_path.replace("/", "_")

# This is copied from rules_jvm_external to ensure that the tools jars don't leak
# into the final tar.
# https://github.com/bazelbuild/rules_jvm_external/blob/master/private/rules/maven_project_jar.bzl#L13-L32
def _strip_excluded_workspace_jars(jar_files, excluded_workspaces):
    to_return = []

    for jar in jar_files:
        owner = jar.owner

        if owner:
            workspace_name = owner.workspace_name

            # bzlmod module names use ~ as a separator
            if "~" in workspace_name:
                idx = workspace_name.index("~")
                workspace_name = workspace_name[0:idx]  # ~ exclusive

            if workspace_name in excluded_workspaces:
                continue

        to_return.append(jar)

    return to_return

def _pkg_java_library_impl(ctx):
    targets_with_runtime_classpath = ctx.attr.targets_with_runtime_classpath
    targets_without_runtime_classpath = ctx.attr.targets_without_runtime_classpath
    excludes = ctx.attr.excludes
    subdir_mapping = ctx.attr.subdir_mapping
    output_jars = []

    for target in targets_without_runtime_classpath:
        java_provider = target[JavaInfo]
        for java_output in java_provider.java_outputs:
            output_jars.append(java_output.class_jar)

    for target in targets_with_runtime_classpath:
        java_provider = target[JavaInfo]
        for java_output in java_provider.java_outputs:
            output_jars.append(java_output.class_jar)

            for jar in java_provider.transitive_runtime_jars.to_list():
                output_jars.append(jar)

    output_jars_dict = {}
    for jar in output_jars:
        target_jar_name = _get_target_jar_name(jar)
        if target_jar_name not in output_jars_dict:
            output_jars_dict[target_jar_name] = jar
    unique_jars = list(output_jars_dict.values())

    output = ctx.actions.declare_directory(ctx.attr.output_directory)
    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    cmds = ["#!/usr/bin/env bash", "mkdir -p {dirname};".format(dirname = output.path)]

    unique_jars = _strip_excluded_workspace_jars(unique_jars, ctx.attr.excluded_workspaces)

    for jar in unique_jars:
        subdirs = []
        target_jar_name = _get_target_jar_name(jar)
        if _should_exclude_jar(target_jar_name, excludes):
            continue

        for subdir_key, prefixes in subdir_mapping.items():
            for prefix in prefixes:
                if target_jar_name.startswith(prefix):
                    subdirs.append(subdir_key)

        if not subdirs:
            subdirs.append("")

        for subdir in subdirs:
            dest_dir = output.path + "/" + subdir if subdir else output.path
            cmds.append("mkdir -p {dest_dir}".format(dest_dir = dest_dir))
            cmds.append("cp {src} {dest}".format(src = jar.path, dest = dest_dir + "/" + target_jar_name))

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

pkg_java_library = rule(
    implementation = _pkg_java_library_impl,
    attrs = {
        "excluded_workspaces": attr.string_list(
            mandatory = False,
            default = [],
            doc = "workspaces to exclude",
        ),
        "excludes": attr.string_list(
            mandatory = False,
            doc = "runtime deps that need to be excluded",
        ),
        "output_directory": attr.string(
            mandatory = True,
            doc = "output directory of all runtime deps",
        ),
        "subdir_mapping": attr.string_list_dict(
            mandatory = False,
            default = {},
            doc = "mapping from subdir to list of jar name prefixes",
        ),
        "targets_with_runtime_classpath": attr.label_list(
            mandatory = False,
            doc = "target that we need both its production jar and runtime deps",
        ),
        "targets_without_runtime_classpath": attr.label_list(
            mandatory = False,
            doc = "target that we don't want its runtime deps",
        ),
    },
)