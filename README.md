# Redhat-AI-Dev Llama Stack

[![Apache2.0 License](https://img.shields.io/badge/license-Apache2.0-brightgreen.svg)](LICENSE)
[![Llama Stack Version](https://img.shields.io/badge/llama_stack-v0.5.2-blue)](https://llamastack.github.io/docs)
[![Python Version](https://img.shields.io/badge/python-3.12-blue)](https://www.python.org/downloads/release/python-3120/)

- [Image Availability](#image-availability)
  - [Latest Stable Release](#latest-stable-release)
  - [Latest Developer Release](#latest-developer-release)
- [Usage](#usage)
  - [Available Inferences](#available-inferences)
    - [vLLM](#vllm)
    - [Ollama](#ollama)
    - [OpenAI](#openai)
    - [Vertex AI (Gemini)](#vertex-ai-gemini)
  - [Configuring RAG](#configuring-rag)
  - [Configuring Safety Guards](#configuring-safety-guards)
- [Running Locally](#running-locally)
- [Running on a Cluster](#running-on-a-cluster)
- [Makefile Commands](#makefile-commands)
- [Contributing](#contributing)
  - [Local Development Requirements](#local-development-requirements)
  - [Updating YAML Files](#updating-yaml-files)
- [Troubleshooting](#troubleshooting)

# Image Availability

## Developer Release (Library Mode)

```
quay.io/redhat-ai-dev/llama-stack:library-0.5.2
```

# Usage

> [!IMPORTANT]
> The default Llama Stack configuration file that is baked into the built image contains tools. Ensure your provided inference server has tool calling **enabled**.

## Available Inferences

Each inference has its own set of environment variables. You can include all of these variables in a `.env` file and pass that instead to your container. See [default-values.env](./env/default-values.env) for a template. It is recommended you copy that file to `values.env` to avoid committing it to Git.

> [!IMPORTANT]
> These are `.env` files, you should enter values without quotations to avoid errors in parsing. 
> 
> VLLM_API_KEY=token ✅
> 
> VLLM_API_KEY="token" ❌

### vLLM

**Required**
```env
ENABLE_VLLM=true
VLLM_URL=<your-server-url>/v1
VLLM_API_KEY=<your-api-key>
```
**Optional**
```env
VLLM_MAX_TOKENS=<defaults to 4096>
VLLM_TLS_VERIFY=<defaults to true>
```

### Ollama

**Required**
```env
ENABLE_OLLAMA=true
OLLAMA_URL=<your-ollama-url>
```

The value of `OLLAMA_URL` is the default `http://localhost:11434`, when you are not running this llama-stack inside a container i.e.; if you run llama-stack directly on your laptop terminal, your llama-stack can reference and network with the Ollama at localhost.

The value of `OLLAMA_URL` is `http://host.containers.internal:11434` if you are running llama-stack inside a container i.e.; if you run llama-stack with the podman run command above, it needs to access the Ollama endpoint on your laptop not inside the container. **If you are using Linux**, ensure your firewall allows port 11434 to your podman container's network, some Linux distributions firewalls block all traffic by default. Alternatively you can use `OLLAMA_URL=http://localhost:11434` and set the `--network host` flag when you run your podman container.

### OpenAI

**Required**
```env
ENABLE_OPENAI=true
OPENAI_API_KEY=<your-api-key>
```

To get your API Key, go to [platform.openai.com](https://platform.openai.com/settings/organization/api-keys).

### Vertex AI (Gemini)

**Required**
```env
ENABLE_VERTEX_AI=true
VERTEX_AI_PROJECT=
VERTEX_AI_LOCATION=
GOOGLE_APPLICATION_CREDENTIALS=
```

For information about these variables see: https://llamastack.github.io/v0.2.18/providers/inference/remote_vertexai.html.

## Configuring RAG

The `config.yaml` file that is included in the container image has a RAG tool enabled. In order for this tool to have the necessary reference content, you need to run:

```
make get-rag
```

This will fetch the necessary reference content and add it to your local project directory.

## Configuring Safety Guards

Safety guards are configured through environment variables in `env/values.env`. To disable safety guards, leave `ENABLE_SAFETY=` empty.

To enable safety guards, set the following:

```env
ENABLE_SAFETY=true
SAFETY_MODEL=<llama-guard-model-name>
SAFETY_URL=<url-of-safety-model-server>/v1
SAFETY_API_KEY=<api-key-if-required>
```

- `SAFETY_MODEL`: The name of the Llama Guard model being used. Defaults to `llama-guard3:8b`.
- `SAFETY_URL`: The URL where the safety model is available. For local container runs, use `http://host.containers.internal:11434/v1`.
- `SAFETY_API_KEY`: The API key required for access to the safety model. Not required for local deployments.

You will also need an instance of Llama Guard running. You can start one locally with Ollama:

```sh
podman run -d --name ollama -p 11434:11434 docker.io/ollama/ollama:latest
podman exec ollama ollama pull llama-guard3:8b
```

**Note:** Ensure the Ollama container is started and the model is ready before trying to query if deploying the containers manually.

# Running Locally

## Identifying Vector Store ID

With Llama Stack `0.4.3` the way Vector Stores are created has changed. This means that the RAG content you download locally by running `make get-rag` contains a generated Vector Store ID. In order for RAG to work properly you need to navigate to `/vector_db/rhdh_product_docs/<docs number>/llama-stack.yaml` and find the `vector_stores` section, it should look like:

```
vector_stores:
  - embedding_dimension: 768
    embedding_model: sentence-transformers//rag-content/embeddings_model
    provider_id: rhdh-product-docs-1_8
    vector_store_id: vs_3d47e06c-ac95-49b6-9833-d5e6dd7252dd
```

You will need the `vector_store_id` value. After copying that value you will need to update `config.yaml`. The `vector_store_id` you copied will replace the `vector_store_id` in that file.

## Running the Container

If you want to enable safety guards, see [Configuring Safety Guards](#configuring-safety-guards) before running.

```
podman run -it -p 8080:8080 --env-file ./env/values.env -v ./embeddings_model:/rag-content/embeddings_model:Z -v ./vector_db/rhdh_product_docs:/rag-content/vector_db/rhdh_product_docs:Z quay.io/redhat-ai-dev/llama-stack:library-0.4.3
```

## Running With Host Network

If using host network, you will need to add the `--network host` flag to the relevant run commands above.

# Running on a Cluster

To deploy on a cluster see [DEPLOYMENT.md](./docs/DEPLOYMENT.md).

# Makefile Commands

| Command | Description |
| ---- | ----|
| **get-rag** | Gets the RAG data and the embeddings model from the rag-content image registry to your local project directory |
| **sync-upstream-config** | Syncs `config.yaml`, `env/default-values.env`, `lightspeed-stack.yaml`, and image pins from upstream |
| **validate-upstream-config** | Validates that synced upstream files and image pins have not drifted |
| **update-question-validation** | Updates the question validation content in `providers.d` |

# Contributing

## Local Development Requirements

- [Yarn](https://yarnpkg.com/)
- [Node.js >= v22](https://nodejs.org/en/about/previous-releases)

## Updating YAML Files

This repository implements Prettier to handle all YAML formatting.
```sh
yarn format # Runs Prettier to update the YAMl files in this repository
yarn verify # Runs Prettier to check the YAML files in this repository
```

If you wish to try new changes with Llama Stack, you can build your own image using the `Containerfile` in the root of this repository.

# Troubleshooting

>[!NOTE]
> You can enable `DEBUG` logging by setting:
>```
>LLAMA_STACK_LOGGING=all=DEBUG
>```

If you experience an error related to permissions for the `vector_db`, such as:

```sh
sqlite3.OperationalError: attempt to write a readonly database
```

You should give the `vector_db` directory write permissions by:

```
chmod -R 777 vector_db
```