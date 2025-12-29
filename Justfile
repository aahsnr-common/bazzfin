# Variables matching your build.yml
image_name := "bazzfin"
fedora_version := "43"
base_image := "silverblue"
nvidia_base := "bazzite"

# Default command (prints available commands)
default:
    @just --list

# Build the image locally using Podman
build:
    @echo "Building {{image_name}} based on Fedora {{fedora_version}}..."
    podman build \
      --build-arg FEDORA_VERSION={{fedora_version}} \
      --build-arg BASE_IMAGE_NAME={{base_image}} \
      --build-arg NVIDIA_BASE={{nvidia_base}} \
      -t {{image_name}}:latest \
      -f Containerfile .

# Clean up local build artifacts
clean:
    podman rmi {{image_name}}:latest || true

# Test the image in a VM (Requires qemu/kvm)
test-vm:
    @echo "Spawning a test VM..."
    podman run --rm -it \
      --security-opt label=type:unconfined_t \
      {{image_name}}:latest \
      /bin/bash
