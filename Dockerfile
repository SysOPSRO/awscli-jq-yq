# Build arguments
ARG ALPINE_VERSION=3.20
ARG AWS_CLI_VERSION=2.15.30
ARG AWS_CLI_PYTHON_VERSION=3.11

### Builder Stage ###
FROM python:${AWS_CLI_PYTHON_VERSION}-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git unzip groff build-base libffi-dev cmake

# Clone the AWS CLI repository
ARG AWS_CLI_VERSION
RUN git clone --single-branch --depth 1 -b ${AWS_CLI_VERSION} https://github.com/aws/aws-cli.git

# Set the working directory
WORKDIR /aws-cli

# Create a virtual environment and install AWS CLI
RUN python -m venv venv && \
    . venv/bin/activate && \
    scripts/installers/make-exe && \
    unzip -q dist/awscli-exe.zip && \
    aws/install --bin-dir /aws-cli-bin && \
    /aws-cli-bin/aws --version

# Reduce image size: remove autocomplete and examples
RUN rm -rf /usr/local/aws-cli/v2/current/dist/aws_completer \
           /usr/local/aws-cli/v2/current/dist/awscli/data/ac.index \
           /usr/local/aws-cli/v2/current/dist/awscli/examples && \
    find /usr/local/aws-cli/v2/current/dist/awscli/data -name completions-1*.json -delete && \
    find /usr/local/aws-cli/v2/current/dist/awscli/botocore/data -name examples-1.json -delete

### Final Stage ###
FROM alpine:${ALPINE_VERSION}

# Install runtime dependencies
RUN apk --no-cache add jq less groff

# Copy AWS CLI from the builder stage
COPY --from=builder /usr/local/aws-cli/ /usr/local/aws-cli/
COPY --from=builder /aws-cli-bin/ /usr/local/bin/

# Set environment variables
ENV PATH="/usr/local/aws-cli/v2/current/bin:$PATH"
ENV LANG='C.UTF-8'

# Verify the installation
RUN aws --version && jq --version

# Define the entrypoint to start an interactive shell
ENTRYPOINT ["/bin/ash"]