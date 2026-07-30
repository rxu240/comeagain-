"""Docker-build-time patch for jac_client 0.3.25's redundant double build.

`jac start main.jac --client pwa` builds the client bundle twice on every
container start: PWATarget.start() calls self.build(), then delegates to
WebTarget.start() which calls self.build() again from scratch
(WebTarget.build() always rmtrees and rebuilds dist/, force=True, no
caching). On a memory-constrained container this doubles peak Vite/Bun
memory usage for zero benefit, since nothing changed between the two
builds.

This patches the installed jac_client package (found via `import
jac_client`) so WebTarget.build() will reuse an already-built dist/ instead
of rebuilding it, but *only* when the JAC_REUSE_PREBUILT_CLIENT=1 env var
is set - this keeps local dev and any other environment's behavior
unchanged, and only affects this project's own Docker image, where we set
that env var and pre-build the bundle once at image-build time.
"""
import glob
import importlib.util
import os
import sys

OLD = '''    bundler = ViteBundler(project_dir=project_dir);

    # Clean dist directory for fresh build
    dist_dir = bundler.output_dir;
    if dist_dir {
        if dist_dir.exists() {
            shutil.rmtree(dist_dir);
        }
        dist_dir.mkdir(parents=True, exist_ok=True);
    }'''

NEW = '''    import os;

    bundler = ViteBundler(project_dir=project_dir);
    dist_dir = bundler.output_dir;

    if os.environ.get("JAC_REUSE_PREBUILT_CLIENT") == "1" and dist_dir and dist_dir.exists() {
        existing = bundler.find_bundle();
        if existing {
            return existing;
        }
    }

    # Clean dist directory for fresh build
    if dist_dir {
        if dist_dir.exists() {
            shutil.rmtree(dist_dir);
        }
        dist_dir.mkdir(parents=True, exist_ok=True);
    }'''


def main() -> None:
    spec = importlib.util.find_spec("jac_client")
    if spec is None or not spec.submodule_search_locations:
        print("patch_jac_client_prebuild: jac_client not installed, skipping", file=sys.stderr)
        return
    pkg_root = list(spec.submodule_search_locations)[0]
    target = f"{pkg_root}/plugin/src/targets/impl/web_target.impl.jac"

    with open(target, "r", encoding="utf-8") as f:
        content = f.read()

    if NEW in content:
        print(f"patch_jac_client_prebuild: already patched: {target}")
        return

    if OLD not in content:
        raise SystemExit(
            f"patch_jac_client_prebuild: expected block not found in {target} "
            "(jac_client version may have changed - update this patch or drop it)"
        )

    content = content.replace(OLD, NEW, 1)
    with open(target, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"patch_jac_client_prebuild: patched {target}")

    # The pip wheel ships precompiled bytecode caches (_precompiled/cpython-*/)
    # alongside the .jac source. If jaclang prefers loading these over
    # recompiling from source, our source edit above would be silently
    # ignored. Delete the matching cached artifacts so jaclang is forced to
    # recompile from the patched source.
    stale = glob.glob(f"{pkg_root}/_precompiled/cpython-*/plugin/src/targets/web_target.jir")
    for path in stale:
        os.remove(path)
        print(f"patch_jac_client_prebuild: removed stale cache {path}")


if __name__ == "__main__":
    main()
