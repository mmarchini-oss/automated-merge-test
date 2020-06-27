#!/bin/bash

set -xe

OWNER=$1 # mmarchini-oss
REPOSITORY=$2 # automated-merge-test
COMMIT_QUEUE_LABEL=$3 # automated-merge-test
COMMIT_QUEUE_FAILED_LABEL=$4 # automated-merge-test
GH_USER_NAME=$5 # secrets.GH_USER_NAME
GH_USER_TOKEN=$6 # secrets.GH_USER_TOKEN
GITHUB_ACTOR=$7 # secrets.GITHUB_ACTOR
GITHUB_TOKEN=$8 # secrets.GITHUB_TOKEN
JENKINS_TOKEN=$9 # secrets.JENKINS_TOKEN
shift 9

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


npm install -g 'https://github.com/mmarchini/node-core-utils#commit-queue-branch'

# TODO(mmarchini): should this be set with whoever added the label for each PR?
git config --local user.email "action@github.com"
git config --local user.name "GitHub Action"

ncu-config set branch master
ncu-config set upstream origin

ncu-config set username ${GH_USER_NAME}
ncu-config set token ${GH_USER_TOKEN}
ncu-config set jenkins_token ${JENKINS_TOKEN}

# ncu-config set repo "$REPOSITORY"
# ncu-config set owner "$OWNER"

remote_repo="https://${GITHUB_ACTOR}:${GITHUB_TOKEN}@github.com/${OWNER}/${REPOSITORY}.git"

for pr in "$@"; do
  curl -sL --request DELETE \
       --url "$(labelsUrl "$pr")"/"$COMMIT_QUEUE_LABEL" \
       --header "authorization: Bearer ${GITHUB_TOKEN}" \
       --header 'content-type: application/json'

  commit=$(git rev-parse HEAD)
  git node land --yes "$pr" >output 2>&1 || git node land --abort --yes

  # TODO(mmarchini): workaround for ncu not returning the expected status code,
  # if the HEAD commit didn't change it means git node land failed
  if [ "$commit" == "$(git rev-parse HEAD)" ]; then
    # Do we need to reset?
    curl -sL --request PUT \
       --url "$(labelsUrl "$pr")" \
       --header "authorization: Bearer ${GITHUB_TOKEN}" \
       --header 'content-type: application/json' \
       --data '{"labels": ["'"${COMMIT_QUEUE_FAILED_LABEL}"'"]}'

    jq -n --arg content "<details><summary>Commit Queue failed</summary><pre>$(cat output)</pre></details>" '{body: $content}' > output.json

    curl -sL --request POST \
       --url "$(commentsUrl "$pr")" \
       --header "authorization: Bearer ${GITHUB_TOKEN}" \
       --header 'content-type: application/json' \
       --data @output.json

    rm output output.json;
  else
    rm output;
    git push "${remote_repo}" HEAD:master

    curl -sL --request POST \
       --url "$(commentsUrl "$pr")" \
       --header "authorization: Bearer ${GITHUB_TOKEN}" \
       --header 'content-type: application/json' \
       --data '{"body": "Landed in '"$(git rev-parse HEAD)"'"}'

    curl -sL --request PATCH \
       --url "$(issueUrl "$pr")" \
       --header "authorization: Bearer ${GITHUB_TOKEN}" \
       --header 'content-type: application/json' \
       --data '{"status": "closed"}'
  fi
done;
