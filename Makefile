MISE := $(if $(shell command -v mise 2>/dev/null),mise exec --,)

.PHONY: check lint fmt fmt-check test integration

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
