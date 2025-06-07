RELEASE_MODE=ReleaseSmall
INSTALL_PREFIX=$(CURDIR)/install
ZIG=zig

# Run Znippets on its own codebase
run:
	$(ZIG) build run -- README.md src

# Run unit tests
test:
	$(ZIG) build test
	$(PY) -m unittest etc/release_changelog.py
	$(PY) -m unittest etc/validate_semver.py

# Install the release build of Znippets into INSTALL_PREFIX
install:
	$(ZIG) build --prefix $(INSTALL_PREFIX) -Doptimize=$(RELEASE_MODE)

# Format source code
fmt:
	$(ZIG) fmt src
	$(ZIG) fmt build.zig
	$(PY) -m black etc/*.py

# Extract the changelog for the next release from the global changelog
# This corresponds to the first section in CHANGELOG.md, with the main header removed
release_changelog.md: CHANGELOG.md etc/release_changelog.py
	$(PY) etc/release_changelog.py CHANGELOG.md > release_changelog.md

# Validate that the ${VERSION} variable complies to semantic versioning
validate_semver:
	$(PY) etc/validate_semver.py $(VERSION)

include etc/help.mk
include etc/py.mk