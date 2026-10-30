#!/usr/bin/env bash
# Signs dist/<version>/, rebuilds the DNF and APT metadata from all of dist/, uploads the release
# to GitHub and pushes public/, which Cloudflare deploys from this repo. See README.md.
set -euo pipefail

version=${1:?usage: release.sh <version> [--dry-run]}
dry_run=${2:-}
key=${FARPANE_GPG_KEY:?set FARPANE_GPG_KEY to the signing key}
url=https://packages.spidey.in
root=$(cd "$(dirname "$0")/.." && pwd)
files=$root/dist/$version
[[ -d $files ]] || { echo "no $files" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
public=$root/public
rm -rf "$public"
mkdir -p "$public/apt"
gpg --armor --export "$key" > "$public/farpane.asc"
cat > "$public/index.html" <<EOF
<!DOCTYPE html>
<meta http-equiv="refresh" content="0; url=https://www.spidey.in/farpane/">
<title>Farpane packages</title>
<a href="https://www.spidey.in/farpane/">Farpane</a>
EOF

sign() { gpg --batch --yes --local-user "$key" "$@"; }

cat > "$public/farpane.repo" <<EOF
[farpane]
name=Farpane
baseurl=$url/rpm/fedora/\$releasever/\$basearch/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=$url/farpane.asc
EOF

# RPMs, one repo per Fedora release and architecture. Only the metadata is published.
shopt -s nullglob
for rpm in "$files"/*.rpm; do
  rpmsign --addsign --define "_gpg_name $key" "$rpm"
done
for rpm in "$root"/dist/*/*.rpm; do
  name=$(basename "$rpm")
  [[ $name =~ \.fc([0-9]+)\.([a-z0-9_]+)\.rpm$ ]] || { echo "bad name: $name" >&2; exit 1; }
  dir=rpm/fedora/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}
  mkdir -p "$work/$dir"
  ln -s "$rpm" "$work/$dir/$name"
done
for dir in "$work"/rpm/fedora/*/*; do
  createrepo_c --quiet "$dir"
  target=$public/${dir#"$work"/}
  mkdir -p "$target"
  cp -r "$dir/repodata" "$target/"
  sign --armor --detach-sign "$target/repodata/repomd.xml"
done

# .debs, one suite per distro release (ubuntu26.04, debian13). Clients use apt/<suite>.sources.
for deb in "$root"/dist/*/*.deb; do
  name=$(basename "$deb")
  [[ $name =~ \.([a-z]+[0-9.]+)_([a-z0-9]+)\.deb$ ]] || { echo "bad name: $name" >&2; exit 1; }
  dir=$work/apt/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/pool
  mkdir -p "$dir"
  ln -s "$deb" "$dir/$name"
done
for suite_dir in "$work"/apt/*; do
  [[ -d $suite_dir ]] || continue
  suite=$(basename "$suite_dir")
  dists=$public/apt/dists/$suite
  arches=()
  for arch_dir in "$suite_dir"/*; do
    arch=$(basename "$arch_dir")
    arches+=("$arch")
    index=$dists/main/binary-$arch
    mkdir -p "$index"
    (cd "$arch_dir" && dpkg-scanpackages --multiversion pool /dev/null 2>/dev/null) > "$index/Packages"
    gzip -9nk "$index/Packages"
  done
  {
    echo "Origin: Farpane"
    echo "Label: Farpane"
    echo "Suite: $suite"
    echo "Codename: $suite"
    echo "Architectures: ${arches[*]}"
    echo "Components: main"
    echo "Date: $(LC_ALL=C date -Ru)"
    echo "SHA256:"
    (cd "$dists" && find main -type f | sort | while read -r path; do
      echo " $(sha256sum "$path" | cut -d' ' -f1) $(stat -c %s "$path") $path"
    done)
  } > "$dists/Release"
  sign --clearsign --output "$dists/InRelease" "$dists/Release"
  sign --armor --detach-sign --output "$dists/Release.gpg" "$dists/Release"
  cat > "$public/apt/$suite.sources" <<EOF
Types: deb
URIs: $url/apt
Suites: $suite
Components: main
Signed-By: /etc/apt/keyrings/farpane.asc
EOF
done

if [[ $dry_run == --dry-run ]]; then
  echo "built $public, nothing uploaded"
  exit 0
fi

(cd "$files" && sha256sum -- * | grep -v ' SHA256SUMS$' > SHA256SUMS)
if gh release view "v$version" >/dev/null 2>&1; then
  gh release upload "v$version" "$files"/* --clobber
else
  gh release create "v$version" "$files"/* --title "Farpane $version" \
    --notes "Install and setup: https://www.spidey.in/farpane/"
fi
cd "$root"
git add public
git commit -m "Repo metadata for $version"
git push
