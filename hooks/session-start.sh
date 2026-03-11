#!/bin/sh
# Gate equip: only trigger full detection in project directories.
# Uses stat-level checks only (no rg, no directory traversal).
# The SUBAGENT-STOP guard in SKILL.md handles subagent sessions.

is_known_non_project() {
  case "$1" in
    "$HOME"|"$HOME/") return 0 ;;
    "$HOME/Documents"*|"$HOME/Downloads"*|"$HOME/Desktop"*) return 0 ;;
    "$HOME/Library"*|"$HOME/Pictures"*|"$HOME/Music"*|"$HOME/Movies"*) return 0 ;;
    /tmp*|/var/tmp*|/private/tmp*|/private/var/tmp*) return 0 ;;
  esac
  return 1
}

has_project_marker() {
  dir="$1"
  [ -d "$dir/.git" ] && return 0
  for f in Package.swift package.json go.mod Cargo.toml pyproject.toml setup.py \
           Makefile CMakeLists.txt pubspec.yaml Gemfile build.gradle build.gradle.kts; do
    [ -f "$dir/$f" ] && return 0
  done
  # Xcode projects and solutions (glob)
  ls "$dir"/*.xcodeproj "$dir"/*.xcworkspace "$dir"/*.sln >/dev/null 2>&1 && return 0
  return 1
}

cwd="$(pwd)"

if is_known_non_project "$cwd"; then
  echo "No project context detected at $cwd. Equip skipped. Re-invoke /cc-skills:equip after navigating to a project."
elif has_project_marker "$cwd"; then
  echo "[MAGIC KEYWORD: cc-skills:equip --auto]"
else
  # Unknown directory, not on blocklist — trigger equip (might be a project)
  echo "[MAGIC KEYWORD: cc-skills:equip --auto]"
fi
