# Deployment

Below you can find documentation related to deploying `Lightspeed Core` and `Llama Stack` in a Pod with `Red Hat Developer Hub (RHDH)`.

## Prerequisites

- Red Hat Developer Hub

## Secrets

You will need a Secret (can be multiple) that can contain the following variables, which of these are set is dependant on what you want enabled. See [README.md](../README.md) for more.

> [!IMPORTANT]
> You only need to set the variables for the inference providers you want to enable. Leave unused provider variables empty.

**Note:** `SAFETY_MODEL` and `SAFETY_URL` are preset based on the Ollama usage in the Deployment [below](#updating-rhdh-backstage-deployment).

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: llama-stack-secrets
type: Opaque
stringData:
  ENABLE_VLLM: ""
  ENABLE_VERTEX_AI: ""
  ENABLE_OPENAI: ""
  ENABLE_OLLAMA: ""
  VLLM_URL: ""
  VLLM_API_KEY: ""
  VLLM_MAX_TOKENS: ""
  VLLM_TLS_VERIFY: ""
  OPENAI_API_KEY: ""
  VERTEX_AI_PROJECT: ""
  VERTEX_AI_LOCATION: ""
  GOOGLE_APPLICATION_CREDENTIALS: ""
  OLLAMA_URL: ""
  SAFETY_MODEL: "llama-guard3:8b"
  SAFETY_URL: "http://localhost:11434/v1"
  SAFETY_API_KEY: ""
```

## Config Maps

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: lightspeed-stack
data:
  lightspeed-stack.yaml: |
    name: Lightspeed Core Service (LCS)
    service:
      host: 0.0.0.0
      port: 8080
      auth_enabled: false
      workers: 1
      color_log: true
      access_log: true
    llama_stack:
      use_as_library_client: false
      url: http://localhost:8321
    user_data_collection:
      feedback_enabled: false
      feedback_storage: '/tmp/data/feedback'
    authentication:
      module: 'noop'
    conversation_cache:
      type: 'sqlite'
      sqlite:
        db_path: '/tmp/cache.db'
```

## Updating RHDH (Backstage) Deployment

The deployment includes:
- **Init Containers**:
  - Copies RAG content (embeddings model and vector database) to a shared volume
  - Pulls the Llama Guard model for safety guards
- **Ollama Container**: Runs the Llama Guard model for safety
- **Llama Stack Container**: Runs the Llama Stack server with RAG capabilities
- **Lightspeed Core Container**: Provides the Lightspeed Core service

```yaml
spec:
  deployment:
    patch:
      spec:
        template:
          spec:
            initContainers:
              - name: rag-content-init
                image: 'quay.io/redhat-ai-dev/rag-content:experimental-release-1.8-lcs'
                command:
                  - /bin/sh
                  - -c
                  - |
                    cp -r /rag/embeddings_model /rag-content/
                    cp -r /rag/vector_db /rag-content/
                volumeMounts:
                  - mountPath: /rag-content
                    name: rag-content
              - name: ollama-model-init
                image: 'docker.io/ollama/ollama:latest'
                command:
                  - /bin/sh
                  - -c
                  - |
                    ollama serve &
                    sleep 5
                    ollama pull llama-guard3:8b
                volumeMounts:
                  - mountPath: /root/.ollama
                    name: ollama-models
            containers:
              - name: ollama
                image: 'docker.io/ollama/ollama:latest'
                volumeMounts:
                  - mountPath: /root/.ollama
                    name: ollama-models
              - name: llama-stack
                image: 'quay.io/redhat-ai-dev/llama-stack:latest'
                envFrom:
                  - secretRef:
                      name: llama-stack-secrets
                volumeMounts:
                  - mountPath: /rag-content
                    name: rag-content
              - name: lightspeed-core
                image: 'quay.io/lightspeed-core/lightspeed-stack:dev-latest'
                volumeMounts:
                  - mountPath: /app-root/lightspeed-stack.yaml
                    name: lightspeed-stack
                    subPath: lightspeed-stack.yaml
                  - mountPath: /tmp/data/feedback
                    name: shared-storage
            volumes:
              - name: rag-content
                emptyDir: {}
              - name: ollama-models
                emptyDir: {}
              - name: lightspeed-stack
                configMap:
                  name: lightspeed-stack
              - name: shared-storage
                emptyDir: {}
```
