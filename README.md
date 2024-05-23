# AWS CLI with jq Docker Image

This repository contains the Dockerfile and build script to create a lightweight, production-ready Docker image for AWS CLI v2 with `jq` installed. The image is based on Alpine Linux for minimal size and includes necessary dependencies for AWS CLI operations.

## Table of Contents

- [Features](#features)
- [Usage](#usage)
    - [Building the Image](#building-the-image)
    - [Running the Container](#running-the-container)
- [Dockerfile Details](#dockerfile-details)

## Features

- **Lightweight**: Based on Alpine Linux to ensure a minimal footprint.
- **AWS CLI v2**: Includes the latest version of AWS CLI v2.
- **jq**: Installed for easy manipulation of JSON data.

## Usage

### Building the Image

To build the Docker image, run the following command:

```sh
./build
```

### Running the Container
To run the container interactively:

```sh
docker run -it thenaim/awscli-jq:v2.15.30
```

## Dockerfile Details

The Dockerfile uses a multi-stage build approach to ensure a minimal final image size:

1. **Builder Stage**:
    - Uses `python:3.11-alpine` as the base image.
    - Installs necessary build dependencies.
    - Clones the AWS CLI repository and builds it.
    - Removes unnecessary files to reduce the image size.

2. **Final Stage**:
    - Uses `alpine:3.20` as the base image.
    - Installs runtime dependencies (`jq`, `less`, `groff`).
    - Copies the AWS CLI from the builder stage.
    - Sets the environment variables and entry point.