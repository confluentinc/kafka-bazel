"""jvm test suite for junit5"""

load("//rules/jvm/private:_junit_utils.bzl", "get_class_name", "get_cpu_n_tag", "get_test_files", "is_integration")
# FIXME(fzakaria): Does not include checkstyle or spotbugs
load("@io_bazel_rules_scala//scala:scala.bzl", "scala_library")
load("@contrib_rules_jvm//java:defs.bzl", "java_junit5_test")
load("@rules_java//java:defs.bzl", "java_library")

# This auto-generates a test suite based on the passed set of targets
# we will add a root test_suite with the name of the passed name
def jvm_junit_test_suite(
        name,
        srcs = [],
        test_suffixes = ["Test.java", "Test.scala"],
        additional_library_srcs = [],
        test_suffixes_excludes = [],
        test_prefixes_excludes = [],
        visibility = None,
        tags = [],
        per_test_args = {},
        runtime_deps = [],
        deps = [],
        cpu_tag = "cpu:2",
        prefixes = ["src/test/java/"],
        size = "medium",
        **kwargs):
    """generate a set of junit5 tests target per test file

    Args:
        name (string): name
        srcs (list): list of source files. Defaults to [].
        additional_library_srcs (list): list of files that should also be included in the "-lib" library.
        These could be files that would normally be sorted only into the "tests" category, but are also
        dependencies for other tests. Defaults to [].
        test_suffixes: A list of suffixes (eg. `["Test.java", "Test.scala"]`)
        test_suffixes_excludes: A list of suffix excludes (eg. `["BaseTest.java", "BaseTest.scala"]`)
        test_prefixes_excludes (list): A list of prefixes to exclude (eg. `["Abstract"]`)
        visibility (list): Defaults to None.
        tags (list): Defaults to [].
        per_test_args (dict): A dict with test file path as the key and tags (list), shard_count (str), and size (str)
        for the value. The values in the dict will overwrite the default values.
        runtime_deps (list): Defaults to [].
        deps (list): Defaults to [].
        cpu_tag: The default number of CPUs to allocate to a test. Can be overwritten by `per_test_args` with a tag of `cpu:{value}`.
        Only applies to tests that are classified as 'Integration Tests' via `is_integration`.
        prefixes (list): Defaults to ["src/test/java/"].
        size (str): Defaults to "medium". Can be overwritten by `per_test_args` with `size = {value}` in the `dict`.
        **kwargs: other args.
    """
    ts = []
    test_srcs, nontest_srcs = get_test_files(
        srcs = srcs,
        test_suffixes = test_suffixes,
        test_suffixes_excludes = test_suffixes_excludes,
        test_prefixes_excludes = test_prefixes_excludes,
        additional_library_srcs = additional_library_srcs,
    )
    if nontest_srcs:
        lib_dep_name = "%s-test-lib" % name
        lib_dep_label = ":%s" % lib_dep_name

        has_scala_files = False
        for src in nontest_srcs:
            if src.endswith(".scala"):
                has_scala_files = True
                break

        if has_scala_files:
            scala_library(
                name = lib_dep_name,
                srcs = nontest_srcs,
                visibility = visibility,
                unused_dependency_checker_mode = "off",
                tags = tags,
                deps = deps,
                **kwargs
            )
        else:
            kwargs_java = dict(kwargs)
            kwargs_java.pop("java_compile_toolchain", None)
            java_library(
                name = lib_dep_name,
                srcs = nontest_srcs,
                visibility = visibility,
                tags = tags,
                deps = deps,
                **kwargs_java
            )
        deps = deps + [lib_dep_label]

    for test_file in test_srcs:
        test_args = per_test_args.get(test_file, {})
        final_tags = tags + test_args.get("tags", [])
        jvm_flags = test_args.get("jvm_flags", []) + kwargs.get("jvm_flags", [])
        is_java_test = test_file.endswith(".java")
        is_scala_test = test_file.endswith(".scala")
        is_integration_test = is_integration(test_file, final_tags)
        cpu_n = get_cpu_n_tag(final_tags)
        suffix = test_file.rfind(".")
        test_name = test_file[:suffix]

        if is_integration_test:
            if "integration" not in final_tags:
                final_tags.append("integration")

            if not cpu_n:
                final_tags.append(cpu_tag)

        test_kwargs = dict(kwargs)
        test_kwargs.pop("jvm_flags", None)
        test_kwargs.pop("java_compile_toolchain", None)

        shard_count = test_args.get("shard_count")
        if shard_count:
            test_kwargs["shard_count"] = shard_count

        test_size = test_args.get("size", size)
        class_name = get_class_name(test_file, prefixes)

        if is_scala_test:
            # Would be nice to get around creating so many scala libraries, like we do for java, but it may not be possible.
            scala_lib_name = "%s_lib" % test_name
            scala_library(
                name = scala_lib_name,
                srcs = [test_file],
                visibility = visibility,
                unused_dependency_checker_mode = "off",
                tags = tags,
                deps = deps,
                testonly = True,
                **kwargs
            )

            java_junit5_test(
                name = test_name,
                test_class = class_name,
                visibility = visibility,
                tags = final_tags,
                runtime_deps = runtime_deps + deps + [scala_lib_name],
                size = test_size,
                jvm_flags = jvm_flags,
                **test_kwargs
            )

            ts.append(test_name)

        if is_java_test:
            java_junit5_test(
                name = test_name,
                srcs = [test_file],
                test_class = class_name,
                visibility = visibility,
                tags = final_tags,
                runtime_deps = runtime_deps,
                deps = deps,
                size = test_size,
                jvm_flags = jvm_flags,
                **test_kwargs
            )

            ts.append(test_name)
    native.test_suite(name = name, tests = ts, visibility = visibility, tags = tags)