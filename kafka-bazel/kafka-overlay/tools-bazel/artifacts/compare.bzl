load("@aspect_bazel_lib//lib:yq.bzl", "yq")

def _validate_name(name):
    if not name.isalpha():
        fail("Invalid name '%s'. Name should only contain alphanumeric characters." % name)

def _compare_jar_impl(ctx):
    shell_script = ctx.file._shell_script
    left_jar = ctx.file.left_jar
    right_jar = ctx.file.right_jar
    left_name = ctx.attr.left_name
    right_name = ctx.attr.right_name
    _validate_name(left_name)
    _validate_name(right_name)
    diff_name = ctx.label.name + ".diff"
    diff_file = ctx.actions.declare_file(diff_name)
    unzipped_parent_dir_name = "%s" % ctx.label.name
    left_dir = ctx.actions.declare_directory(unzipped_parent_dir_name + "/" + left_name)
    right_dir = ctx.actions.declare_directory(unzipped_parent_dir_name + "/" + right_name)

    ctx.actions.run_shell(
        command = "./%s %s %s %s %s %s" % (
            shell_script.path,
            left_jar.path,
            right_jar.path,
            left_dir.path,
            right_dir.path,
            diff_file.path,
        ),
        inputs = [left_jar, right_jar, shell_script],
        outputs = [left_dir, right_dir, diff_file],
    )
    return [
        DefaultInfo(files = depset([diff_file])),
        OutputGroupInfo(with_dirs = depset([diff_file, left_dir, right_dir])),
    ]

compare_jar = rule(
    attrs = {
        "left_jar": attr.label(
            allow_single_file = True,
            doc = "The left jar file to compare",
        ),
        "right_jar": attr.label(
            allow_single_file = True,
            doc = "The right jar file to compare",
        ),
        "left_name": attr.string(
            default = "left",
            doc = "A name for the left unzipped directory (only alphanumeric characters)",
        ),
        "right_name": attr.string(
            default = "right",
            doc = "A name for the right unzipped directory (only alphanumeric characters)",
        ),
        "_shell_script": attr.label(
            allow_single_file = True,
            default = "//tools-bazel/artifacts:compare_jar.sh",
        ),
    },
    doc = """
        Compares two jar files by unzipping them and outputting a report on the differences
          1. paths (files or directories) that are missing in either jar
          2. a recursive diff of the directories
        The first part helps identify all missing files even if they are inside missing directories.
        The second part compares file contents but stops at missing directories.
        Output group `with_dirs` also includes the unzipped directories (--output_groups=with_dirs)
        for use with other diff tools.
    """,
    implementation = _compare_jar_impl,
)

def compare_jar_test(name, left_jar, right_jar, left_name = "left", right_name = "right"):
    """
    Invokes compare_jar and adds a test that compares the output with an expected report file. Them report file must bear
    the name <name>.diff. If the file does not exist an empty report is used.

    In the event of a test failure, the test prints the differences between the report (left side) and
    the expected report (right side).
    """
    compare_jar(
        name = name,
        left_jar = left_jar,
        left_name = left_name,
        right_jar = right_jar,
        right_name = right_name,
        tags = ["manual"],
    )

    expected_report_file = native.glob([name + ".diff_expected"])
    if expected_report_file:
        expected_report_file = expected_report_file[0]
    else:
        expected_report_file = "//tools-bazel/artifacts:empty_report_jar.diff"

    native.sh_test(
        name = name + "_test",
        size = "small",
        srcs = ["//tools-bazel/artifacts:test_diff.sh"],
        args = ["$(location :" + name + ")", "$(location " + expected_report_file + ")"],
        data = [":" + name, expected_report_file],
        tags = ["compare_jar", "manual"],
    )

def _no_match_rule_impl(ctx):
    glob_pattern = ctx.attr.glob_pattern
    fail("Error: No file matched the glob pattern '{}'".format(glob_pattern))

no_match_rule = rule(
    attrs = {
        "glob_pattern": attr.string(),
    },
    doc = "A rule that fails with an error message about no file matching a specific glob pattern",
    implementation = _no_match_rule_impl,
)

def resolve_gradle_jar(glob_pattern):
    files = native.glob([glob_pattern])
    if not files:
        # Defer error until the rule is used
        rule_name = "no-match" + glob_pattern.replace("*", "")
        no_match_rule(
            name = rule_name,
            glob_pattern = glob_pattern,
            tags = ["manual"],
        )
        return ":" + rule_name
    else:
        return files[0]

def compare_gradle_jar_test(
        name,
        bazel_jar,
        gradle_jar_pattern,
        test_jar,
        compare_javadoc_jar = True,
        compare_source_jar = True,
        alternative_bazel_jar_target = None):
    compare_jar_test(
        name = name,
        left_jar = bazel_jar,
        left_name = "bazel",
        right_jar = resolve_gradle_jar(gradle_jar_pattern),
        right_name = "gradle",
    )

    if alternative_bazel_jar_target:
        bazel_jar = alternative_bazel_jar_target

    if test_jar:
        compare_jar_test(
            name = name + "-test",
            left_jar = test_jar,
            left_name = "bazel",
            right_jar = resolve_gradle_jar(gradle_jar_pattern.replace(".jar", "-test.jar")),
            right_name = "gradle",
        )

    if compare_javadoc_jar:
        compare_jar_test(
            name = name + "-docs",
            left_jar = bazel_jar + "-docs",
            left_name = "bazel",
            right_jar = resolve_gradle_jar(gradle_jar_pattern.replace(".jar", "-javadoc.jar")),
            right_name = "gradle",
        )

    if compare_source_jar:
        compare_jar_test(
            name = name + "-maven-source",
            left_jar = bazel_jar,
            left_name = "bazel",
            right_jar = resolve_gradle_jar(gradle_jar_pattern.replace(".jar", "-sources.jar")),
            right_name = "gradle",
        )

def _compare_file_impl(ctx):
    left_file = ctx.file.left_file
    right_file = ctx.file.right_file
    diff_name = ctx.label.name + ".diff"
    diff_file = ctx.actions.declare_file(diff_name)

    ctx.actions.run_shell(
        command = "diff -u %s %s > %s || true" % (
            left_file.path,
            right_file.path,
            diff_file.path,
        ),
        inputs = [left_file, right_file],
        outputs = [diff_file],
    )
    return [
        DefaultInfo(files = depset([diff_file])),
    ]

compare_file = rule(
    attrs = {
        "left_file": attr.label(
            allow_single_file = True,
            doc = "The left file to compare",
        ),
        "right_file": attr.label(
            allow_single_file = True,
            doc = "The right file to compare",
        ),
    },
    doc = """
        Compares two files with diff and outputs a report on the differences.
    """,
    implementation = _compare_file_impl,
)

def compare_file_test(name, left_file, right_file):
    compare_file(
        name = name,
        left_file = left_file,
        right_file = right_file,
        tags = ["manual"],
    )

    expected_report_file = native.glob([name + ".diff_expected"])
    if expected_report_file:
        expected_report_file = expected_report_file[0]
    else:
        expected_report_file = "//tools-bazel/artifacts:empty_report_file.diff"

    native.sh_test(
        name = name + "_test",
        size = "small",
        srcs = ["//tools-bazel/artifacts:test_diff.sh"],
        args = ["$(location :" + name + ")", "$(location " + expected_report_file + ")"],
        data = [":" + name, expected_report_file],
        tags = ["compare_file", "manual"],
    )

def compare_gradle_pom_test(name, bazel_pom, gradle_pom):
    _process_xml(name + "_yq_gradle", gradle_pom)
    _process_xml(name + "_yq_bazel", bazel_pom)

    compare_file_test(
        name = name,
        left_file = ":" + name + "_yq_bazel.xml",
        right_file = ":" + name + "_yq_gradle.xml",
    )

def create_compare_tests(
        name,
        gradle_jar_pattern,
        gradle_pom,
        compare_javadoc_jar,
        compare_source_jar,
        test_jar):
    compare_gradle_jar_test(
        name = name + "-compare-jar",
        bazel_jar = name,
        gradle_jar_pattern = gradle_jar_pattern,
        compare_javadoc_jar = compare_javadoc_jar,
        compare_source_jar = compare_source_jar,
        test_jar = test_jar,
    )

    compare_gradle_pom_test(
        name = name + "-compare-pom",
        bazel_pom = name + "-pom",
        gradle_pom = gradle_pom,
    )

def _process_xml(name, pom):
    # Once we have reconciled the set of dependencies, we could stop sorting them and reconcile their order
    # sorts dependencies by artifactId
    # sorts exclusions by artifactId
    # removes the scope attribute from compile dependencies because compile is the default scope
    # removes comments
    # sorts the attributes of the xml elements
    yq_expression = (
        " (.project.dependencies |= (select(.dependency|has(0)).dependency |= sort_by(.artifactId)))" +
        " | (.project.dependencies.dependency[] |= (select(.exclusions.exclusion|has(0)).exclusions.exclusion |= sort_by(.artifactId)))" +
        " | (.project.dependencies.dependency[] |= (select(.scope == \"compile\") | del(.scope)))" +
        ' | ... comments=""' +
        " | sort_keys(..)"
    )

    yq(
        name = name,
        srcs = [pom],
        outs = [name + ".xml"],
        args = ["-p=xml"],
        expression = yq_expression,
        tags = ["manual"],
    )
