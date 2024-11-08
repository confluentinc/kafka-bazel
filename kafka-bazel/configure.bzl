"""Helper macros to configure the Kafka overlay project."""

# Directory of overlay files relative to WORKSPACE
DEFAULT_OVERLAY_PATH = "kafka-overlay"

def _is_absolute(path):
    """Returns `True` if `path` is an absolute path.

    Args:
      path: A path (which is a string).
    Returns:
      `True` if `path` is an absolute path.
    """
    return path.startswith("/") or (len(path) > 2 and path[1] == ":")

def _join_path(a, b):
    if _is_absolute(b):
        return b
    return str(a) + "/" + str(b)

def _overlay_directories(repository_ctx):
    # src_workspace is the workspace that contains the source files
    # for the overlay. Could be a label //:WORKSPACE with src_path being
    # relative path or could be a remote http_archive repo such as:
    # "@kafka-raw//:WORKSPACE"
    src_workspace_path = repository_ctx.path(
        repository_ctx.attr.src_workspace,
    ).dirname

    # join the path with the src_workspace_path to get the source path
    src_path = _join_path(src_workspace_path, repository_ctx.attr.src_path)

    # Do the same now for the overlay_workspace and path
    overlay_workspace_path = repository_ctx.path(
        repository_ctx.attr.overlay_workspace,
    ).dirname
    overlay_path = _join_path(
        overlay_workspace_path,
        repository_ctx.attr.overlay_path,
    )

    overlay_script = repository_ctx.path(
        repository_ctx.attr._overlay_script,
    )

    # Rather than add a dependency on Python rules, we just find the python3
    python_bin = repository_ctx.which("python3")
    if not python_bin:
        # Windows typically just defines "python" as python3. The script itself
        # contains a check to ensure python3.
        python_bin = repository_ctx.which("python")

    if not python_bin:
        fail("Failed to find python3 binary")

    # rather than '.' we could do
    # repository_path = str(repository_ctx.path(""))
    cmd = [
        python_bin,
        overlay_script,
        "--src",
        src_path,
        "--overlay",
        overlay_path,
        "--target",
        '.',
    ]
    exec_result = repository_ctx.execute(cmd, timeout = 20)

    if exec_result.return_code != 0:
        fail(("Failed to execute overlay script: '{cmd}'\n" +
              "Exited with code {return_code}\n" +
              "stdout:\n{stdout}\n" +
              "stderr:\n{stderr}\n").format(
            cmd = " ".join([str(arg) for arg in cmd]),
            return_code = exec_result.return_code,
            stdout = exec_result.stdout,
            stderr = exec_result.stderr,
        ))

def _kafka_configure_impl(repository_ctx):
    _overlay_directories(repository_ctx)

    # Do other stuff here if needed
    pass

kafka_configure = repository_rule(
    implementation = _kafka_configure_impl,
    # If the configure flag is set, the repository is only re-fetched on `bazel fetch`
    # when the --configure parameter is passed to it (if the attribute is unset, this command will not cause a re-fetch)
    configure = True,
    # If the local flag is set, in addition to the above cases, the repo is also re-fetched when the Bazel server restarts.
    local = True,
    attrs = {
        "_overlay_script": attr.label(
            default = Label("//:overlay_directories.py"),
            allow_single_file = True,
        ),
        "overlay_workspace": attr.label(default = Label("//:WORKSPACE")),
        "overlay_path": attr.string(default = DEFAULT_OVERLAY_PATH),
        "src_workspace": attr.label(default = Label("//:WORKSPACE")),
        "src_path": attr.string(mandatory = True),
    },
)