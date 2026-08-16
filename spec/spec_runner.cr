# Single entry point that pulls in every spec file. Used for the coverage binary
# (`scripts/coverage.sh`) and for `crystal tool unreachable`.
#
# The directories are named one by one rather than globbed with `./**`, which would also pull in
# `spec/fixtures/compile_errors`, whose whole point is that it does not compile.
require "./spec_helper"
require "./aws-record/**"
require "./integration/**"
