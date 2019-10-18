load(
    "//experimental/internal/ghrelease:publisher.bzl",
    _ghrelease_publisher = "ghrelease_publisher",
)

load(
    "//experimental/internal/ghrelease:assets.bzl",
    _ghrelease_assets = "ghrelease_assets",
)

load(
    "//experimental/internal/ghrelease:test_suite.bzl",
    _ghrelease_test_suite = "ghrelease_test_suite",
)

load(
    "//experimental/internal/embedding:cas_file.bzl",
    _file_uploader = "file_uploader",
)

load(
    "//experimental/internal/embedding:embedder.bzl",
    _embedded_reference = "embedded_reference",
)


def ghrelease(name, **kwargs):
    label = "%s//%s:%s" % (native.repository_name(), native.package_name(), name)
    print("'ghrelease' is deprecated, please update rule to 'ghrelease_publisher' (%s)" % label)
    ghrelease_publisher(name = name, **kwargs)

ghrelease_publisher = _ghrelease_publisher
ghrelease_assets = _ghrelease_assets
ghrelease_test_suite = _ghrelease_test_suite
file_uploader = _file_uploader
embedded_reference = _embedded_reference
