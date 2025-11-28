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
FROM registry.access.redhat.com/ubi9/python-312:9.7@sha256:92c71d1e64cf84b9aa6e8e81555397175b9367298b456d24eac5b55ab41fdab9 AS builder
USER root
ENV UV_COMPILE_BYTECODE=0 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0

WORKDIR /app-root

RUN dnf install -y gcc python3.12-devel make && \
    dnf clean all && \
    pip3.12 install uv

COPY ./pyproject.toml ./

RUN uv sync --no-dev

FROM registry.access.redhat.com/ubi9/python-312-minimal:9.7@sha256:2ac60c655288a88ec55df5e2154b9654629491e3c58b5c54450fb3d27a575cb6
USER root
ARG APP_ROOT=/app-root
WORKDIR /app-root

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONCOERCECLOCALE=0 \
    PYTHONUTF8=1 \
    PYTHONIOENCODING=UTF-8 \
    LANG=en_US.UTF-8

RUN mkdir -p /licenses
COPY LICENSE /licenses/

COPY --from=builder --chown=1001:1001 /app-root/.venv ./.venv

COPY --chown=1001:1001 ./run.yaml ./scripts/entrypoint.sh ./

COPY --chown=1001:1001 ./config/ ./config

RUN chmod +x entrypoint.sh

ENV PATH="/app-root/.venv/bin:$PATH"

EXPOSE 8321

ENTRYPOINT ["./entrypoint.sh"]

USER 1001
