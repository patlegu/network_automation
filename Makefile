# Fonction to import config files stored in the env directory
# define setup_env
	# $(eval ENV_FILE := env/$(1).env)
	# @echo " - setup env $(ENV_FILE)"
	# $(eval include env/$(1).env)
	# $(eval export sed 's/=.*//' env/$(1).env)
# endef

# Define default environment file paths
# Users can override these by passing them on the command line, e.g.,
# make IDENT_ENV_PATH=my_ident.env build
IDENT_ENV_PATH ?= env/ident.env
CONFIG_ENV_PATH ?= env/config.env
DEPLOY_ENV_PATH ?= env/deploy.env

# Helper to robustly extract variable names for export
export_vars = $(shell awk -F= '/^[A-Za-z_][A-Za-z0-9_]*=/ {print $$1}' $(1))

# import credendtials
$(if $(wildcard $(IDENT_ENV_PATH)),,$(error Identity env file "$(IDENT_ENV_PATH)" not found. Create it or specify path with IDENT_ENV_PATH=))
$(info Loading identity environment from $(IDENT_ENV_PATH))
include $(IDENT_ENV_PATH)
export $(call export_vars,$(IDENT_ENV_PATH))

# import config.
# You can change the default config with `make CONFIG_ENV_PATH="config_special.env" build`
$(if $(wildcard $(CONFIG_ENV_PATH)),,$(error Configuration env file "$(CONFIG_ENV_PATH)" not found. Create it or specify path with CONFIG_ENV_PATH=))
$(info Loading configuration environment from $(CONFIG_ENV_PATH))
include $(CONFIG_ENV_PATH)
export $(call export_vars,$(CONFIG_ENV_PATH))

# import deploy config
# You can change the default deploy config with `make DEPLOY_ENV_PATH="deploy_special.env" release`
$(if $(wildcard $(DEPLOY_ENV_PATH)),,$(error Deployment env file "$(DEPLOY_ENV_PATH)" not found. Create it or specify path with DEPLOY_ENV_PATH=))
$(info Loading deployment environment from $(DEPLOY_ENV_PATH))
include $(DEPLOY_ENV_PATH)
export $(call export_vars,$(DEPLOY_ENV_PATH))

# grep the version from the mix file
VERSION=$(shell ./version.sh)


# HELP
# This will output the help for each task
# thanks to https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help build build-nc run up stop release publish publish-latest publish-version \
        tag tag-latest tag-version repo-login repo-logout version

help: ## This help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help


# DOCKER TASKS
# Build the container
build: ## Build the container
	docker build -t $(APP_NAME) .

build-nc: ## Build the container without caching
	docker build --no-cache -t $(APP_NAME) .

run: ## Run container on port configured in `$(CONFIG_ENV_PATH)`
	docker run -i -t --rm --env-file=$(CONFIG_ENV_PATH) -p=$(PORT):$(PORT) --name="$(APP_NAME)" $(APP_NAME)


up: build run ## Build and then run the container.

stop: ## Stop and remove a running container
	docker stop $(APP_NAME); docker rm $(APP_NAME)

release: build-nc publish ## Make a release by building and publishing the `{version}` ans `latest` tagged containers to docker Hub

# Docker publish
publish: repo-login publish-latest publish-version ## Publish the `{version}` ans `latest` tagged containers to docker Hub

publish-latest: tag-latest ## Publish the `latest` taged container to docker Hub
	@echo 'publish latest to $(DOCKER_REPO)'
	docker push $(DOCKER_REPO)/$(APP_NAME):latest

publish-version: tag-version ## Publish the `{version}` taged container to docker Hub
	@echo 'publish $(VERSION) to $(DOCKER_REPO)'
	docker push $(DOCKER_REPO)/$(APP_NAME):$(VERSION)

# Docker tagging
tag: tag-latest tag-version ## Generate container tags for the `{version}` ans `latest` tags

tag-latest: ## Generate container `{version}` tag
	@echo 'create tag latest'
	docker tag $(APP_NAME) $(DOCKER_REPO)/$(APP_NAME):latest

tag-version: ## Generate container `latest` tag
	@echo 'create tag $(VERSION)'
	docker tag $(APP_NAME) $(DOCKER_REPO)/$(APP_NAME):$(VERSION)

# HELPERS
DOCKER_LOGIN_SERVER ?= # Defaults to Docker Hub if empty. Set to your registry server if not Docker Hub.

# login to docker HUB repo-ECR
repo-login: ## Auto login to docker HUB repo
ifeq ($(strip $(DOCKER_CLI_LOGIN)),)
	@echo "DOCKER_CLI_LOGIN is not set. Please set it for automated login."
	@echo "Attempting interactive login to $(or $(DOCKER_LOGIN_SERVER), Docker Hub)..."
	@docker login $(DOCKER_LOGIN_SERVER)
else
    ifeq ($(strip $(DOCKER_CLI_PASSWORD)),)
		@echo "DOCKER_CLI_PASSWORD is not set. Attempting interactive login for user $(DOCKER_CLI_LOGIN) to $(or $(DOCKER_LOGIN_SERVER), Docker Hub)..."
		@docker login --username "$(DOCKER_CLI_LOGIN)" $(DOCKER_LOGIN_SERVER)
    else
		@echo "Logging in to $(or $(DOCKER_LOGIN_SERVER), Docker Hub) as $(DOCKER_CLI_LOGIN) using provided password..."
		@echo "$(DOCKER_CLI_PASSWORD)" | docker login --username "$(DOCKER_CLI_LOGIN)" --password-stdin $(DOCKER_LOGIN_SERVER)
    endif
endif

# login to docker HUB repo-ECR
repo-logout: ## Auto logout to docker HUB repo
	@echo "Logging out from $(or $(DOCKER_LOGIN_SERVER), Docker Hub)..."
	@docker logout $(DOCKER_LOGIN_SERVER)

version: ## Output the current version
	@echo $(VERSION)
