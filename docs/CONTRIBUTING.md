# Contributing to AmniX-Finance

## Pre-commit Hooks Setup (REQUIRED)

Install pre-commit:
  pip install pre-commit
  pre-commit install
  pre-commit run --all-files

## Commit Format

type(scope): summary

Types: fix, feat, refactor, chore, docs, ci, perf

## Security

Never commit secrets. Always use Vault.
Run gitleaks before pushing.
