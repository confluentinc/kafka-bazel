MULTIVERSE_NAME = "default"
IS_SCALA_2_12 = False
BASE_SCALA_VERSION = "2.13"

SCALAC_OPTS = [
    "-deprecation:false",
    "-unchecked",
    "-encoding",
    "utf8",
    "-Xlog-reflective-calls",
    "-feature",
    "-language:postfixOps",
    "-language:implicitConversions",
    "-language:existentials",
    "-Xlint:constant",
    "-Xlint:delayedinit-select",
    "-Xlint:doc-detached",
    "-Xlint:missing-interpolator",
    "-Xlint:nullary-unit",
    "-Xlint:option-implicit",
    "-Xlint:package-object-classes",
    "-Xlint:poly-implicit-overload",
    "-Xlint:private-shadow",
    "-Xlint:stars-align",
    "-Xlint:type-parameter-shadow",
    "-Xlint:unused",
    "-opt-warnings",
    "-Xlint:strict-unsealed-patmat",
    "-Xfatal-warnings",
    # https://stackoverflow.com/a/62440046
    "-Wconf:msg=While parsing annotations in:silent",
    "-release",
    "8",
]

TARGET_SCALA_SUFFIX = "_2_13"

def maven_dep(coordinates_string):
    coord = _parse_maven_coordinates(coordinates_string)
    if coord["is_scala"]:
        artifact_id = coord["artifact_id"] + TARGET_SCALA_SUFFIX
    else:
        artifact_id = coord["artifact_id"]
    if "version" in coord:
        str = "@maven//:{}_{}_{}".format(coord["group_id"], artifact_id, coord["version"])
    else:
        str = "@maven//:{}_{}".format(coord["group_id"], artifact_id)
    return str.replace(".", "_").replace("-", "_")

def _parse_maven_coordinates(coordinates_string):
    """
    Given a string containing a standard Maven coordinate (g:a:[p:[c:]]v),
    returns a Maven artifact map (see above).
    See also https://github.com/bazelbuild/rules_jvm_external/blob/4.3/specs.bzl
    """
    if "::" in coordinates_string:
        idx = coordinates_string.find("::")
        group_id = coordinates_string[:idx]
        rest = coordinates_string[idx + 2:]
        is_scala = True
    elif ":" in coordinates_string:
        idx = coordinates_string.find(":")
        group_id = coordinates_string[:idx]
        rest = coordinates_string[idx + 1:]
        is_scala = False
    else:
        fail("failed to parse '{}'".format(coordinates_string))
    parts = rest.split(":")
    artifact_id = parts[0]
    if (len(parts)) == 1:
        result = dict(group_id = group_id, artifact_id = artifact_id, is_scala = is_scala)
    elif len(parts) == 2:
        version = parts[1]
        result = dict(group_id = group_id, artifact_id = artifact_id, version = version, is_scala = is_scala)
    elif len(parts) == 3:
        packaging = parts[1]
        version = parts[2]
        result = dict(group_id = group_id, artifact_id = artifact_id, packaging = packaging, version = version, is_scala = is_scala)
    elif len(parts) == 4:
        packaging = parts[1]
        classifier = parts[2]
        version = parts[3]
        result = dict(group_id = group_id, artifact_id = artifact_id, packaging = packaging, classifier = classifier, version = version, is_scala = is_scala)
    else:
        fail("failed to parse '{}'".format(coordinates_string))
    return result
