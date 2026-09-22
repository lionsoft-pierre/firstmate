# Bitbucket Cloud pull request watch

Empirical record for the merge watch on Bitbucket Cloud, alongside the GitHub and GitLab ones.
Collected on 2026-09-22 against `https://api.bitbucket.org/2.0` with a real Atlassian account email and API token.

The only Bitbucket workspace available for this evidence is a private client repository, so its workspace, repository, pull request numbers, and commit hashes stay out of this record exactly as the private-instance GitLab runs do in [gitlab-merge-watch.md](gitlab-merge-watch.md).
What is recorded here is the API's shape, which is what the hermetic fixture in `tests/fm-pr-check-security.test.sh` reproduces and what the implementation depends on.
Placeholders below are `<workspace>`, `<repo>`, `<merged-pr>`, `<declined-pr>`, `<short>`, and `<full>`.

## Versions

```
$ curl --version | head -1
curl 8.7.1 (x86_64-apple-darwin26.0) libcurl/8.7.1 (SecureTransport) LibreSSL/3.3.6 zlib/1.2.12 nghttp2/1.69.0

$ bash --version | head -1
GNU bash, version 5.3.9(1)-release (aarch64-apple-darwin25.4.0)
```

## Why REST rather than a CLI

Bitbucket has no CLI in firstmate's toolchain, so there is no equivalent of `gh pr view` or `glab mr view` to read a state from.
REST 2.0 is read with `curl` instead, authenticated as `<email>:<api-token>` over HTTP basic auth.
The token is handed to `curl` in a configuration file on stdin rather than as `-u`, so it never appears in any process's argument list.

## Partial responses make the state unambiguous

A full pull request resource carries a `state` on the pull request and another `state` on each entry of `participants`, so a body read without a selector has more than one plausible reading of that key.
The API's own `fields` selector removes the ambiguity at the source:

```
$ # GET repositories/<workspace>/<repo>/pullrequests/<merged-pr>?fields=state
{"state": "MERGED"}
```

The poll additionally counts the occurrences of the key and refuses a body carrying more than one, so an unexpectedly larger response is silence rather than a state.
The observed states are `OPEN`, `MERGED`, `DECLINED`, and `SUPERSEDED`.
A live listing of one client repository returned merged and declined pull requests and no superseded ones, which is why `SUPERSEDED` is exercised only against the fixture.

## The pull request resource abbreviates the head

This is the non-obvious fact this record exists for.
`source.commit.hash` on the pull request resource is a 12-character abbreviation, not the full commit:

```
$ # GET repositories/<workspace>/<repo>/pullrequests/<merged-pr>?fields=source.commit.hash
{"source": {"commit": {"hash": "<short>"}}}

$ # where <short> is 12 characters
```

An abbreviation is ambiguous by construction and cannot be recorded as `pr_head=` or compared as a commit object, so it is resolved through that repository's own commit resource, which returns the full hash:

```
$ # GET repositories/<workspace>/<repo>/commit/<short>?fields=hash
{"hash": "<full>"}
```

`bin/fm-pr-lib.sh`'s `fm_pr_bitbucket_read_head` performs both reads and refuses a resolved hash that does not begin with the abbreviation it asked about, so a redirected or unexpected resource cannot substitute another commit.

## End to end: the published poll against live pull requests

Running `bin/fm-pr-poll.sh` the way the watcher does, against a genuinely merged pull request, a genuinely declined one, and with the credentials file pointed at a path that does not exist:

```
$ fm-pr-poll.sh --validated bitbucket https://bitbucket.org/<workspace>/<repo>/pull-requests/<merged-pr> bitbucket.org <workspace>/<repo> <merged-pr>
merged
$ fm-pr-poll.sh --validated bitbucket https://bitbucket.org/<workspace>/<repo>/pull-requests/<declined-pr> bitbucket.org <workspace>/<repo> <declined-pr>
declined
$ FM_BITBUCKET_CREDENTIALS=/nonexistent fm-pr-poll.sh --validated bitbucket https://bitbucket.org/<workspace>/<repo>/pull-requests/<merged-pr> bitbucket.org <workspace>/<repo> <merged-pr>
```

The merged pull request produces exactly one `merged` line, the declined one produces exactly one `declined` line, and an unusable credential produces nothing rather than a false merge.
`declined` and `superseded` are terminal too, so the watcher retires the poll on any of the three instead of asking forever; only `merged` records a merge outcome.

## What stays hermetic

Every other property is pinned without the network by `tests/fm-pr-check-security.test.sh`, `tests/fm-crew-state.test.sh`, and `tests/fm-teardown.test.sh`: URL parsing and its rejection matrix, the exact sidecar bytes, a doctored sidecar that no longer rebuilds its stored URL, the token reaching neither `curl`'s argument list nor the request URL, an absent `curl` and an absent or half-present credential pair, the arming refusals, the merge refusal, terminal retirement for `declined` and `superseded`, teardown's landed-work evidence from a merged Bitbucket head, and the reported pull request state never becoming a merge when the read fails.

## Merging is out of scope

`bin/fm-pr-merge.sh` refuses a Bitbucket URL before anything is recorded or armed.
Bitbucket pull requests merge through the Bitbucket side's own process; firstmate only watches for the result.
[`configuration.md`](configuration.md) owns `config/bitbucket-credentials` and the resolution order.
