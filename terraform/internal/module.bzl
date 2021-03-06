load(":providers.bzl", "TerraformModuleInfo", "TerraformPluginInfo", "TerraformWorkspaceInfo", "tf_workspace_files_prefix")
load("//experimental/internal/embedding:embedder.bzl", "get_valid_labels")

_module_attrs = {
    "srcs": attr.label_list(
        allow_files = [".tf", ".tf.json"],
        default = [],
    ),
    "data": attr.label_list(
        allow_files = True,
        default = [],
    ),
    "embed": attr.label_list(
        doc = "Merge the content of other <terraform_module>s (or other 'ModuleInfo' providing deps) into this one.",
        providers = [TerraformModuleInfo],
        default = [],
    ),
    "deps": attr.label_list(
        providers = [TerraformModuleInfo],
        default = [],
    ),
    "plugins": attr.label_list(
        doc = "Custom Terraform plugins that this module requires.",
        providers = [TerraformPluginInfo],
        default = [],
    ),
    "modulepath": attr.string(),
}

def module_outputs(name, generate_docs):
    outputs = {
        "out": "%{name}.tar.gz",
        "graph": "%{name}_graph.dot",
    }

    if generate_docs:
        outputs.update({
            "docs_md": "%{name}_docs.md",
            "docs_json": "%{name}_docs.json",
        })

    return outputs

module_tool_attrs = {
    "generate_docs": attr.bool(
        default = False,
    ),
    "_terraform_docs": attr.label(
        default = Label("@tool_terraform_docs"),
        executable = True,
        cfg = "host",
    ),
    "_terraform": attr.label(
        default = Label("@tool_terraform"),
        executable = True,
        cfg = "host",
    ),
    "_resolve_srcs": attr.label(
        default = Label("//terraform/internal:resolve_srcs"),
        executable = True,
        cfg = "host",
    ),
    "_create_root_bundle": attr.label(
        default = Label("//terraform/internal:create_root_bundle"),
        executable = True,
        cfg = "host",
    ),
}

def _collect_srcs(ctx):
    srcs = {}
    for f in ctx.files.srcs:
        if f.basename in srcs and srcs[f.basename] != f:
            fail("Cannot have multiple files with same basename (%s, %s)" % (f, srcs[f.basename]), attr = "srcs")
        srcs[f.basename] = f
    for dep in ctx.attr.embed:
        if getattr(dep[TerraformModuleInfo], "srcs"):
            for f in dep[TerraformModuleInfo].srcs:
                if f.basename in srcs and srcs[f.basename] != f:
                    fail("Cannot have multiple files with same basename (%s, %s)" % (f, srcs[f.basename]), attr = "srcs")
    return srcs.values()

def _collect_data(ctx):
    file_map = {}
    file_tars = []
    for f in ctx.files.data:
        label = f.owner or ctx.label
        prefix = label.package + "/"
        path = f.short_path[len(prefix):]
        if path in file_map and f != file_map[path]:
            fail("Conflicting files for path '%s' (%s, %s)" % (path, f, file_map[path]), attr = "data")
        file_map[path] = f
    for dep in ctx.attr.embed:
        info = dep[TerraformModuleInfo]
        for path, f in getattr(info, "file_map", {}).items():
            if path in file_map and f != file_map[path]:
                fail("Conflicting files for path '%s' (%s, %s)" % (path, f, file_map[path]), attr = "data")
            file_map[path] = f
        if getattr(info, "file_tars"):
            file_tars += [info.file_tars]
    return file_map, depset(transitive = file_tars)

def _collect_plugins(ctx):
    transitive = []
    for dep in ctx.attr.embed + ctx.attr.deps:
        if hasattr(dep[TerraformModuleInfo], "plugins"):
            transitive += [dep[TerraformModuleInfo].plugins]
    return depset(direct = ctx.attr.plugins, transitive = transitive)

def _collect_deps(ctx):
    """
    Return (direct_modules, modules)
    """
    # "direct" will be..
    # - ctx.attr.deps
    # - also, for each ctx.attr.embed, TerraformModuleInfo.direct_modules

    # "all" is
    # - ctx.attr.deps, ctx.attr.embed
    # - TerraformModuleInfo.modules for both deps & embeds
    transitive = []  # used to create "modules" (ie all)
    embedded = []  # used to create "direct_modules"
    for embed in ctx.attr.embed:
        if hasattr(embed[TerraformModuleInfo], "modules"):
            transitive += [embed[TerraformModuleInfo].modules]
        if hasattr(embed[TerraformModuleInfo], "direct_modules"):
            embedded += [embed[TerraformModuleInfo].direct_modules]
    for dep in ctx.attr.deps:
        if hasattr(dep[TerraformModuleInfo], "modules"):
            transitive += [dep[TerraformModuleInfo].modules]
    direct_modules = depset(direct = ctx.attr.deps, transitive = embedded)
    modules = depset(transitive = transitive + [direct_modules])
    return direct_modules, modules

def _generate_docs(ctx, srcs, md_output = None, json_output = None):
    files = ctx.actions.args()
    files.add_all([f for f in srcs if f.extension == "tf"])

    #    files = [f for f in srcs if f.extension == "tf"]
    #    if files
    ctx.actions.run_shell(
        inputs = srcs + [ctx.executable._terraform_docs],
        outputs = [md_output, json_output],
        arguments = [
            ctx.executable._terraform_docs.path,
            md_output.path,
            json_output.path,
            files,
        ],
        command = """set -eu
terraform_docs="$1"; shift
md_out="$1"; shift
json_out="$1"; shift
"$terraform_docs" --sort-inputs-by-required md   "$@" > "$md_out"
"$terraform_docs" --sort-inputs-by-required json "$@" > "$json_out"
""",
        tools = ctx.attr._terraform_docs.default_runfiles.files,
    )

def _generate_graph(ctx, root_bundle = None, plugins = None, output = None):
    plugin_files = {}
    for p in plugins.to_list():
        plugin_files.update(p[TerraformPluginInfo].files)

    # tgt_filename=>src_file pairs
    plugin_file_args = ctx.actions.args()
    for tgt, src in plugin_files.items():
        plugin_file_args.add_all([tgt, src])

    ctx.actions.run_shell(
        inputs = plugin_files.values() + [
            root_bundle,
            ctx.executable._terraform,
        ],
        outputs = [output],
        arguments = [
            ctx.executable._terraform.path,
            output.path,
            root_bundle.path,
            plugin_file_args,
        ],
        command = """set -eu
: ${USER:=$(whoami)}
if [ -e "/Users/$USER" ]; then
    : ${HOME:="/Users/$USER"}
else
    : ${HOME:="/home/$USER"}
fi
export USER HOME
tf="$PWD/$1"; shift
output="$PWD/$1"; shift
root_bundle="$PWD/$1"; shift
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:=$TMPDIR/rules_terraform/plugin-cache}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"
workspace_dir="$(mktemp -d)"
trap "rm -rf $workspace_dir" EXIT
tar xzf "$root_bundle" -C $workspace_dir
while [[ $# -gt 0 ]]; do
    tgt="$workspace_dir/.terraform/plugins/$1"; shift
    src="$PWD/$1"; shift
    mkdir -p $(dirname "$tgt")
    ln -s "$src" "$tgt"
done
cd "$workspace_dir"
"$tf" init > /dev/null
"$tf" graph > "$output"
""",
        execution_requirements = {
            "requires-network": "1",
        },
        tools = ctx.attr._terraform.default_runfiles.files,
    )

def _resolve_srcs(
        ctx,
        modulepath = None,
        srcs = None,
        modules = None,
        module_resolved_srcs_output = None,
        root_resolved_srcs_output = None):
    args = ctx.actions.args()
    args.add("--modulepath", modulepath)
    args.add("--module_resolved_output", module_resolved_srcs_output)
    args.add("--root_resolved_output", root_resolved_srcs_output)
    for f in srcs:
        args.add("--input", f)
    for m in modules.to_list():
        info = m[TerraformModuleInfo]
        if not getattr(info, "modulepath"):
            fail("Implementation error. %s's TerraformModuleInfo provider has no 'modulepath' field." % ctx.label, attr = "deps")
        args.add("--embedded_module", struct(
            label = str(m.label),
            modulepath = info.modulepath,
            valid_labels = get_valid_labels(ctx, m.label),
        ).to_json())
    ctx.actions.run(
        inputs = srcs,
        outputs = [module_resolved_srcs_output, root_resolved_srcs_output],
        arguments = [args],
        mnemonic = "ResolveTerraformSrcs",
        executable = ctx.executable._resolve_srcs,
        tools = ctx.attr._resolve_srcs.default_runfiles.files,
    )

def _create_root_bundle(ctx, output, root_resolved_srcs, module_info):
    args = ctx.actions.args()
    inputs = []
    transitive = []

    args.add("--output", output)

    # get relevant data from the immediate module
    args.add_all("--input_tar", ["", root_resolved_srcs])
    inputs += [root_resolved_srcs]
    if module_info.file_map:
        for path, file in module_info.file_map.items():
            args.add_all("--input_file", [path, file], expand_directories=False)
            inputs += [file]
    if module_info.file_tars:
        transitive += [module_info.file_tars]
        for f in module_info.file_tars.to_list():
            args.add_all("--input_tar", ["", f])

    # get relevant data from dependant modules
    if module_info.modules:
        for dep in module_info.modules.to_list():
            m = dep[TerraformModuleInfo]
            args.add_all("--input_tar", [m.modulepath, m.resolved_srcs])
            inputs += [m.resolved_srcs]
            for f in m.file_tars.to_list():
                args.add_all("--input_tar", [m.modulepath, f])
            transitive += [m.file_tars]
            if getattr(m, "file_map"):
                for path, file in m.file_map.items():
                    args.add_all("--input_file", ["modules/%s/%s" % (m.modulepath, path), file], expand_directories=False)
                    inputs += [file]
    ctx.actions.run(
        inputs = depset(direct = inputs, transitive = transitive),
        outputs = [output],
        arguments = [args],
        mnemonic = "CreateTerraformRootBundle",
        executable = ctx.executable._create_root_bundle,
        tools = ctx.attr._create_root_bundle.default_runfiles.files,
    )

def module_impl(ctx, modulepath = None):
    """
    """
    modulepath = modulepath or ctx.attr.modulepath or "{pkg}_{name}".format(
        pkg = ctx.label.package.replace("/", "_"),
        name = ctx.attr.name,
    )

    # collect & resolve sources
    srcs = _collect_srcs(ctx)
    module_resolved_srcs = ctx.actions.declare_file(ctx.attr.name + ".module-srcs.tar")
    root_resolved_srcs = ctx.actions.declare_file(ctx.attr.name + ".root-srcs.tar")
    direct_modules, modules = _collect_deps(ctx)
    _resolve_srcs(
        ctx,
        modulepath = modulepath,
        srcs = srcs,
        modules = direct_modules,
        module_resolved_srcs_output = module_resolved_srcs,
        root_resolved_srcs_output = root_resolved_srcs,
    )

    # generate docs from sources
    if ctx.attr.generate_docs:
        _generate_docs(
            ctx,
            srcs,
            md_output = ctx.outputs.docs_md,
            json_output = ctx.outputs.docs_json,
        )

    # collect files & add generated docs
    file_map, file_tars = _collect_data(ctx)
    if ctx.attr.generate_docs:
        file_map["README.md"] = ctx.outputs.docs_md

    # collect plugins & we can finally create our TerraformModuleInfo!
    plugins = _collect_plugins(ctx)
    module_info = TerraformModuleInfo(
        modulepath = modulepath,
        srcs = srcs,
        resolved_srcs = module_resolved_srcs,
        file_map = file_map,
        file_tars = file_tars,
        plugins = plugins,
        modules = modules,
        direct_modules = direct_modules,
    )

    # create the "root module bundle" by providing our module_info
    _create_root_bundle(ctx, ctx.outputs.out, root_resolved_srcs, module_info)

    # create a 'dot' graph of our resources
    _generate_graph(
        ctx,
        root_bundle = ctx.outputs.out,
        plugins = plugins,
        output = ctx.outputs.graph,
    )

    providers = [
        module_info,
        DefaultInfo(files = depset(direct = [ctx.outputs.out])),
    ]

    if ctx.attr.generate_docs:
        providers.append(
            OutputGroupInfo(docs = [ctx.outputs.docs_md]),
        )


    # return our module_info on a struct so other things can use it
    return struct(
        terraform_module_info = module_info,
        providers = providers,
    )

terraform_module = rule(
    module_impl,
    attrs = dict(module_tool_attrs.items() + _module_attrs.items()),
    outputs = module_outputs,
)
