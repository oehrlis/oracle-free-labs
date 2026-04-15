# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: Makefile
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.04.15
# Version....: v1.0.0
# Purpose....: Build, lint, lab management, and release targets for oracle-free-labs
# Notes......: Config via .env (overrides). Use 'make help' for targets.
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help
MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

# Ensure Homebrew-installed tools are found regardless of caller's PATH
PATH := /opt/homebrew/bin:/usr/local/bin:$(PATH)
export PATH

# -- Colors --------------------------------------------------------------------
COLOR_RESET  := \033[0m
COLOR_BOLD   := \033[1m
COLOR_GREEN  := \033[32m
COLOR_YELLOW := \033[33m
COLOR_BLUE   := \033[34m
COLOR_RED    := \033[31m

# -- Project -------------------------------------------------------------------
PROJECT_NAME   := oracle-free-labs
VERSION        := $(shell cat VERSION 2>/dev/null || echo "0.0.0")
ARTEFACTS_DIR  := artefacts

# -- Directories ---------------------------------------------------------------
SCRIPT_DIR := scripts
BUILD_DIR  := build
DOC_DIR    := doc

# -- Services ------------------------------------------------------------------
SERVICES := cdbfree labdb odbrepo odbseed odbdemo odbenc

# -- Scripts -------------------------------------------------------------------
PDF_SCRIPT  := $(SCRIPT_DIR)/generate_pdf.sh
BUMP_SCRIPT := $(SCRIPT_DIR)/bump_version.sh

# -- Docker variables ----------------------------------------------------------
-include .env
BUILD_IMAGE ?= oracle-free-labs:latest
REGISTRY    ?= ghcr.io/oehrlis

# -- Tool detection ------------------------------------------------------------
SHELLCHECK   := $(shell PATH="$(PATH)" command -v shellcheck 2>/dev/null)
SHFMT        := $(shell PATH="$(PATH)" command -v shfmt 2>/dev/null)
MARKDOWNLINT := $(shell PATH="$(PATH)" command -v markdownlint 2>/dev/null || \
                         PATH="$(PATH)" command -v markdownlint-cli 2>/dev/null)
YAMLLINT     := $(shell PATH="$(PATH)" command -v yamllint 2>/dev/null)
GIT          := $(shell PATH="$(PATH)" command -v git 2>/dev/null)
DOCKER       := $(shell PATH="$(PATH)" command -v docker 2>/dev/null)

# ==============================================================================
# Help
# ==============================================================================

.PHONY: help
help: ## Show this help message
	@echo -e "$(COLOR_BOLD)$(PROJECT_NAME) Makefile$(COLOR_RESET)"
	@echo "Version: $(VERSION)"
	@echo ""
	@echo "Release workflow:"
	@echo "  Patch : make release                 # bump patch -> commit -> tag"
	@echo "  Minor : make version-bump-minor && make tag"
	@echo "  Major : make version-bump-major && make tag"
	@echo "  After : git push origin main && git push origin v$(VERSION)"
	@echo ""
	@echo -e "$(COLOR_BOLD)Lint and Format:$(COLOR_RESET)"
	@grep -hE '^(lint|fmt)[a-zA-Z_-]*:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_GREEN)%-28s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)Lab Services (generic):$(COLOR_RESET)"
	@grep -hE '^(up|down|ps|logs|bash|sql|reset):.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_GREEN)%-28s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)Lab: cdbfree (plain Oracle 26ai Free):$(COLOR_RESET)"
	@grep -hE '^(up|down|logs|bash|sql|reset)-cdbfree:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_GREEN)%-28s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)Lab: labdb (empty DB for labs):$(COLOR_RESET)"
	@grep -hE '^(up|down|logs|bash|sql|reset)-labdb:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_GREEN)%-28s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)Lab: odbrepo (EA repository via SQL scripts):$(COLOR_RESET)"
	@grep -hE '^(up|down|logs|bash|sql|reset)-odbrepo:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_GREEN)%-28s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)Lab: odbseed (EA repository from PDB archive):$(COLOR_RESET)"
	@grep -hE '^(up|down|logs|bash|sql|reset)-odbseed:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_GREEN)%-28s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)Lab: odbdemo (complex EA demo from PDB archive):$(COLOR_RESET)"
	@grep -hE '^(up|down|logs|bash|sql|reset)-odbdemo:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_GREEN)%-28s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)Lab: odbenc (EA demo with TDE via SQL scripts):$(COLOR_RESET)"
	@grep -hE '^(up|down|logs|bash|sql|reset)-odbenc:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_GREEN)%-28s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)Build:$(COLOR_RESET)"
	@grep -hE '^(build)[a-zA-Z_-]*:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_GREEN)%-28s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)Documentation:$(COLOR_RESET)"
	@grep -hE '^(doc|pdf)[a-zA-Z_-]*:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_GREEN)%-28s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)Cleanup:$(COLOR_RESET)"
	@grep -hE '^clean[a-zA-Z_-]*:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_GREEN)%-28s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)Version Management:$(COLOR_RESET)"
	@grep -hE '^(version|check-version)[a-zA-Z_-]*:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_GREEN)%-28s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)Release Management:$(COLOR_RESET)"
	@grep -hE '^(tag|release):.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_GREEN)%-28s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(COLOR_BOLD)Info:$(COLOR_RESET)"
	@grep -hE '^status:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_GREEN)%-28s$(COLOR_RESET) %s\n", $$1, $$2}'

# ==============================================================================
# Lint and Format
# ==============================================================================

.PHONY: lint
lint: lint-shell lint-yaml lint-markdown check-version ## Run all lint checks

.PHONY: lint-shell
lint-shell: ## Lint shell scripts with shellcheck
	@if [[ -z "$(SHELLCHECK)" ]]; then \
		echo "Error: shellcheck not found (install: brew install shellcheck)"; \
		exit 1; \
	fi
	@find "$(SCRIPT_DIR)" -type f -name "*.sh" -print0 | \
		xargs -0 "$(SHELLCHECK)" -x -S warning

.PHONY: fmt-shell
fmt-shell: ## Check shell script formatting with shfmt (diff only)
	@if [[ -z "$(SHFMT)" ]]; then \
		echo "Error: shfmt not found (install: brew install shfmt)"; \
		exit 1; \
	fi
	@find "$(SCRIPT_DIR)" -type f -name "*.sh" -print0 | \
		xargs -0 "$(SHFMT)" -d -i 4 -bn -ci -sr

.PHONY: fmt-shell-write
fmt-shell-write: ## Format shell scripts in-place with shfmt
	@if [[ -z "$(SHFMT)" ]]; then \
		echo "Error: shfmt not found (install: brew install shfmt)"; \
		exit 1; \
	fi
	@find "$(SCRIPT_DIR)" -type f -name "*.sh" -print0 | \
		xargs -0 "$(SHFMT)" -w -i 4 -bn -ci -sr
	@echo "✅ Shell scripts formatted"

.PHONY: lint-yaml
lint-yaml: ## Lint YAML files with yamllint
	@if [[ -z "$(YAMLLINT)" ]]; then \
		echo "Error: yamllint not found (install: pip install yamllint)"; \
		exit 1; \
	fi
	@find . -type f \( -name "*.yml" -o -name "*.yaml" \) \
		-not -path "./.git/*" \
		-not -path "./data/*" \
		-not -path "./node_modules/*" -print0 | \
		xargs -0 "$(YAMLLINT)"

.PHONY: lint-markdown
lint-markdown: ## Lint markdown files with markdownlint
	@if [[ -z "$(MARKDOWNLINT)" ]]; then \
		echo "Error: markdownlint not found (install: npm install -g markdownlint-cli)"; \
		exit 1; \
	fi
	@find . -type f -name "*.md" \
		-not -path "./.git/*" \
		-not -path "./data/*" \
		-not -path "./node_modules/*" -print0 | \
		xargs -0 "$(MARKDOWNLINT)"

# ==============================================================================
# Lab Services - Generic
# ==============================================================================

.PHONY: up
up: ## Start a service by profile: make up SERVICE=labdb
	@if [[ -z "$(SERVICE)" ]]; then \
		echo "Error: SERVICE is required. Example: make up SERVICE=labdb"; \
		echo "Available: $(SERVICES)"; \
		exit 1; \
	fi
	@if [[ ! -f ".env" ]]; then \
		echo "❌ .env not found. Run: cp .env.example .env"; \
		exit 1; \
	fi
	docker compose --profile "$(SERVICE)" up -d

.PHONY: down
down: ## Stop a service: make down SERVICE=labdb  (omit SERVICE to stop all)
	@if [[ -z "$(SERVICE)" ]]; then \
		echo -e "$(COLOR_BOLD)Stopping all services...$(COLOR_RESET)"; \
		for svc in $(SERVICES); do \
			echo -e "ℹ️  Stopping $$svc..."; \
			docker compose --profile "$$svc" down || true; \
		done; \
		echo "✅ All services stopped"; \
	else \
		docker compose --profile "$(SERVICE)" down; \
	fi

.PHONY: ps
ps: ## Show status of all running lab containers
	docker compose ps

.PHONY: logs
logs: ## Follow logs for a service: make logs SERVICE=labdb
	@if [[ -z "$(SERVICE)" ]]; then \
		echo "Error: SERVICE is required. Example: make logs SERVICE=labdb"; \
		exit 1; \
	fi
	docker compose logs -f "$(SERVICE)"

.PHONY: bash
bash: ## Open bash shell in a container: make bash SERVICE=labdb
	@if [[ -z "$(SERVICE)" ]]; then \
		echo "Error: SERVICE is required. Example: make bash SERVICE=labdb"; \
		exit 1; \
	fi
	docker compose exec "$(SERVICE)" bash

.PHONY: sql
sql: ## Open sqlplus in a container: make sql SERVICE=labdb
	@if [[ -z "$(SERVICE)" ]]; then \
		echo "Error: SERVICE is required. Example: make sql SERVICE=labdb"; \
		exit 1; \
	fi
	docker compose exec "$(SERVICE)" sqlplus / as sysdba

.PHONY: reset
reset: ## Full reset (destructive!): make reset SERVICE=labdb  (omit SERVICE to reset ALL)
	@if [[ -z "$(SERVICE)" ]]; then \
		read -rp "⚠️  This will destroy ALL data for ALL services. Continue? [y/N] " confirm; \
		[[ "$$confirm" == [yY] ]] || { echo "Aborted."; exit 1; }; \
		for svc in $(SERVICES); do \
			echo -e "ℹ️  Resetting $$svc..."; \
			docker compose --profile "$$svc" down -v || true; \
			rm -rf "data/$$svc/"; \
		done; \
		echo "✅ All services reset complete"; \
	else \
		read -rp "⚠️  This will destroy ALL data for service '$(SERVICE)'. Continue? [y/N] " confirm; \
		[[ "$$confirm" == [yY] ]] || { echo "Aborted."; exit 1; }; \
		docker compose --profile "$(SERVICE)" down -v; \
		rm -rf "data/$(SERVICE)/"; \
		echo "✅ Service $(SERVICE) reset complete"; \
	fi

# ==============================================================================
# Lab Services - Per Service (explicit targets for autocomplete)
# ==============================================================================

# -- cdbfree -------------------------------------------------------------------
.PHONY: up-cdbfree
up-cdbfree: ## Start cdbfree (plain Oracle 26ai Free)
	$(MAKE) --no-print-directory up SERVICE=cdbfree

.PHONY: down-cdbfree
down-cdbfree: ## Stop cdbfree
	$(MAKE) --no-print-directory down SERVICE=cdbfree

.PHONY: logs-cdbfree
logs-cdbfree: ## Follow logs for cdbfree
	$(MAKE) --no-print-directory logs SERVICE=cdbfree

.PHONY: bash-cdbfree
bash-cdbfree: ## Open bash shell in cdbfree
	$(MAKE) --no-print-directory bash SERVICE=cdbfree

.PHONY: sql-cdbfree
sql-cdbfree: ## Open sqlplus in cdbfree
	$(MAKE) --no-print-directory sql SERVICE=cdbfree

.PHONY: reset-cdbfree
reset-cdbfree: ## Full reset of cdbfree (destructive!)
	$(MAKE) --no-print-directory reset SERVICE=cdbfree

# -- labdb ---------------------------------------------------------------------
.PHONY: up-labdb
up-labdb: ## Start labdb (empty DB for labs)
	$(MAKE) --no-print-directory up SERVICE=labdb

.PHONY: down-labdb
down-labdb: ## Stop labdb
	$(MAKE) --no-print-directory down SERVICE=labdb

.PHONY: logs-labdb
logs-labdb: ## Follow logs for labdb
	$(MAKE) --no-print-directory logs SERVICE=labdb

.PHONY: bash-labdb
bash-labdb: ## Open bash shell in labdb
	$(MAKE) --no-print-directory bash SERVICE=labdb

.PHONY: sql-labdb
sql-labdb: ## Open sqlplus in labdb
	$(MAKE) --no-print-directory sql SERVICE=labdb

.PHONY: reset-labdb
reset-labdb: ## Full reset of labdb (destructive!)
	$(MAKE) --no-print-directory reset SERVICE=labdb

# -- odbrepo -------------------------------------------------------------------
.PHONY: up-odbrepo
up-odbrepo: ## Start odbrepo (EA repository via SQL scripts)
	$(MAKE) --no-print-directory up SERVICE=odbrepo

.PHONY: down-odbrepo
down-odbrepo: ## Stop odbrepo
	$(MAKE) --no-print-directory down SERVICE=odbrepo

.PHONY: logs-odbrepo
logs-odbrepo: ## Follow logs for odbrepo
	$(MAKE) --no-print-directory logs SERVICE=odbrepo

.PHONY: bash-odbrepo
bash-odbrepo: ## Open bash shell in odbrepo
	$(MAKE) --no-print-directory bash SERVICE=odbrepo

.PHONY: sql-odbrepo
sql-odbrepo: ## Open sqlplus in odbrepo
	$(MAKE) --no-print-directory sql SERVICE=odbrepo

.PHONY: reset-odbrepo
reset-odbrepo: ## Full reset of odbrepo (destructive!)
	$(MAKE) --no-print-directory reset SERVICE=odbrepo

# -- odbseed -------------------------------------------------------------------
.PHONY: up-odbseed
up-odbseed: ## Start odbseed (EA repository from PDB archive)
	$(MAKE) --no-print-directory up SERVICE=odbseed

.PHONY: down-odbseed
down-odbseed: ## Stop odbseed
	$(MAKE) --no-print-directory down SERVICE=odbseed

.PHONY: logs-odbseed
logs-odbseed: ## Follow logs for odbseed
	$(MAKE) --no-print-directory logs SERVICE=odbseed

.PHONY: bash-odbseed
bash-odbseed: ## Open bash shell in odbseed
	$(MAKE) --no-print-directory bash SERVICE=odbseed

.PHONY: sql-odbseed
sql-odbseed: ## Open sqlplus in odbseed
	$(MAKE) --no-print-directory sql SERVICE=odbseed

.PHONY: reset-odbseed
reset-odbseed: ## Full reset of odbseed (destructive!)
	$(MAKE) --no-print-directory reset SERVICE=odbseed

# -- odbdemo -------------------------------------------------------------------
.PHONY: up-odbdemo
up-odbdemo: ## Start odbdemo (complex EA demo from PDB archive)
	$(MAKE) --no-print-directory up SERVICE=odbdemo

.PHONY: down-odbdemo
down-odbdemo: ## Stop odbdemo
	$(MAKE) --no-print-directory down SERVICE=odbdemo

.PHONY: logs-odbdemo
logs-odbdemo: ## Follow logs for odbdemo
	$(MAKE) --no-print-directory logs SERVICE=odbdemo

.PHONY: bash-odbdemo
bash-odbdemo: ## Open bash shell in odbdemo
	$(MAKE) --no-print-directory bash SERVICE=odbdemo

.PHONY: sql-odbdemo
sql-odbdemo: ## Open sqlplus in odbdemo
	$(MAKE) --no-print-directory sql SERVICE=odbdemo

.PHONY: reset-odbdemo
reset-odbdemo: ## Full reset of odbdemo (destructive!)
	$(MAKE) --no-print-directory reset SERVICE=odbdemo

# -- odbenc --------------------------------------------------------------------
.PHONY: up-odbenc
up-odbenc: ## Start odbenc (EA demo with TDE via SQL scripts)
	$(MAKE) --no-print-directory up SERVICE=odbenc

.PHONY: down-odbenc
down-odbenc: ## Stop odbenc
	$(MAKE) --no-print-directory down SERVICE=odbenc

.PHONY: logs-odbenc
logs-odbenc: ## Follow logs for odbenc
	$(MAKE) --no-print-directory logs SERVICE=odbenc

.PHONY: bash-odbenc
bash-odbenc: ## Open bash shell in odbenc
	$(MAKE) --no-print-directory bash SERVICE=odbenc

.PHONY: sql-odbenc
sql-odbenc: ## Open sqlplus in odbenc
	$(MAKE) --no-print-directory sql SERVICE=odbenc

.PHONY: reset-odbenc
reset-odbenc: ## Full reset of odbenc (destructive!)
	$(MAKE) --no-print-directory reset SERVICE=odbenc

# ==============================================================================
# Build
# ==============================================================================

.PHONY: build
build: ## Build extended Oracle Free image from build/Dockerfile
	@if [[ -z "$(DOCKER)" ]]; then \
		echo "Error: docker not found in PATH"; exit 1; \
	fi
	@if [[ ! -f "$(BUILD_DIR)/Dockerfile" ]]; then \
		echo "Error: $(BUILD_DIR)/Dockerfile not found"; exit 1; \
	fi
	docker build -t "$(BUILD_IMAGE)" -f "$(BUILD_DIR)/Dockerfile" "$(BUILD_DIR)"
	@echo "✅ Image built: $(BUILD_IMAGE)"

.PHONY: build-push
build-push: build ## Build and push extended image to registry
	docker tag "$(BUILD_IMAGE)" "$(REGISTRY)/$(BUILD_IMAGE)"
	docker push "$(REGISTRY)/$(BUILD_IMAGE)"
	@echo "✅ Image pushed: $(REGISTRY)/$(BUILD_IMAGE)"

# ==============================================================================
# Documentation
# ==============================================================================

.PHONY: doc
doc: ## Build PDF documentation (DOCNAME=<name> required)
	@if [[ -z "$(DOCKER)" ]]; then \
		echo "Error: docker not found in PATH"; exit 1; \
	fi
	@if [[ -z "$(DOCNAME)" ]]; then \
		echo "Error: DOCNAME is required. Example: make doc DOCNAME=DOAG2025-Oracle-Container-Labs_Manuskript_v1.0"; \
		exit 1; \
	fi
	@"$(PDF_SCRIPT)" "$(DOCNAME)"

.PHONY: pdf
pdf: doc ## Alias for doc

# ==============================================================================
# Cleanup
# ==============================================================================

.PHONY: clean
clean: ## Remove temporary and cached files (safe, no DB data removed)
	@find . -type f -name "*.tmp" -not -path "./.git/*" -delete 2>/dev/null || true
	@find . -type f -name "*.bak" -not -path "./.git/*" -delete 2>/dev/null || true
	@find . -type d -name "__pycache__" -not -path "./.git/*" -exec rm -rf {} + 2>/dev/null || true
	@echo "✅ Clean complete"

# ==============================================================================
# Version Management
# ==============================================================================

.PHONY: version
version: ## Show current version from VERSION file
	@echo "$(VERSION)"

.PHONY: check-version
check-version: ## Validate semantic version format in VERSION file
	@grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' VERSION \
		&& echo "Version is valid: $(VERSION)" \
		|| (echo "Invalid version format in VERSION"; exit 1)

.PHONY: version-bump-patch
version-bump-patch: ## Bump patch (0.0.X), update CHANGELOG, commit
	@"$(BUMP_SCRIPT)" patch; \
	version="$$(cat VERSION)"; \
	$(GIT) add VERSION CHANGELOG.md; \
	$(GIT) commit -m "chore: bump version to v$$version"; \
	echo "✅ Bumped and committed: v$$version"; \
	echo "   Next: make tag"

.PHONY: version-bump-minor
version-bump-minor: ## Bump minor (0.X.0), update CHANGELOG, commit
	@"$(BUMP_SCRIPT)" minor; \
	version="$$(cat VERSION)"; \
	$(GIT) add VERSION CHANGELOG.md; \
	$(GIT) commit -m "chore: bump version to v$$version"; \
	echo "✅ Bumped and committed: v$$version"; \
	echo "   Next: make tag"

.PHONY: version-bump-major
version-bump-major: ## Bump major (X.0.0), update CHANGELOG, commit
	@"$(BUMP_SCRIPT)" major; \
	version="$$(cat VERSION)"; \
	$(GIT) add VERSION CHANGELOG.md; \
	$(GIT) commit -m "chore: bump version to v$$version"; \
	echo "✅ Bumped and committed: v$$version"; \
	echo "   Next: make tag"

# ==============================================================================
# Release Management
# ==============================================================================

.PHONY: tag
tag: ## Create git tag from VERSION (guards: clean tree + VERSION committed)
	@if [[ -z "$(GIT)" ]]; then echo "Error: git not found in PATH"; exit 1; fi; \
	version="$$(cat VERSION)"; \
	tag="v$$version"; \
	if ! $(GIT) diff --quiet HEAD 2>/dev/null; then \
		echo "❌ Working tree is dirty - commit all changes before tagging:"; \
		$(GIT) status -sb; \
		exit 1; \
	fi; \
	committed="$$($(GIT) show HEAD:VERSION 2>/dev/null | tr -d '[:space:]')"; \
	if [[ "$$committed" != "$$version" ]]; then \
		echo "❌ VERSION ($$version) not yet committed (HEAD has: $$committed)"; \
		echo "   Run: git add VERSION CHANGELOG.md && git commit -m 'chore: bump version to v$$version'"; \
		exit 1; \
	fi; \
	if $(GIT) rev-parse "$$tag" >/dev/null 2>&1; then \
		echo "❌ Tag $$tag already exists"; \
		exit 1; \
	fi; \
	$(GIT) tag -a "$$tag" -m "Release $$tag"; \
	echo "✅ Created tag $$tag"; \
	echo ""; \
	echo "   Push manually:"; \
	echo "     git push origin main"; \
	echo "     git push origin $$tag"

.PHONY: release
release: ## Full patch release: bump patch -> commit -> tag
	@echo "🚀 Starting patch release..."
	@$(MAKE) --no-print-directory version-bump-patch
	@$(MAKE) --no-print-directory tag
	@version="$$(cat VERSION)"; \
	echo "🎉 Release v$$version complete!"; \
	echo ""; \
	echo "   Push manually:"; \
	echo "     git push origin main"; \
	echo "     git push origin v$$version"

# ==============================================================================
# Info
# ==============================================================================

.PHONY: status
status: ## Show git status and current version
	@echo -e "$(COLOR_BOLD)Project status$(COLOR_RESET)"
	@echo "Version: $(VERSION)"
	@if [[ -n "$(GIT)" ]]; then \
		echo ""; \
		$(GIT) status -sb; \
	fi
# - EOF ------------------------------------------------------------------------
