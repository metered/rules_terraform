load("//experimental:publishing.bzl", "ghrelease_assets", "ghrelease_publisher", "ghrelease_test_suite")

VERSION = "0.2"

ghrelease_publisher(
    name = "draft",
    args = ["--draft"],
    version = VERSION,
    deps = [
        ":prerelease-tests",
        ":tf-modules",
    ],
)

ghrelease_publisher(
    name = "check",
    asset_upload_prefix = "s3://anthology-storage-dev-us-east-1/tests/",
    version = VERSION,
    deps = [
        ":prerelease-tests",
        ":tf-modules",
    ],
)

ghrelease_publisher(
    name = "publish",
    args = ["--publish"],
    version = VERSION,
    deps = [
        ":prerelease-tests",
        ":tf-modules",
    ],
)

ghrelease_assets(
    name = "tf-modules",
    bazel_flags = ["--config=publish"],
    data = [
        "//examples/src:hello-world_ecs",
        "//examples/src:hello-world_k8s",
        "//examples/src:hello-world_tf",
    ],
)

ghrelease_test_suite(
    name = "prerelease-tests",
    tests = [
        "//...",
        # "//examples/test:k8s-e2e_integration_test",
        # "//examples/test:ecs-e2e_integration_test"
    ],
)
