load("@aspect_bazel_lib//lib:stamping.bzl", "STAMP_ATTRS", "maybe_stamp")

script = """
#!/bin/bash
cat <<EOF > $3
commitId=$(cat $1 | grep STABLE_GIT_COMMIT | awk '{print $2}' | cut -c 1-16)
version=$2
EOF
"""

def _impl(ctx):
    """
    Writes a file (in properties format) with the commitId and version of the current build.
    The version comes from the maven_version variable which is set in bazelrc.
    The commitId comes from the stamping script (bazel_stamp_vars.sh).

    "unknown" is used for both properties unless `--config=release` is used with the build.
    `--config=release` should only be used with `bazel build` and not `bazel test` because the stamped files
    will bust much of the cache and is unnecessary for tests.
    """
    stamp = maybe_stamp(ctx)

    if stamp:
        version = ctx.var.get("maven_version", "unknown")
        ctx.actions.run_shell(
            inputs = [stamp.volatile_status_file, stamp.stable_status_file],
            arguments = [stamp.stable_status_file.path, version, ctx.outputs.out.path],
            outputs = [ctx.outputs.out],
            command = script,
        )
    else:
        ctx.actions.write(
            output = ctx.outputs.out,
            content = "commitId=unknown\nversion=unknown\n",
        )

write_version_file = rule(
    implementation = _impl,
    attrs = dict({"out": attr.output()}, **STAMP_ATTRS),
)
