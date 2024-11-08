load("@contrib_rules_jvm//java:defs.bzl", "checkstyle_config")

def checkstyle_config_wrapped(
        name,
        checkstyle_binary,
        checkstyle_xml,
        import_control_xml,
        suppressions_xml,
        java_header = None):
    """
    Reads the checkstyle config from the given checkstyle_xml file and replaces the import-control and suppressions
    variables with the given import_control_xml and suppressions_xml files using proper pathing for bazel.
    """
    out_file = name + "_import-control.xml"
    gen_name = name + "_genrule"

    srcs = [
        "update_checkstyle_bazel.sh",
        checkstyle_xml,
        import_control_xml,
        suppressions_xml,
    ]

    data = [
        import_control_xml,
        suppressions_xml,
    ]

    if java_header:
        srcs.append(java_header)
        data.append(java_header)

    native.genrule(
        name = gen_name,
        srcs = srcs,
        outs = [out_file],
        cmd = " ".join([
            "bash $(location update_checkstyle_bazel.sh) ",
            "$(@D)/{} ".format(out_file),
            "$(location {})".format(checkstyle_xml),
            "$(location {})".format(import_control_xml),
            "$(location {})".format(suppressions_xml),
            "$(location {})".format(java_header) if java_header else "",  # Optional
        ]),
    )

    checkstyle_config(
        name = name,
        checkstyle_binary = checkstyle_binary,
        config_file = "//checkstyle:" + gen_name,
        data = data,
        visibility = ["//visibility:public"],
    )
