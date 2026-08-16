# Single entry point that pulls in every spec file. Used for the coverage binary
# (`scripts/coverage.sh`) and for `crystal tool unreachable`.
require "./spec_helper"
require "./**"
