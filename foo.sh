#!/bin/bash

set -ex

OWNER=$1
REPOSITORY=$2
GITHUB_TOKEN=$3
pr=$4

API_URL=https://api.github.com

function gitHubCurl() {
  url=$1
  method=$2
  shift 2

  curl -ifsL --request "$method" \
       --url "$url" \
       --header "authorization: Bearer ${GITHUB_TOKEN}" \
       --header 'content-type: application/json' "$@"
}

function commentsUrl() {
  echo "$(issueUrl "${1}")/comments"
}

function issueUrl() {
  echo "$API_URL/repos/${OWNER}/${REPOSITORY}/issues/${1}"
}

gitHubCurl "$(commentsUrl "$pr")" POST --data '{ "body": "foo" }'
