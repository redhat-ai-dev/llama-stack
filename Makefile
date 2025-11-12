RAG_CONTENT_IMAGE ?= quay.io/redhat-ai-dev/rag-content:release-1.8-lcs
VENV := $(CURDIR)/scripts/python-scripts/.venv
PYTHON := $(VENV)/bin/python3
PIP := $(VENV)/bin/pip3

default: help

get-rag: ## Download a copy of the RAG embedding model and vector database
	podman create --replace --name tmp-rag-container $(RAG_CONTENT_IMAGE) true
	rm -rf vector_db embeddings_model
	podman cp tmp-rag-container:/rag/vector_db vector_db
	podman cp tmp-rag-container:/rag/embeddings_model embeddings_model
	podman rm tmp-rag-container

help: ## Show this help screen
	@echo 'Usage: make <OPTIONS> ... <TARGETS>'
	@echo ''
	@echo 'Available targets are:'
	@echo ''
	@grep -E '^[ a-zA-Z0-9_.-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-33s\033[0m %s\n", $$1, $$2}'
	@echo ''

# TODO (Jdubrick): Replace reference to lightspeed-core/lightspeed-providers once bug is addressed.
update-question-validation:
	curl -o ./config/providers.d/inline/safety/lightspeed_question_validity.yaml https://raw.githubusercontent.com/Jdubrick/lightspeed-providers/refs/heads/devai/resources/external_providers/inline/safety/lightspeed_question_validity.yaml