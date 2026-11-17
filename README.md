# Caravana templates

The catalog of app templates for [Caravana](https://github.com/Cosmic-Chimps/caravana), a self-hosted
PaaS on HashiCorp Nomad. A template installs a known app (a status page, a fediverse server, a
database with its admin page) from New app › **From a template** by answering two or three questions.

| Template | What it is |
| --- | --- |
| `uptime-kuma` | A status monitor and status page |
| `hollo` | A single-user fediverse server, with its Postgres |
| `postgres` | PostgreSQL 17 on a volume, backed up daily, with Adminer to look into it |
| `adminer` | A web page to browse and edit a database, behind a user name and password |
| `umbral` | An OpenID Connect provider that signs people in without passwords |
| `frunchy` | Your Crunchyroll watch history as statistics you can share (signs in through Umbral) |
| `continuwuity` | A Matrix homeserver: your own chat server, federated with every other one |
| `peertube` | Video hosting on your own domain, federated, with the videos in an S3-compatible bucket (R2) |
| `codemagic-patch` | Over-the-air updates for React Native and Capacitor apps |

## What a template is

A folder with a manifest and a Compose file with `{{placeholders}}`:

```
catalog.json                    {"format": 1, "version": "2026.11.12"}
templates/<name>/template.json  the manifest
templates/<name>/compose.yaml   the Compose file
templates/<name>/logo.svg       optional
```

- The **Compose file** says which images run and how they are wired. Images are pinned to a version
  (Caravana pins the digest at install). It may not use `depends_on`, a floating tag or anything
  Caravana can't honor: that is a warning, and a warning fails the check.
- The **manifest** has the template's name, title, version, description, tags and upstream link; its
  **inputs** (a `domain`, an `email`, a `text` with a pattern, a `secret`); its **generated secrets**
  (a length and an alphabet; Caravana makes them at install and never shows them); and the **overlay**
  per service: domains, health check, secrets and backup, which Compose has no words for.
- A `{{placeholder}}` is a plain substitution, once, with no logic. A plain input may go anywhere in the
  file or the overlay. A **secret** (a secret input or a generated one) may go only in a service's
  `secrets[].value`, so no password ever lands in the Compose file Caravana keeps and shows.

The format is specified in
[`specs/035-app-templates/contracts/template-format.md`](https://github.com/cosmic-chimps/caravana/blob/main/specs/035-app-templates/contracts/template-format.md)
in Caravana's repository, field by field, with the limits.

## Adding one

1. Make `templates/<name>/` with `template.json` and `compose.yaml`. Start from the nearest existing
   template. Write it from the upstream project's own documentation, and run the image to learn its
   health path: pick one that answers 200 without signing in (not a redirect).
2. Check it: `go run github.com/cosmic-chimps/caravana/cmd/caravana@main template check .` renders every
   template with its example inputs through Caravana's own Compose and job translators.
3. Try it on a Caravana: `lab/install-all.sh <name>` (see below).
4. Open a pull request. CI runs the same check.

Set `"lab": false` in the manifest when the lab job can't install the template (it needs a private
image, say), and say why in its notes.

## The quality gate

`caravana template check <dir>` fails a template that:

- doesn't follow the format (every field says which rule it broke, naming the template);
- puts a secret anywhere but a service's `secrets[].value`, or declares an input nothing uses;
- renders a Compose file Caravana refuses, or one that gives a warning;
- has an image reference Caravana can't read, or a floating tag (`latest`, or none);
- backs up a database with its password in a plain environment variable.

`lab/install-all.sh` is the second gate: it installs each template whose `lab` isn't false into a
running Caravana through its API, with the template's example inputs, waits until it is healthy, deletes
it and prints a table.

```sh
CARAVANA_URL=https://caravana.example.com CARAVANA_TOKEN=cvat_... lab/install-all.sh        # all
CARAVANA_URL=... CARAVANA_TOKEN=... lab/install-all.sh adminer umbral                        # some
```

It needs `curl` and `jq`. A template with a backup is installed without backups when the installation
has no backup destination yet.

## The release

Tag a version (`git tag 2026.11.13 && git push origin 2026.11.13`; `2026.11.13.1` for a second one the
same day). The release workflow bundles the catalog (`caravana template bundle --version <tag> . dist`) and
uploads `catalog.json` and `SHA256SUMS` to a GitHub release. Caravana asks for the latest release once a
day: it fetches `SHA256SUMS` first, `catalog.json` only when its sum changed, checks the sum and every
template, and keeps the catalog if its version is newer than the one it has. Each Caravana release also
embeds a copy, so a new installation works offline. The owner can turn the daily check off in New app ›
From a template, and then Caravana makes no request.

## Licence

AGPL-3.0, as Caravana. See `LICENSE`.
