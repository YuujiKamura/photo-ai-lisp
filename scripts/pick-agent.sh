#!/usr/bin/env sh
echo "=============================="
echo " photo-ai-lisp : pick an agent"
echo "=============================="
echo "  [1] claude"
echo "  [2] gemini"
echo "  [3] codex"
echo "  [Enter] skip (stay in shell)"
echo "=============================="
printf "> "
read CHOICE
case "$CHOICE" in
  1) claude ;;
  2) gemini ;;
  3) codex ;;
esac
