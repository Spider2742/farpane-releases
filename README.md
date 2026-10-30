# Farpane releases

Download page: https://www.spidey.in/farpane/

This repo publishes Farpane's builds, in [Releases](https://github.com/Spider2742/farpane-releases/releases).
Farpane's source code isn't here. Bugs and questions: support@spidey.in, or
[Spidey's Web on Discord](https://discord.gg/JXcPvtCFcg).

## How it's served

GitHub Releases holds every file. `packages.spidey.in`, a Cloudflare Worker (`worker/index.js`),
holds the signed DNF and APT metadata (`public/`) and redirects each `.rpm` or `.deb` request to its release
file, so DNF and APT see one normal repo. Cloudflare deploys it from this repo on every push.

## Publishing a release

Needs `gh`, `gpg`, `createrepo_c`, `rpm-sign`, `dpkg-dev`, and the signing key in the local
keyring. Keep every published version in `dist/<version>/`: metadata is rebuilt from that folder,
so a version missing from it drops out of the repos (its release stays on GitHub).

```sh
export FARPANE_GPG_KEY=<key fingerprint>
tools/release.sh 0.2.0            # sign, build metadata, upload, push public/
tools/release.sh 0.2.0 --dry-run  # sign and build public/ only
```

Package file names must look like this, since the version and repo come from the name. GitHub
changes `~` in file names, so don't use it.

```
farpane-0.2.0-1.fc44.x86_64.rpm
farpane_0.2.0-1.ubuntu26.04_amd64.deb
```
