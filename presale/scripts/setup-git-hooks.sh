#!/bin/bash

HOOKS_DIR=$(git rev-parse --show-toplevel)/.git/hooks

echo "🔧 Installing pre-commit hook..."

cp scripts/pre-commit "$HOOKS_DIR/pre-commit"
chmod +x "$HOOKS_DIR/pre-commit"

echo "✅ Pre-commit hook installed successfully."
