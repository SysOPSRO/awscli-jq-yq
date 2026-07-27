# Build arguments
ARG ALPINE_VERSION=3.24
ARG AWS_CLI_VERSION=2.22.6
ARG AWS_CLI_PYTHON_VERSION=3.11

### Builder Stage ###
FROM python:${AWS_CLI_PYTHON_VERSION}-slim AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    unzip \
    groff \
    build-essential \
    libffi-dev \
    zlib1g \
    zlib1g-dev \
    binutils \
    upx-ucl \
    curl \
    libssl-dev \
    cargo \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Clone the AWS CLI repository
ARG AWS_CLI_VERSION
RUN git clone --single-branch --depth 1 -b ${AWS_CLI_VERSION} https://github.com/aws/aws-cli.git

# Set the working directory
WORKDIR /aws-cli

# ENV SETUPTOOLS_USE_DISTUTILS=stdlib
# ENV RUAMEL_NO_LONG_DESCRIPTION=1
# ENV YAML_FORCE_BUNDLED=1
# Create a virtual environment and install AWS CLI
    # pip install "setuptools<70" && \
    # pip install --only-binary=:all: ruamel.yaml.clib && \

RUN python -m venv venv && \
    . venv/bin/activate && \
    pip install --upgrade pip wheel && \
    PIP_NO_BUILD_ISOLATION=1 scripts/installers/make-exe && \
    unzip -q dist/awscli-exe.zip && \
    aws/install --bin-dir /aws-cli-bin && \
    /aws-cli-bin/aws --version

# Reduce image size: remove autocomplete and examples
RUN rm -rf /usr/local/aws-cli/v2/current/dist/aws_completer \
    /usr/local/aws-cli/v2/current/dist/awscli/data/ac.index \
    /usr/local/aws-cli/v2/current/dist/awscli/examples && \
    find /usr/local/aws-cli/v2/current/dist/awscli/data -name completions-1*.json -delete && \
    find /usr/local/aws-cli/v2/current/dist/awscli/botocore/data -name examples-1.json -delete && \
    find /usr/local/aws-cli/ /aws-cli-bin/ -type f -executable -exec strip --strip-unneeded {} + || true

ARG TARGETARCH
RUN case "${TARGETARCH}" in \
      amd64)  CLI53_ARCH="amd64" ;; \
      arm64)  CLI53_ARCH="arm64" ;; \
      *) echo "Unsupported arch: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    curl -sSLo /aws-cli-bin/cli53 \
      https://github.com/barnybug/cli53/releases/download/v0.9.0/cli53-linux-${CLI53_ARCH} && \
    chmod +x /aws-cli-bin/cli53 && \
    upx -9 /aws-cli-bin/cli53

# install custodian
RUN python3 -m venv /opt/custodian && \
    . /opt/custodian/bin/activate && \
    pip install --upgrade pip && \
    pip install "c7n[aws]" && \
    custodian version
# clean custodian venv
RUN rm -rf /opt/custodian/lib/python*/site-packages/pip \
    /opt/custodian/lib/python*/site-packages/setuptools \
    /opt/custodian/lib/python*/site-packages/wheel

### Final Stage ###
# was alpine${ALPINE_VERSION}
FROM python:${AWS_CLI_PYTHON_VERSION}-slim

# Install runtime dependencies
# RUN apk --no-cache add jq yq gawk less groff bash nano mc htop coreutils curl kubectl py3-mysqlclient py3-pymysql git redis
RUN apt-get update && apt-get install -y --no-install-recommends \
    jq \
    yq \
    gawk \
    less \
    groff \
    bash \
    nano \
    mc \
    htop \
    curl \
    kubectl \
    default-mysql-client \
    python3-mysqldb \
    python3-pymysql \
    git \
    redis-tools \
    && rm -rf /var/lib/apt/lists/*

# Copy AWS CLI from the builder stage
COPY --from=builder /usr/local/aws-cli/ /usr/local/aws-cli/
COPY --from=builder /aws-cli-bin/ /usr/local/bin/
COPY --from=builder /opt/custodian /opt/custodian
COPY tools/* /usr/local/bin/
RUN chmod +x /usr/local/bin/dns-purge-unused.sh

# Set the default shell to Bash
SHELL ["/bin/bash", "-c"]

# Set environment variables
ENV PATH="/opt/custodian/bin:/usr/local/aws-cli/v2/current/bin:$PATH"
ENV LANG='C.UTF-8'

# Verify the installation
RUN aws --version && jq --version && yq --version && custodian version

# Start an interactive Bash session by default
CMD ["/bin/bash"]