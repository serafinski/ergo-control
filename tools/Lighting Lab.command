#!/bin/zsh
cd "${0:A:h:h}" || exit 1
python3 tools/lighting_lab.py interactive
result=$?
print
read '?Press Return to close…'
exit "$result"
