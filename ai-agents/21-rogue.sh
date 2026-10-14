#!/usr/bin/env bash
# Run the rogue agent: real identity, no approval, every secret blocked.
exec kubectl -n agents exec -it deploy/rogue-agent -c agent -- python /app/rogue.py
