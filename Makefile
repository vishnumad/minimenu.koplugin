MISE := $(if $(shell command -v mise 2>/dev/null),mise exec --,)

.PHONY: check lint fmt fmt-check test integration release

check: lint fmt-check test

lint:
	@log=$$(mktemp -d); \
	$(MISE) lua-language-server --check=. --checklevel=Hint --check_format=pretty --logpath="$$log" > "$$log/out"; \
	status=$$?; tr '\r' '\n' < "$$log/out" | grep -v -E -e '^ *$$' -e '^ *[>=]+ *[0-9]+/[0-9]+( \[.*\])? *$$' -e '^Initializing'; \
	rm -rf "$$log"; exit $$status

fmt:
	$(MISE) stylua .

fmt-check:
	$(MISE) stylua --check .

test:
	busted

integration:
	@test -n "$(KOREADER_DIR)" || { echo "set KOREADER_DIR to the emulator koreader directory"; exit 2; }
	KOREADER_DIR=$(KOREADER_DIR) KO_PLUGINS_DISABLED=$(KO_PLUGINS_DISABLED) timeout 600 spec/integration/run.sh

release:
	@echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$$' || { echo "usage: make release VERSION=x.y.z"; exit 2; }
	@test -z "$$(git status --porcelain)" || { echo "commit or stash your changes first"; exit 1; }
	@test "$$(git rev-parse --abbrev-ref HEAD)" = master || { echo "releases are made from master"; exit 1; }
	@! git rev-parse -q --verify "refs/tags/v$(VERSION)" >/dev/null || { echo "v$(VERSION) already exists"; exit 1; }
	@$(MAKE) check
	sed -E -i.bak 's/^( *version = )"[^"]*"/\1"$(VERSION)"/' _meta.lua && rm -f _meta.lua.bak
	git commit -q -m "Release v$(VERSION)" _meta.lua
	git tag -a "v$(VERSION)" -m "v$(VERSION)"
	@echo "Now push the release: git push origin master v$(VERSION)"
