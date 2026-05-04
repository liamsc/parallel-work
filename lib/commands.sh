#!/usr/bin/env bash
# User-facing commands — each file in commands/ defines one or two related commands.

_PWORK_COMMANDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")/commands" && pwd)"

source "$_PWORK_COMMANDS_DIR/init.sh"
source "$_PWORK_COMMANDS_DIR/cd.sh"
source "$_PWORK_COMMANDS_DIR/pw.sh"
source "$_PWORK_COMMANDS_DIR/sync.sh"
source "$_PWORK_COMMANDS_DIR/status.sh"
source "$_PWORK_COMMANDS_DIR/branches.sh"
source "$_PWORK_COMMANDS_DIR/new.sh"
source "$_PWORK_COMMANDS_DIR/clean.sh"
source "$_PWORK_COMMANDS_DIR/resume.sh"
source "$_PWORK_COMMANDS_DIR/g-resume.sh"
source "$_PWORK_COMMANDS_DIR/setup.sh"
source "$_PWORK_COMMANDS_DIR/update.sh"
source "$_PWORK_COMMANDS_DIR/version.sh"
source "$_PWORK_COMMANDS_DIR/list.sh"
