load(
    "//terraform/internal:terraform.bzl",
    _terraform_provider = "terraform_provider",
)

load(
    "//terraform/internal:workspace.bzl",
    _terraform_workspace = "terraform_workspace_macro",
)

load(
    "//terraform/internal:module.bzl",
    _terraform_module = "terraform_module",
)

load(
    "//terraform/internal:integration_test.bzl",
    _terraform_intergration_test = "terraform_integration_test",
)

terraform_provider = _terraform_provider
terraform_workspace = _terraform_workspace
terraform_module = _terraform_module
terraform_intergration_test = _terraform_intergration_test
