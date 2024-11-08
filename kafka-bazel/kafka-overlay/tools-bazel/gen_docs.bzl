def gen_docs(name, java_binary, output_html = None):
    """
    Calls the given java_binary and directs System.out to a .html file.
    """
    deploy_jar = java_binary + "_deploy.jar"

    if not output_html:
        output_html = name + ".html"

    native.genrule(
        name = name,
        srcs = [deploy_jar],
        outs = [output_html],
        cmd = "$(JAVA) -jar $(location " + deploy_jar + ") > $@",
        toolchains = ["@bazel_tools//tools/jdk:current_java_runtime"],
    )
