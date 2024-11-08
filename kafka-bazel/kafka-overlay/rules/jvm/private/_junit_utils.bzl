"""junit utils module"""

def sanitize_string_for_usage(s):
    """ Sanitize String

    Args:
        s (string): input string

    Returns:
        string: sanitized string
    """
    res_array = []
    for idx in range(len(s)):
        c = s[idx]
        if c.isalnum() or c == ".":
            res_array.append(c)
        else:
            res_array.append("_")
    return "".join(res_array)

def get_class_name(src, prefixes = []):
    """Strip the suffix from the source

    Args:
        src (string): file path
        prefixes (list): prefixes to strip

    Returns:
        string: class name
    """
    idx = src.rindex(".")
    name = src[:idx]

    for prefix in prefixes:
        idx = name.find(prefix)
        if idx != -1:
            return name[idx + len(prefix):].replace("/", ".")
    return name.replace("/", ".")

def _is_test(src, test_suffixes, test_suffixes_excludes, test_prefixes_excludes):
    """Check if the source is a test.

    Args:
        src (string): file path
        test_suffixes (list): suffixes to identify test files
        test_suffixes_excludes (list): suffixes to exclude from test files
        test_prefixes_excludes (list): prefixes to exclude from test files

    Returns:
        boolean
    """
    for suffix in test_suffixes:
        if src.endswith(suffix):
            for suffix_exclude in test_suffixes_excludes:
                if src.endswith(suffix_exclude):
                    return False
            for prefix_exclude in test_prefixes_excludes:
                if src.split("/")[-1].startswith(prefix_exclude):
                    return False
            return True
    return False

def is_integration(src, test_tags = []):
    """Check if test is an integration test.

    Determined by the file path containing "integration" or an existing
    "integration" tag.

    Args:
        src (string): file path
        test_tags (list): tags to be applied to the test

    Returns:
        boolean
    """
    if "integration" in src.lower():
        return True
    for tag in test_tags:
        if tag.lower() == "integration":
            return True

    return False

def get_cpu_n_tag(test_tags):
    """Get the cpu tag from the test tags

    Args:
        test_tags (list): tags to be applied to the test

    Returns:
        string: cpu tag, None if not found
    """
    for tag in test_tags:
        if tag.startswith("cpu:"):
            return tag
    return None

def get_test_files(
        srcs = [],
        test_suffixes = [],
        additional_library_srcs = [],
        test_suffixes_excludes = [],
        test_prefixes_excludes = []):
    """
    This function creates a common test suite.

    Args:
        srcs: The source files for the test suite.
        test_suffixes: The suffixes of test files.
        additional_library_srcs: Additional source files for the test suite.
        test_suffixes_excludes: The suffixes to exclude from test files.
        test_prefixes_excludes: The prefixes to exclude from test files.

    Returns:
        A tuple containing the test suite and non-test source files.
    """
    nontest_srcs = []
    test_srcs = []
    for src in srcs:
        if _is_test(src, test_suffixes, test_suffixes_excludes, test_prefixes_excludes):
            test_srcs.append(src)
        else:
            nontest_srcs.append(src)

    for src in additional_library_srcs:
        nontest_srcs.append(src)

    return test_srcs, nontest_srcs