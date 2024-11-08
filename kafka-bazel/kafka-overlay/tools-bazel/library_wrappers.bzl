load("//rules/jvm:jvm_junit_test_suite.bzl", internal_jvm_junit_test_suite = "jvm_junit_test_suite")
load("@io_bazel_rules_scala//scala:scala.bzl", oss_scala_library = "scala_library")
load("@contrib_rules_jvm//java:defs.bzl", oss_java_export = "java_export", oss_java_library = "java_library")
load("@rules_java//java:defs.bzl", "java_proto_library")
load("@rules_jvm_external//:defs.bzl", oss_maven_export = "maven_export")
load("@rules_proto//proto:defs.bzl", "proto_library")
load("//dependencies:dependencies.bzl", "libs")
load("//tools-bazel:copy_system_test_jars.bzl", "conditional_copy_lib_jars")
load("//tools-bazel/artifacts:compare.bzl", "compare_gradle_jar_test", "compare_gradle_pom_test", "create_compare_tests")

jar_pkg_excluded_workspaces = {
    "protobuf": None,
    "com_google_protobuf": None,
    "io_grpc_grpc_java": None,
    "flatbuffers_deps": None,
    "contrib_rules_jvm_deps": None,
    "com_google_api_grpc_proto_google_common_protos": None,
}

excluded_workspaces = jar_pkg_excluded_workspaces | {
    "io_bazel_rules_scala_scala_library": None,
    "io_bazel_rules_scala_scala_reflect": None,
    "io_bazel_rules_scala_scala_reflect_2_13_14": None,
    "io_bazel_rules_scala_scala_reflect_2_12_18": None,
}

_javadocopts = [
    "-notimestamp",
    "-quiet",
    "-Xdoclint:none",
    "-encoding",
    "UTF8",
    "--show-members",
    "public",
    "-public",
    "-charset",
    "UTF-8",
]

def _get_javadocopts(title_name):
    window_title = title_name + " $(maven_version)" + " API"
    doctitle = title_name + " $(maven_version)" + " API"
    return _javadocopts + ["-doctitle", doctitle, "-windowtitle", window_title]

def _convert_dep_to_neverlink(dep):
    # Ensure dep contains a target name
    label = native.package_relative_label(dep)
    dep = str(label)

    #TODO: See how to handle fbs dependencies
    if label.name.count("_fbs") > 0:
        return dep

    if label.name.count("_proto") > 0:
        return dep

    if label.name.count("_grpc") > 0:
        return dep

    #TODO: See how to handle io_bazel_rules_scala_scala_library
    if label.workspace_name in ["io_bazel_rules_scala_scala_library", "io_bazel_rules_scala_scala_reflect"]:
        return dep

    #TODO: For consistency and so that we can remove the dependencies package exception in this code, we should settle on either neverlink or compile_only, and make sure all rules use the same
    if label.package == "dependencies":
        if not label.name.startswith("compile_only_"):
            return "//%s:compile_only_%s" % (label.package, label.name)
        else:
            return dep
    elif dep.startswith("@maven"):
        return dep.replace("@maven//", "@maven_compile_only//")
    elif not dep.endswith("-neverlink"):
        return dep + "-neverlink"
    else:
        return dep

def _normalize_label(label):
    return str(native.package_relative_label(label))

def _snake_case_name(artifact):
    return artifact.get("group").replace(".", "_").replace("-", "_") + "_" + artifact.get("artifact").replace(".", "_").replace("-", "_")

def _process_runtime_deps(deps, runtime_deps, runtime_deps_exclude):
    """
    Adds all deps to the runtime_deps unless they are in the exclusion list.
    """
    runtime_deps = [_normalize_label(dep) for dep in runtime_deps]
    runtime_deps_exclude = [_normalize_label(dep) for dep in runtime_deps_exclude]
    if type(deps) == type([]):
        for dep in deps:
            _dep = _normalize_label(dep)

            if (
                _dep not in runtime_deps and
                _dep not in runtime_deps_exclude and
                (_dep.startswith("@maven//") or _dep.startswith("@//") or _dep.startswith("@io_bazel_rules_scala"))
            ):
                runtime_deps.append(dep)

    return runtime_deps

def _process_exclusions(deps, runtime_deps, exclusions):
    """
    Add the exclusions on dependencies from the artifact list passed to maven_install.
    This logic should be pushed into rules_jvm_external's _pom_file_impl where a more
    Definitive list of dependencies is available, in a format that is easier to use.
    """
    artifact_to_exclusions = {
        _snake_case_name(artifact): artifact.get("exclusions")
        for artifact in libs.values()
        if type(artifact) == "dict" and artifact.get("exclusions")
    }

    # If select() is used, the type is not a list, and we do not try to access the actual deps.
    # Moving this functionality within a rule, such as _pom_file_impl, would address this.
    if type(deps) == "list" and type(runtime_deps) == "list":
        all_deps = deps + runtime_deps

        def dep_key(dep):
            # Makes an assumption on the repository name. Again, this would not be necessary in _pom_file_impl.
            return dep.split("@maven//:")[-1] if dep.startswith("@maven//:") else None

        exclusions = dict(exclusions)
        exclusions.update({
            dep: artifact_to_exclusions[dep_key(dep)]
            for dep in all_deps
            if dep_key(dep) and dep_key(dep) in artifact_to_exclusions
        })

    return exclusions

def _add_default_resources(add_copyright_and_notice, resources):
    if not add_copyright_and_notice:
        return resources


    if "//:NOTICE" not in resources:
        resources.append("//:NOTICE")

    return resources

def _remove_maven_coordinates_from_tags(tags):
    to_return = []
    for tag in tags:
        if not tag.startswith("maven_coordinates="):
            to_return.append(tag)

    return to_return

def _library_neverlink_option(
        library,
        **attrs):
    name = attrs.get("name")

    remove_library = ["name", "neverlink"]
    remove_neverlink = ["deps"]

    library_attrs = {k: v for k, v in attrs.items() if k not in remove_library}
    neverlink_library_attrs = {k: v for k, v in library_attrs.items() if k not in remove_neverlink}
    deps = attrs.get("deps", [])

    library(name = name, **library_attrs)

    neverlink_tags = _remove_maven_coordinates_from_tags(neverlink_library_attrs.pop("tags", []))
    neverlink_tags.append("maven:compile-only")

    library(
        name = name + "-neverlink",
        neverlink = True,
        deps = [_convert_dep_to_neverlink(dep) for dep in deps],
        tags = neverlink_tags,
        **neverlink_library_attrs
    )

def _scala_library(**attrs):
    """
    Creates a scala library target that uses //:scala_java_toolchain for Java compilation.
    """
    oss_scala_library(java_compile_toolchain = "//toolchains:scala_java_toolchain", **attrs)

def java_library(neverlink_option = False, **attrs):
    """
    If neverlink_option is True, creates two java library targets. One with neverlink option and one without.
    The neverlink library has `-neverlink` suffix in its name.
    If neverlink_option is False, creates a java library target.
    Using a java_library target with neverlink option is the equivalent of importing a 'compileOnly' dependency in Gradle.
    """
    if attrs["name"].endswith("-test-jar"):
        attrs["resources"] = _add_default_resources(True, attrs.get("resources", []))
    if neverlink_option:
        _library_neverlink_option(oss_java_library, **attrs)
    else:
        oss_java_library(**attrs)

    # [system-test-kafka] copy kafka streams test JARs to testlibs directory
    if attrs["name"].startswith("kafka-streams-upgrade-system-tests"):
        conditional_copy_lib_jars(
            name = attrs["name"] + "copy-test-jar",
            jar_name = attrs["name"],
            jar_suffix = "-test",
            libs_target = attrs["name"],
            output_directory = "testlibs",
        )

def scala_library(neverlink_option = False, **attrs):
    """
    If neverlink_option is True, creates two scala library targets. One with neverlink option and one without.
    The neverlink library has `-neverlink` suffix in its name.
    If neverlink_option is False, creates a scala library target.
    Using a scala_library target with neverlink option is the equivalent of importing a 'compileOnly' dependency in Gradle.
    """
    if attrs["name"].endswith("-test-jar") or attrs["name"].endswith("-test-jar-scala"):
        attrs["resources"] = _add_default_resources(True, attrs.get("resources", []))
    if neverlink_option:
        _library_neverlink_option(_scala_library, **attrs)
    else:
        _scala_library(**attrs)

def _maven_export(
        pom_template = "//tools-bazel:pom.tpl",
        enable_compare_tests = True,
        gradle_jar_pattern = "build/libs/*-ce.jar",
        gradle_pom = "build/publications/mavenJava/pom-default.xml",
        **attrs):
    """

    """
    name = attrs.pop("name")
    deps = attrs.get("deps", [])
    exclusions = _process_exclusions(deps, [], attrs.pop("exclusions", {}))

    oss_maven_export(
        name = name,
        pom_template = pom_template,
        exclusions = exclusions,
        excluded_workspaces = excluded_workspaces,
        javadocopts = _get_javadocopts(name),
        **attrs
    )

    if enable_compare_tests:
        create_compare_tests(
            name = name,
            gradle_jar_pattern = gradle_jar_pattern,
            gradle_pom = gradle_pom,
            compare_javadoc_jar = "no-javadocs" not in attrs.get("tags", []),
            compare_source_jar = "no-sources" not in attrs.get("tags", []),
            test_jar = attrs.get("classifier_artifacts", {}).get("test", None),
        )

def _java_export(
        pom_template = "//tools-bazel:pom.tpl",
        enable_compare_tests = True,
        gradle_jar_pattern = "build/libs/*-ce.jar",
        gradle_pom = "build/publications/mavenJava/pom-default.xml",
        add_copyright_and_notice = True,
        alternative_javadoc_title = None,
        **attrs):
    """
    Creates a java export target.

    Exclusions are applied to the dependencies that have them in the artifact list passed to maven_install and the ones
    passed directly in the `exclusions` attribute. The `exclusions` attribute is a dictionary where the key is the artifact.

    All `deps` are added to `runtime_deps` by default, unless they are already in `runtime_deps` or `runtime_deps_exclude`.
    This is to ensure a similar functionality to Gradle's `implementation` configuration, classifying the dependencies
    with scope `runtime` in the generated pom.xml to avoid leaking transitive dependencies to consumers.
    """
    name = attrs.pop("name")
    deps = attrs.get("deps", [])
    runtime_deps = attrs.get("runtime_deps", [])

    attrs["runtime_deps"] = _process_runtime_deps(deps, runtime_deps, attrs.pop("runtime_deps_exclude", []))
    exclusions = _process_exclusions(deps, runtime_deps, attrs.pop("exclusions", {}))
    attrs["resources"] = _add_default_resources(add_copyright_and_notice, attrs.get("resources", []))
    attrs["doc_resources"] = _add_default_resources(add_copyright_and_notice, attrs.get("doc_resources", []))
    javadoc_title = alternative_javadoc_title or name

    oss_java_export(
        name = name,
        pom_template = pom_template,
        exclusions = exclusions,
        excluded_workspaces = excluded_workspaces,
        javadocopts = _get_javadocopts(javadoc_title),
        **attrs
    )

    if enable_compare_tests:
        create_compare_tests(
            name = name,
            gradle_jar_pattern = gradle_jar_pattern,
            gradle_pom = gradle_pom,
            compare_javadoc_jar = "no-javadocs" not in attrs.get("tags", []),
            compare_source_jar = "no-sources" not in attrs.get("tags", []),
            test_jar = attrs.get("classifier_artifacts", {}).get("test", None),
        )

def maven_export(
        neverlink_option = False,
        pom_template = "//tools-bazel:pom.tpl",
        enable_compare_tests = True,
        gradle_jar_pattern = "build/libs/*-ce.jar",
        gradle_pom = "build/publications/mavenJava/pom-default.xml",
        **attrs):
    # It does not look like any of the Gradle artifacts are publishing source jars, so this will block source jar
    # generation and comparison tests for now.
    attrs["tags"] = attrs.get("tags", [])
    attrs["tags"].append("no-sources")
    enable_test_jar_copy = attrs.pop("enable_test_jar_copy", False)

    name = attrs.pop("name")
    _maven_export(
        name = name,
        pom_template = pom_template,
        enable_compare_tests = enable_compare_tests,
        gradle_jar_pattern = gradle_jar_pattern,
        gradle_pom = gradle_pom,
        **attrs
    )

    if neverlink_option:
        remove_neverlink = [
            "maven_coordinates",
            "classifier_artifacts",
            "deps",
            "runtime_deps",
            "exports",
            "runtime_deps_exclude",
            "exclusions",
            "exclusions_on_artifacts",
            "lib_name",
            "doc_resources",
        ]

        neverlink_library_attrs = {k: v for k, v in attrs.items() if k not in remove_neverlink}
        deps = attrs.get("deps", [])
        runtime_deps = attrs.get("runtime_deps", [])
        exports = attrs.get("exports", [])
        neverlink_tags = neverlink_library_attrs.pop("tags", [])
        neverlink_tags.append("maven:compile-only")

        oss_java_library(
            name = name + "-neverlink",
            neverlink = True,
            deps = [_convert_dep_to_neverlink(dep) for dep in deps],
            runtime_deps = [_convert_dep_to_neverlink(dep) for dep in runtime_deps],
            exports = [_convert_dep_to_neverlink(dep) for dep in exports],
            tags = neverlink_tags,
            **neverlink_library_attrs
        )

    # [system-test-kafka] copy output jar to libs directory
    if attrs.get("maven_coordinates"):
        jar_name = attrs.get("maven_coordinates").split(":")[1]
    else:
        jar_name = name
    conditional_copy_lib_jars(
        name = name + "-copy-lib-jar",
        jar_name = jar_name,
        libs_target = name,
    )

    # [system-test-kafka] copy test jar to testlibs directory
    if enable_test_jar_copy and attrs.get("classifier_artifacts", {}).get("test"):
        conditional_copy_lib_jars(
            name = name + "-copy-test-jar",
            jar_name = jar_name,
            jar_suffix = "-test",
            libs_target = attrs.get("classifier_artifacts", {}).get("test"),
            output_directory = "testlibs",
        )

def java_export(
        neverlink_option = False,
        pom_template = "//tools-bazel:pom.tpl",
        enable_compare_tests = True,
        gradle_jar_pattern = "build/libs/*-ce.jar",
        gradle_pom = "build/publications/mavenJava/pom-default.xml",
        add_copyright_and_notice = True,
        alternative_javadoc_title = None,
        **attrs):
    """
    If neverlink_option is True, creates two java export library targets. One with neverlink option and one without.
    The neverlink library has `-neverlink` suffix in its name.
    Using a java_library target with neverlink option is the equivalent of importing a 'compileOnly' dependency in Gradle.

    if pom_template is not provided, it uses the default pom template from tools-bazel.
    if enable_compare_tests is True, it creates two compare tests for jar and pom files.
    if gradle_jar_pattern is not provided, it uses the default gradle jar pattern, only needed if enable_compare_tests is True.
    if gradle_pom is not provided, it uses the default gradle pom file, only needed if enable_compare_tests is True.
    if add_copyright_and_notice is True, it adds the default COPYRIGHT and NOTICE files to the resources.
    if alternative_javadoc_title is provided, it uses the provided title for the javadoc window title and doctitle,
        otherwise it just uses the target name.
    """

    # It does not look like any of the Gradle artifacts are publishing source jars, so this will block source jar
    # generation and comparison tests for now.
    attrs["tags"] = attrs.get("tags", [])
    attrs["tags"].append("no-sources")
    enable_test_jar_copy = attrs.pop("enable_test_jar_copy", False)

    name = attrs.pop("name")
    _java_export(
        name = name,
        pom_template = pom_template,
        enable_compare_tests = enable_compare_tests,
        gradle_jar_pattern = gradle_jar_pattern,
        gradle_pom = gradle_pom,
        add_copyright_and_notice = add_copyright_and_notice,
        alternative_javadoc_title = alternative_javadoc_title,
        **attrs
    )

    if neverlink_option:
        remove_neverlink = [
            "maven_coordinates",
            "classifier_artifacts",
            "deps",
            "runtime_deps",
            "exports",
            "runtime_deps_exclude",
            "exclusions",
            "exclusions_on_artifacts",
            "doc_resources",
        ]

        neverlink_library_attrs = {k: v for k, v in attrs.items() if k not in remove_neverlink}
        deps = attrs.get("deps", [])
        runtime_deps = attrs.get("runtime_deps", [])
        exports = attrs.get("exports", [])
        neverlink_tags = neverlink_library_attrs.pop("tags", [])
        neverlink_tags.append("maven:compile-only")

        oss_java_library(
            name = name + "-neverlink",
            neverlink = True,
            deps = [_convert_dep_to_neverlink(dep) for dep in deps],
            runtime_deps = [_convert_dep_to_neverlink(dep) for dep in runtime_deps],
            exports = [_convert_dep_to_neverlink(dep) for dep in exports],
            tags = neverlink_tags,
            **neverlink_library_attrs
        )

    # [system-test-kafka] copy output jar to libs directory
    if attrs.get("maven_coordinates"):
        jar_name = attrs.get("maven_coordinates").split(":")[1]
    else:
        jar_name = name
    conditional_copy_lib_jars(
        name = name + "-copy-lib-jar",
        jar_name = jar_name,
        libs_target = name,
    )

    # [system-test-kafka] copy test jar to testlibs directory
    if enable_test_jar_copy and attrs.get("classifier_artifacts", {}).get("test"):
        conditional_copy_lib_jars(
            name = name + "-copy-test-jar",
            jar_name = jar_name,
            jar_suffix = "-test",
            libs_target = attrs.get("classifier_artifacts", {}).get("test"),
            output_directory = "testlibs",
        )

def scala_export(**attrs):
    """
    Creates a scala_library target "_name" and passes that to a java_export
    """
    name = attrs.pop("name")
    scala_name = "_" + name
    maven_coordinates = attrs.pop("maven_coordinates")
    classifier_artifacts = attrs.pop("classifier_artifacts", {})
    neverlink_option = attrs.get("neverlink_option", False)
    tags = attrs.get("tags", [])
    visibility = attrs.get("visibility", ["//visibility:public"])
    enable_test_jar_copy = attrs.pop("enable_test_jar_copy", False)
    attrs["runtime_deps"] = _process_runtime_deps(attrs.get("deps", []), attrs.get("runtime_deps", []), attrs.pop("runtime_deps_exclude", []))

    scala_library(name = scala_name, **attrs)

    java_export(
        name = name,
        classifier_artifacts = classifier_artifacts,
        maven_coordinates = maven_coordinates,
        neverlink_option = neverlink_option,
        tags = tags,
        visibility = visibility,
        exports = [":" + scala_name],
        runtime_deps = attrs.get("runtime_deps", []),
        enable_test_jar_copy = enable_test_jar_copy,
    )

def jvm_junit_test_suite(**attrs):
    """
    Uses //:scala_java_toolchain for Java compilation on the scala_library targets.
    """
    internal_jvm_junit_test_suite(java_compile_toolchain = "//toolchains:scala_java_toolchain", **attrs)

def _java_library_exclude_runtime_deps_impl(ctx):
    # JavaInfo does not have attributes for all of its constructor parameters, so we need to access java_outputs
    java_output = ctx.attr.dep[JavaInfo].java_outputs[0]

    # Include just the jar, omitting all dependencies
    return [JavaInfo(
        compile_jar = java_output.compile_jar,
        output_jar = java_output.class_jar,
    )]

java_library_exclude_runtime_deps = rule(
    attrs = {
        "dep": attr.label(
            mandatory = True,
            providers = [JavaInfo],
        ),
    },
    doc = "References a library while excluding all of its runtime dependencies. Unlike with `neverlink = True`, the classes directly compiled from sources within the library will still be on the runtime classpath. Intended for use with java_binary's deploy_env, to selectively add a library to the exclusion, but not its dependencies.",
    implementation = _java_library_exclude_runtime_deps_impl,
)

def unified_proto_java(name, srcs, visibility = "//visibility:public", deps = []):
    proto_lib_name = name + "_proto"
    java_proto_lib_name = name + "_java_proto"
    genrule_out = name + "_src_jar.srcjar"
    genrule_cmd = "cp $(RULEDIR)/" + proto_lib_name + "-speed-src.jar $(location " + genrule_out + ")"

    proto_library(
        name = proto_lib_name,
        srcs = srcs,
        visibility = [visibility],
        deps = deps,
    )

    java_proto_library(
        name = java_proto_lib_name,
        visibility = [visibility],
        deps = [":" + proto_lib_name],
    )

    native.genrule(
        name = name + "_src_jar",
        srcs = [":" + java_proto_lib_name],
        outs = [genrule_out],
        cmd = genrule_cmd,
        visibility = [visibility],
    )
