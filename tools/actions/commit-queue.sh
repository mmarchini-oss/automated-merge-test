#!/bin/bash

set -xe

OWNER=$1
REPOSITORY=$2
GITHUB_TOKEN=$3
shift 3

API_URL=https://api.github.com
COMMIT_QUEUE_LABEL='commit-queue'
COMMIT_QUEUE_FAILED_LABEL='commit-queue-failed'

function issueUrl() {
  echo "$API_URL/repos/${OWNER}/${REPOSITORY}/issues/${1}"
}

function labelsUrl() {
  echo "$(issueUrl "${1}")/labels"
}

function commentsUrl() {
  echo "$(issueUrl "${1}")/comments"
}

function gitHubCurl() {
  url=$1
  method=$2
  shift 2

  curl -fsL --request "$method" \
       --url "$url" \
       --header "authorization: Bearer ${GITHUB_TOKEN}" \
       --header 'content-type: application/json' "$@"
}


# TODO(mmarchini): should this be set with whoever added the label for each PR?
git config --local user.email "action@github.com"
git config --local user.name "GitHub Action"

for pr in "$@"; do
  # Skip PR if CI was requested
  if gitHubCurl "$(labelsUrl "$pr")" GET | jq -e 'map(.name) | index("request-ci")'; then
    continue;
  fi

  # Skip PR if CI is still running
  if ncu-ci url "https://github.com/${OWNER}/${REPOSITORY}/pull/${pr}" 2>&1 | grep "^Result *PENDING"; then
    continue;
  fi

  # Delete the commit queue label
  gitHubCurl "$(labelsUrl "$pr")"/"$COMMIT_QUEUE_LABEL" DELETE

  commit=$(git rev-parse HEAD)
  git node land --yes "$pr" >output 2>&1 || echo "Failed to land #${pr}"

  # TODO(mmarchini): workaround for ncu not returning the expected status code,
  # if the "Landed in..." message was not on the output we assume land failed
  if ! tail -n 10 output | grep '. Post "Landed in .*/pull/'"${pr}"; then
    git node land --abort --yes

    gitHubCurl "$(labelsUrl "$pr")" POST --data '{"labels": ["'"${COMMIT_QUEUE_FAILED_LABEL}"'"]}'

    jq -n --arg content "<details><summary>Commit Queue failed</summary><pre>$(cat output)</pre></details>" '{body: $content}' > output.json

    gitHubCurl "$(commentsUrl "$pr")" POST --data @output.json

    rm output output.json;
  else
    rm output;
    git push origin master;

    gitHubCurl "$(commentsUrl "$pr")" POST --data '{"body": "Landed in '"$(git rev-parse HEAD)"'"}'

    gitHubCurl "$(issueUrl "$pr")" PATCH --data '{"state": "closed"}'
  fi
done;
