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
| `wazuh` | A security platform: agents send events, Wazuh finds threats and shows them on a dashboard (indexer, manager and dashboard; about 4 GB) |
| `codemagic-patch` | Over-the-air updates for React Native and Capacitor apps, signing in with GitHub, Bitbucket Cloud or GitLab (you choose) |

## What a template is

A folder with a manifest and a Compose file with `{{placeholders}}`:

```
catalog.json                       {"format": 2, "version": "2026.11.25"}
templates/<name>/template.json     the manifest
templates/<name>/compose.yaml      the Compose file
templates/<name>/logo.svg          optional
templates/<name>/template.v1.json  optional: a frozen format-1 variant (see "Two formats")
templates/<name>/compose.v1.yaml   its Compose file
```

- The **Compose file** says which images run and how they are wired. Images are pinned to a version
  (Caravana pins the digest at install). It may not use `depends_on`, a floating tag or anything
  Caravana can't honor: that is a warning, and a warning fails the check.
- The **manifest** has the template's name, title, version, description, tags and upstream link; its
  **inputs** (a `domain`, an `email`, a `text` with a pattern, a `secret`, or a `choice` between a few
  answers; at most 20; any may be `"required": false`, and any may be asked only `"when"` an earlier choice
  has a given answer); its **generated secrets**
  (a length and an alphabet; Caravana makes them at install and never shows them); and the **overlay**
  per service: domains, health check, secrets and backup, which Compose has no words for.
- Content that only one answer needs is **conditional**: a single-line entry of the Compose file ends with a
  marker comment (`GITHUB_OAUTH_CLIENT_ID: "{{gh_client_id}}" # when signin=github`, or `# when
  signin=bitbucket,gitlab`, or `# when s3_region` for "when that input isn't empty"), and an item of the
  overlay's `domains`, `secrets`, `identities` or `publish` may carry `"when": {"signin": "github"}`. What
  doesn't hold is dropped, so nothing empty reaches the app. See `codemagic-patch`.
- A `{{placeholder}}` is a plain substitution, once, with no logic. A plain input may go anywhere in the
  file or the overlay. A **secret** (a secret input or a generated one) may go only in a service's
  `secrets[].value`, so no password ever lands in the Compose file Caravana keeps and shows.
- A template may ask Caravana to make **certificates** at install (`"certificates"`: one certificate
  authority and the certificates it signs, RSA 2048, ten years; the authority's key is thrown away). They
  make the secret names `ca_cert`, `<leaf>_cert` and `<leaf>_key`, usable like a generated secret. The
  filter `{{admin_password|bcrypt}}` writes the bcrypt hash of a secret, for services that keep hashes
  (OpenSearch's internal users). A template that uses either needs a Caravana that has them, so it sets
  `"requires"` and is listed as unavailable to an older one. See `wazuh`.

The format is specified in
[`specs/058-template-inputs/contracts/template-format-2.md`](https://github.com/cosmic-chimps/caravana/blob/main/specs/058-template-inputs/contracts/template-format-2.md)
(certificates and the bcrypt filter: [`specs/060-opensearch-apps/contracts/template-format-060.md`](https://github.com/cosmic-chimps/caravana/blob/main/specs/060-opensearch-apps/contracts/template-format-060.md))
(and, for what format 1 has, `specs/035-app-templates/contracts/template-format.md`) in Caravana's
repository, field by field, with the limits.

### Two formats

Caravana up to 0.22 reads only `catalog.json` in **format 1** (at most 12 inputs; the types `domain`,
`email`, `text`, `secret`; no `required`, `choices` or `when`) and refuses a whole catalog that holds one thing
it doesn't know, which would stop its template list from updating. So a release publishes two bundles:

- `catalog.v2.json`, format 2, every template as `template.json` and `compose.yaml` are written. Newer
  Caravana reads this one (and falls back to `catalog.json` for a release that has none).
- `catalog.json`, format 1, **for the older ones**: each template whose files already pass format 1's rules,
  and, for one that needs format 2 (like `codemagic-patch`, with its choices), its **frozen variant**,
  `template.v1.json` and `compose.v1.yaml`, copied from the last format-1 version. A folder that has only the
  frozen files is a template older Caravanas still offer and newer ones don't (`codemagic-patch-bitbucket`:
  `codemagic-patch` replaces it). A format-2 template with no frozen variant is simply not offered to the old.

`caravana template bundle` makes both and says which templates are in one only; `caravana template check`
checks both (a frozen variant too). Never edit a frozen variant to use format 2: that is what `template.json`
is for.

## Adding one

1. Make `templates/<name>/` with `template.json` and `compose.yaml`. Start from the nearest existing
   template. Write it from the upstream project's own documentation, and run the image to learn its
   health path: pick one that answers 200 without signing in (not a redirect).
2. Check it: `go run github.com/cosmic-chimps/caravana/cmd/caravana@main template check .` renders every
   template, for each combination of its choices (at most 64) and with each optional input empty and filled,
   through Caravana's own Compose and job translators.
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
uploads `catalog.v2.json`, `catalog.json` and `SHA256SUMS` (one line for each file) to a GitHub release.
Caravana asks for the latest release once a day: it fetches `SHA256SUMS` first, then `catalog.v2.json` (or
`catalog.json` when the release has no such line) only when its sum changed, checks the sum and every
template, and keeps the catalog if its version is newer than the one it has. A template written for a newer
Caravana than the one reading is listed as unavailable; the rest of the catalog is kept. Each Caravana release also
embeds a copy, so a new installation works offline. The owner can turn the daily check off in New app ›
From a template, and then Caravana makes no request.

## Licence

AGPL-3.0, as Caravana. See `LICENSE`.
