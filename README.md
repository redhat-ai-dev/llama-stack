# Redhat-AI-Dev Llama Stack

[![Apache2.0 License](https://img.shields.io/badge/license-Apache2.0-brightgreen.svg)](LICENSE)

- [Image Availability](#image-availability)
- [Usage](#usage)
  - [Available Inferences](#available-inferences)
    - [vLLM](#vllm)
    - [Ollama](#ollama)
    - [OpenAI](#openai)
  - [Configuring RAG](#configuring-rag)
  - [Configuring Question Validation](#configuring-question-validation)
  - [Running Locally](#running-locally)
  - [Running on a Cluster](#running-on-a-cluster)
- [Makefile Commands](#makefile-commands)
- [Contributing](#contributing)
- [Troubleshooting](#troubleshooting)

## Image Availability

### Latest Stable Release

```
quay.io/redhat-ai-dev/llama-stack:0.1.1
```

### Latest Developer Release

```
quay.io/redhat-ai-dev/llama-stack:latest
```

## Usage

> [!IMPORTANT]
> The default Llama Stack configuration file that is baked into the built image contains tools. Ensure your provided inference server has tool calling **enabled**.

**Note:** You can enable `DEBUG` logging by setting:
```
LLAMA_STACK_LOGGING=all=DEBUG
```

### Available Inferences

Each inference has its own set of environment variables. You can include all of these variables in a `.env` file and pass that instead to your container. See [default-values.env](./env/default-values.env) for a template. It is recommended you copy that file to `values.env` to avoid committing it to Git.

> [!IMPORTANT]
> These are `.env` files, you should enter values without quotations to avoid errors in parsing. 
> 
> VLLM_API_KEY=token ✅
> 
> VLLM_API_KEY="token" ❌

#### vLLM

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

#### Ollama

**Required**
```env
ENABLE_OLLAMA=true
OLLAMA_URL=<your-ollama-url>
```

The value of `OLLAMA_URL` is the default `http://localhost:11434`, when you are not running this llama-stack inside a container i.e.; if you run llama-stack directly on your laptop terminal, your llama-stack can reference and network with the Ollama at localhost.

The value of `OLLAMA_URL` is `http://host.containers.internal:11434` if you are running llama-stack inside a container i.e.; if you run llama-stack with the podman run command above, it needs to access the Ollama endpoint on your laptop not inside the container. **If you are using Linux**, ensure your firewall allows port 11434 to your podman container's network, some Linux distributions firewalls block all traffic by default. Alternatively you can use `OLLAMA_URL=http://localhost:11434` and set the `--network host` flag when you run your podman container.

#### OpenAI

**Required**
```env
ENABLE_OPENAI=true
OPENAI_API_KEY=<your-api-key>
```

To get your API Key, go to [platform.openai.com](https://platform.openai.com/settings/organization/api-keys).

#### Vertex AI (Gemini)

**Required**
```env
ENABLE_VERTEX_AI=true
VERTEX_AI_PROJECT=
VERTEX_AI_LOCATION=
GOOGLE_APPLICATION_CREDENTIALS=
```

For information about these variables see: https://llamastack.github.io/v0.2.18/providers/inference/remote_vertexai.html.

### Configuring RAG

The `run.yaml` file that is included in the container image has a RAG tool enabled. In order for this tool to have the necessary reference content, you need to run:

```
make get-rag
```

This will fetch the necessary reference content and add it to your local project directory.

### Configuring Question Validation

By default this Llama Stack has a Safety Shield for question validation enabled. You will need to set the following environment variables to ensure functionality:

- `VALIDATION_PROVIDER`: The provider you want to use for question validation. This should match what the provider value you are using under `inference`, such as `vllm`, `ollama`, `openai`. Defaults to `vllm`
- `VALIDATION_MODEL_NAME`: The name of the LLM you want to use for question validation

### Running Locally

```
podman run -it -p 8321:8321 --env-file ./env/values.env -v ./embeddings_model:/app-root/embeddings_model:Z -v ./vector_db/rhdh_product_docs:/app-root/vector_db/rhdh_product_docs:Z quay.io/redhat-ai-dev/llama-stack:latest
```

Or if using the host network:
```
podman run -it -p 8321:8321 --env-file ./env/values.env --network host -v ./embeddings_model:/app-root/embeddings_model:Z -v ./vector_db/rhdh_product_docs:/app-root/vector_db/rhdh_product_docs:Z quay.io/redhat-ai-dev/llama-stack:latest
```

> [!WARNING]
> This repository is currently running Llama Stack v0.2.22. This version is incompatible with Llama Stack >= 0.3.x. Due to these limitations, the latest image we can consume from Lightspeed Core is `quay.io/lightspeed-core/lightspeed-stack:dev-20251208-f20efb9`.
>

Latest Lightspeed Core Developer Image:
```
quay.io/lightspeed-core/lightspeed-stack:dev-latest
```

To run Lightspeed Core (Llama Stack should be running):
```
podman run -it -p 8080:8080 -v ./lightspeed-stack.yaml:/app-root/lightspeed-stack.yaml:Z quay.io/lightspeed-core/lightspeed-stack:dev-latest
```

**Note:** If you have built your own version of Lightspeed Core you can replace the image referenced with your own build. Additionally, you can use the Llama Stack container along with the `lightspeed-stack.yaml` file to run Lightspeed Core locally with `uv` from their [repository](https://github.com/lightspeed-core/lightspeed-stack).

### Running on a Cluster

To deploy on a cluster see [DEPLOYMENT.md](./docs/DEPLOYMENT.md).

# Makefile Commands

| Command | Description |
| ---- | ----|
| **get-rag** | Gets the RAG data and the embeddings model from the rag-content image registry to your local project directory |
| **update-question-validation** | Updates the question validation content in `providers.d` |
| **validate-prompt-templates** | Validates prompt values in run.yaml. **Requires Python >= 3.11** |
| **update-prompt-templates** | Updates the prompt values in run.yaml. **Requires Python >= 3.11** |

## Contributing

### Local Development Requirements

- [Yarn](https://yarnpkg.com/)
- [Node.js >= v22](https://nodejs.org/en/about/previous-releases)

### Updating YAML Files

This repository implements Prettier to handle all YAML formatting.
```sh
yarn format # Runs Prettier to update the YAMl files in this repository
yarn verify # Runs Prettier to check the YAML files in this repository
```

If you wish to try new changes with Llama Stack, you can build your own image using the `Containerfile` in the root of this repository.

## Troubleshooting

If you experience an error related to permissions for the `vector_db`, such as:

```sh
sqlite3.OperationalError: attempt to write a readonly database
```

You should give the `vector_db` directory write permissions by:

```
chmod -R 777 vector_db
```