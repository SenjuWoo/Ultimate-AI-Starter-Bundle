# Shared build tools and project dependencies

The Starter Bundle owns shared build/runtime provisioning. Skyrim Forge owns
Skyrim SDK and plugin-development guidance. Reverse THIS! owns binary/application
analysis tools. A build tool needed by an analysis or Skyrim project can be
reused from the shared installation without copying it into that toolbench.

## Xmake

Xmake belongs in the default shared compiler/build suite alongside CMake/Ninja,
MSVC/Windows SDK, GCC, Go, Rust and .NET. The installer finds the existing
executable first, uses the official `Xmake-io.Xmake` winget owner for supported
updates, and compiles/runs a dependency-free C++23/MSVC fixture. It does not
replace project SDK pins or install another copy beside a working installation.
The observed installed version accepts a vendor `+HEAD` suffix and colored
version output; those are not signs of an unsupported compiler.

[Xmake upstream](https://github.com/xmake-io/xmake) owns its releases. The
[libxse CommonLibSSE](https://github.com/libxse/commonlibsse) Xmake workflow
belongs in Forge's native-plugin guidance. Xmake itself is general-purpose.

## Tools supplied under zIDK

These are useful general build tools, rather than reverse-engineering payloads:

| Tool | Use when | Installation boundary |
|---|---|---|
| [Nx](https://github.com/nrwl/nx) | A monorepo needs a project graph, task scheduling and caching | Follow the existing workspace's package-manager manifest and lock. The supplied checkout is a private source monorepo with placeholder package versions, not an installed `nx` release. |
| [Turborepo](https://github.com/vercel/turborepo) | A JavaScript/TypeScript monorepo uses Turbo task pipelines and caching | Reuse its project-local `turbo` dependency. The supplied Windows executable is a binary download; a folder name alone does not prove version or provenance. |
| [Vite](https://github.com/vitejs/vite) | A frontend project needs a development server and bundler | Use the project's Vite/plugin versions and supported Node range. Its source monorepo is not a drop-in global install. |
| [webpack](https://github.com/webpack/webpack) | An existing application uses webpack loaders/plugins and build configuration | Keep the project's webpack/webpack-cli and loader lock; do not add Vite merely because it is also available. |

All four upstream projects identify MIT licensing; dependency and service terms
are separate. Their full source checkouts are documented references, not
vendored into the bundle. A project selects its actual build system; installing
all alternatives globally would add duplicate state and does not improve that
project's builds. Preserve existing cache, account and telemetry preferences.

Use the package manager already declared by the project and its locked install
workflow. Update those dependencies as a reviewed project change with the
project's actual build/tests, rather than as a machine-wide bundle upgrade.
No repository snapshot, unknown downloaded executable or lifecycle script is
run simply because it appeared in a supplied tools folder.
