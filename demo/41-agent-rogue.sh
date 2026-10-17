#!/usr/bin/env bash
# The rogue agent: a real identity (its own service account), but no permit. Everything denied.
exec kubectl -n agents exec -it deploy/rogue-agent -c agent -- python /app/rogue.py
