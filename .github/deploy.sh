#!/bin/bash
# Manual deploy trigger - pushes deploy tag to trigger GitHub Actions

if [ -z "$1" ]; then
    COMMIT=$(git rev-parse HEAD)
else
    COMMIT=$1
fi

echo "Deploying commit: $COMMIT"

git tag -d deploy 2>/dev/null
git push origin :refs/tags/deploy 2>/dev/null
git tag -a deploy -m "deploy" "$COMMIT"
git push origin refs/tags/deploy

echo "Deploy tag pushed. Monitor at GitHub Actions."
