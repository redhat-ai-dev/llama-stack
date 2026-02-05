#
#
# Copyright Red Hat
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
ARG TAG="dev-latest"
FROM quay.io/lightspeed-core/lightspeed-stack:${TAG} AS builder

USER root

ENV UV_COMPILE_BYTECODE=0 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0

WORKDIR /app-root

RUN pip3.12 install uv

# Install build tools needed for compiling C++ extensions (e.g., madoka)
RUN microdnf install -y gcc-c++ python3.12-devel && microdnf clean all

COPY ./pyproject.toml ./uv.lock LICENSE ./

# export to requirements to add ontop of deps. built in from LCORE
RUN uv export --locked --no-hashes --no-header --no-annotate --no-dev --format requirements.txt > requirements.txt

# use 'unsafe-best-match' to get all indices and then match
# instead of first match wins. Ensures extra index url is used
RUN uv pip install -r requirements.txt \
    --extra-index-url https://download.pytorch.org/whl/cpu \
    --index-strategy unsafe-best-match

FROM registry.access.redhat.com/ubi9/python-312-minimal:9.7@sha256:2ac60c655288a88ec55df5e2154b9654629491e3c58b5c54450fb3d27a575cb6

USER root

WORKDIR /app-root

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONCOERCECLOCALE=0 \
    PYTHONUTF8=1 \
    PYTHONIOENCODING=UTF-8 \
    LANG=en_US.UTF-8

COPY --from=builder --chown=1001:1001 /app-root /app-root

# checked by konflux
COPY --from=builder --chown=1001:1001 /app-root/LICENSE /licenses/

COPY --chown=1001:1001 ./run.yaml ./lightspeed-stack.yaml ./
COPY --chown=1001:1001 ./config/ ./config/
COPY --chown=1001:1001 --chmod=755 ./scripts/entrypoint.sh ./

ENV PATH="/app-root/.venv/bin:$PATH"

EXPOSE 8080

ENTRYPOINT ["./entrypoint.sh", "/app-root/.venv/bin/python3.12"]

USER 1001

# Labels for enterprise contract
LABEL com.redhat.component=rhdh-lightspeed-llama-stack
LABEL description="Red Hat Developer Hub Lightspeed Llama Stack"
LABEL distribution-scope=private
LABEL io.k8s.description="Red Hat Developer Hub Lightspeed Llama Stack"
LABEL io.k8s.display-name="Red Hat Developer Hub Lightspeed Llama Stack"
LABEL io.openshift.tags="developerhub,rhdh,lightspeed,ai,assistant,llama"
LABEL name=rhdh-lightspeed-llama-stack
LABEL release=1.8
LABEL url="https://github.com/redhat-ai-dev/llama-stack"
LABEL vendor="Red Hat, Inc."
LABEL version=0.1.1
LABEL summary="Red Hat Developer Hub Lightspeed Llama Stack"