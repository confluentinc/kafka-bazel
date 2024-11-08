def message_generator(
        name,
        srcs,
        args):
    native.genrule(
        name = name,
        srcs = srcs,
        outs = [
            name + ".srcjar",
        ],
        cmd = "$(location //tools-bazel:message_generator.sh) '$(SRCS)' $(OUTS) $(location //generator:MessageGenerator) $(location @bazel_tools//tools/zip:zipper) " + " ".join(args),
        tools = ["//generator:MessageGenerator", "@bazel_tools//tools/zip:zipper", "//tools-bazel:message_generator.sh"],
    )
