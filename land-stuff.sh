#!/bin/bash

set -xe

echo starting arguments: $@

OWNER=$1 # mmarchini-oss
REPOSITORY=$2 # automated-merge-test
COMMIT_QUEUE_LABEL=$3 # automated-merge-test
COMMIT_QUEUE_FAILED_LABEL=$4 # automated-merge-test
GITHUB_ACTOR=$5 # env.GITHUB_ACTOR
GITHUB_TOKEN=$6 # secrets.GITHUB_TOKEN
shift 6

echo parsed arguments: $@

API_URL=https://api.github.com

function issueUrl() {
  echo "$API_URL/repos/${OWNER}/${REPOSITORY}/issues/${1}"
}

function labelsUrl() {
  echo "$(issueUrl "${1}")/labels"
}

function commentsUrl() {
  echo "$(issueUrl "${1}")/comments"
}


npm install -g node-core-utils

# TODO(mmarchini): should this be set with whoever added the label for each PR?
git config --local user.email "action@github.com"
git config --local user.name "GitHub Action"

ncu-config --global set readme "$(pwd)"/README.md
ncu-config set branch master
ncu-config set upstream origin

ncu-config set repo "$REPOSITORY"
ncu-config set owner "$OWNER"

remote_repo="https://${GITHUB_ACTOR}:${GITHUB_TOKEN}@github.com/${REPOSITORY}.git"

for pr in "$@"; do
  echo curl --request DELETE \
       --url "$(labelsUrl "$pr")"/"$COMMIT_QUEUE_LABEL" \
       --header "authorization: Bearer ${GITHUB_TOKEN}" \
       --header 'content-type: application/json'

  success=yes
  git node land --yes "$pr" || success=no

  if [ "$success" == "no" ]; then
    # Do we need to reset?
    echo curl --request PUT \
       --url "$(labelsUrl "$pr")" \
       --header "authorization: Bearer ${GITHUB_TOKEN}" \
       --header 'content-type: application/json' \
       --data '{"labels": ["'"${COMMIT_QUEUE_FAILED_LABEL}"'"]}'
  else
    echo git push "${remote_repo}" HEAD:master

    echo curl --request POST \
       --url "$(commentsUrl "$pr")" \
       --header "authorization: Bearer ${GITHUB_TOKEN}" \
       --header 'content-type: application/json' \
       --data '{"body": "Landed in '"$(git rev-parse HEAD)"'"}'

    echo curl --request PATCH \
       --url "$(commentsUrl "$pr")" \
       --header "authorization: Bearer ${GITHUB_TOKEN}" \
       --header 'content-type: application/json' \
       --data '{"status": "closed"}'
  fi
done;
