#!/bin/bash
git remote add upstream https://github.com/christopherkarani/Swarm.git 2>/dev/null
git remote set-url --push upstream DISABLE
echo "Upstream configured (pull-only from christopherkarani/Swarm)"
