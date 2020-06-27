# Node.js Commit Queue Proof-of-Concept

This repository contains a proof-of-concept Commit Queue for the Node.js
project.

## Overview

From a high-level, the Commit Queue works as follow:

1. Collaborators will add `commit-queue` label to Pull Reuqests ready to land
2. Every five minutes the queue will do the followith with each Pull Request with the label:
  1. Check if the PR also has a `request-ci` label (if it has, skip this PR since it's pending a CI run)
  2. Check if the last Jenkins CI is finished running (if it is not, skip this PR)
  3. Remove the `commit-queue` label
  4. Run `git node land <pr>`
  5. If it fails:
    1. Abort `git node land` session
    2. Add `commit-queue-failed` label to the PR
    3. Leave a comment on the PR with the output from `git node land`
    4. Skip next steps, go to next PR in the queue
  6. If it succeeds:
    1. Push the changes to nodejs/node
    2. Leave a comment on the PR with `Landed in ...`
    3. Close the PR
    4. Go to next PR in the queue


## Implementation

The [action](/.github/workflows/commit_queue.yml) will run on scheduler events
every five minutes. Using the scheduler is necessary to work around GitHub
limitations on pull requests from forks (no access to secrets, which prevents
usage of node-core-utils, and GITHUB_TOKEN is read-only, which prevents us from
pushing). Five minutes is the smallest number accepted by the scheduler. The
scheduler is not guaranteed to run every five minutes, it might take longer
between runs.

`octokit/graphql-action` is used to fetch all Pull Requests with the
`commit-queue` label. The output is a JSON payload, so `jq` is used to turn
that into a list of PR ids we can pass as arguments to
[land-stuff.sh](./land-stuff.sh).

[land-stuff.sh](./land-stuff.sh) receives many positional arguments:

1. The repository owner
2. The repository name
3. The commit queue label
4. Label to be used if landing fails
5. GitHub username to be used by node-core-utils
5. GitHub token of the user above to be used by node-core-utils
7. The Action actor (`${{ github.actor }}`)
8. The Action GITHUB_TOKEN
9. Jenkins access token for the GitHub user mentioned above
10. Every positional argument starting at this one will be a Pull Reuqest ID of
    a Pull Request with commit-queue set.

A GitHub personal token is necessary for node-core-utils. The reasoning is
still to be understood, but it seems like the GITHUB_TOKEN lacks some
permission on the GraphQL API, even if it is running on a scheduler context.
The personal token only needs read permission for public repositories, we can
use the GITHUB_TOKEN for write operations. Jenkins token is required to check
CI status.

> Side note: it is possible to reduce the number of arguments on this script
> by keeping the labels name hardcoded in the script, and by setting up
> node-core-utils outside the script. This would get us to 4 required
> arguments.

First thing the script does is configure git and node-core-utils with
appropriate tokens. After that, it will iterate over the pull requests.
`ncu-ci` is used to check if the last CI is still pending. The PR is skipped if
CI is pending. No other CI validation is done here since `git node land` knows
how to handle red CIs.

Using `curl` and the `GITHUB_TOKEN` to communicate with the GitHub API, the
script removes the `commit-queue` label. It then runs `git node land`,
forwarding stdout and stderr to a file. If any errors happens, we run 
`git node land --abort`, and then we use `curl` to add `commit-queue-failed`
label to the PR, as well as sending a comment with the output of 
`git node land`.

If no errors happen during `git node land`, the script will use the 
`GITHUB_TOKEN` to push the changes to `master`, and then will use `curl` to
leave a `Landed in ...` comment in the PR, and then will close it. Iteration
continues until all PRs have done the steps above.

## TODO

### Required

  - [ ] Keep on `commit-queue` if:
    - [ ] `request-ci` label is also present
    - [ ] Last Jenkins CI is pending
  - [ ] Properly validate if `git node land` worked by checking `output`
  - [ ] Fail if PR has more than one commit
  - [ ] Check if the `push` event is happening when landing via `commit-queue`
  - [ ] `git node land --strict` to require Jenkins Green or Yellow CI

### Optional

#### Easy manual revert via label

An easy way to revert is a good plus for the project, but is not explicitly
required because the Action lands PRs just like collaborators do today. It
would only make sense to have revert as something required if: a) having
the commit queue will **drastically** increase our average number of landed
commits per day; or b) collaborators never landed multiple PRs in a short span
of time (which happens frequently).

The revert queue should be implemented as a separate action, since it needs a
different GraphQL query to fetch the PRs. It could even be implemented before,
alongside or after the commit queue, so we have flexibility.

Here's a checklist to implement the revert queue:

  - [ ] `revert-queue` label
  - [ ] Create a revert PR for PRs with single commit
  - [ ] Add label `request-ci`
  - [ ] Add label `commit-queue`
  - [ ] Ping original PR author and collaborator who requsted revert

#### Miscellaneous / Future Work

  - [ ] Skip if GitHub Actions are pending
  - [ ] Fail if GitHub Actions failed
  - [ ] `git node land` to add Commit-Queueu-By metatada, or to use the user
        who added to the queue as committer
  - [ ] Should this be implemented in JavaScript instead of bash?
  - [ ] Should this live in a separate repository we can reference via `use`?
  - [ ] `git node land --automerge` so it tried to merge `fixup!` and `squash!`
        commits.
  - [ ] Which label is better: `commit-queue-failed` or 
        `manual-landing-required`?

## Collaborators and TSC list

Required for NCU, so minimal lists created for this repo

### TSC (Technical Steering Committee)

* [mmarchini](https://github.com/mmarchini) -
**mmarchini** &lt;me@mmarchini.me&gt;

### TSC Emeriti

* [ghost](https://github.com/ghost) -
**ghost** &lt;ghost@ghost.ghost&gt;

### Collaborators

* [mmarchini](https://github.com/mmarchini) -
**mmarchini** &lt;me@mmarchini.me&gt;

### Collaborator Emeriti

* [ghost](https://github.com/ghost) -
**ghost** &lt;ghost@ghost.ghost&gt;
