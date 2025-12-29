This guide assumes you have forked `ublue-os/bazzite`, replaced the `Containerfile` with your custom version, and that Fedora 43 images and packages exist (as requested).

### **1. Repository Structure Verification**

Your `Containerfile` relies on specific directories to build correctly. Since you have forked the repository, these should already be present, but you must verify them.

- **`build_files/`**: Contains helper scripts like `/ctx/cleanup` and `/ctx/install-kernel`. Ensure this directory is in your repository root.
- **`system_files/`**: Contains the desktop and Nvidia configuration files referenced in Stage 2 of your `Containerfile`.
- **`firmware/`**: Your `Containerfile` executes `COPY firmware /`. Ensure a `firmware` folder exists in the root, even if it is empty, to prevent build failures.

### **2. The Workflow File**

Delete any existing workflows in `.github/workflows/` and create a new file named `.github/workflows/build.yml` with the following content. This workflow is tailored to your single-image build.

```yaml
name: Build Custom Bazzite
on:
  push:
    branches:
      - main
    paths-ignore:
      - "README.md"
  schedule:
    - cron: "20 20 * * *" # Builds daily at 8:20pm UTC
  workflow_dispatch: # Allows manual trigger

env:
  # VARIABLES TO CHANGE
  IMAGE_NAME: bazzfin
  FEDORA_VERSION: 43
  IMAGE_REGISTRY: ghcr.io/${{ github.repository_owner }}

jobs:
  build_push:
    name: Build and Push Image
    runs-on: ubuntu-24.04
    permissions:
      contents: read
      packages: write
      id-token: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Verify Build Context
        run: |
          if [ ! -d "build_files" ]; then echo "❌ build_files directory missing!"; exit 1; fi
          if [ ! -d "system_files" ]; then echo "❌ system_files directory missing!"; exit 1; fi

      - name: Maximize Build Space
        uses: ublue-os/remove-unwanted-software@v7

      - name: Generate Tags
        id: generate-tags
        shell: bash
        run: |
          # Generates tags: latest, 43, and date-stamp
          TIMESTAMP="$(date +%Y%m%d)"
          echo "tags=latest ${FEDORA_VERSION} ${TIMESTAMP}" >> $GITHUB_OUTPUT

      - name: Image Metadata
        uses: docker/metadata-action@v5
        id: meta
        with:
          images: |
            ${{ env.IMAGE_REGISTRY }}/${{ env.IMAGE_NAME }}
          labels: |
            org.opencontainers.image.title=${{ env.IMAGE_NAME }}
            org.opencontainers.image.description=Custom Bazzite (Silverblue+Nvidia+ASUS)
            io.artifacthub.package.readme-url=https://raw.githubusercontent.com/${{ github.repository }}/main/README.md

      - name: Build Image using Buildah
        id: build_image
        uses: redhat-actions/buildah-build@v2
        with:
          containerfiles: |
            ./Containerfile
          image: ${{ env.IMAGE_NAME }}
          tags: ${{ steps.generate-tags.outputs.tags }}
          build-args: |
            FEDORA_VERSION=${{ env.FEDORA_VERSION }}
            BASE_IMAGE_NAME=kinoite
            NVIDIA_BASE=bazzite
          oci: true

      - name: Login to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Push Image
        uses: redhat-actions/push-to-registry@v2
        id: push
        with:
          image: ${{ steps.build_image.outputs.image }}
          tags: ${{ steps.build_image.outputs.tags }}
          registry: ${{ env.IMAGE_REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Install Cosign
        uses: sigstore/cosign-installer@v3.5.0

      - name: Sign the images
        run: |
          cosign sign -y --key env://COSIGN_PRIVATE_KEY ${{ env.IMAGE_REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.push.outputs.digest }}
        env:
          COSIGN_PRIVATE_KEY: ${{ secrets.SIGNING_SECRET }}
          COSIGN_EXPERIMENTAL: false
```

### **3. Variables You Need to Change**

#### **A. In `build.yml` (Environment Variables)**

- **`IMAGE_NAME`**: Set to `bazzfin` to match your `Containerfile` default. If you change this, your final image URL will change (e.g., `ghcr.io/youruser/newname`).
- **`FEDORA_VERSION`**: Set to `43`. This controls which upstream Bazzite kernel and base image are pulled.
- **`BASE_IMAGE_NAME`** (in `build-args`): Set to `kinoite` (for KDE) or `silverblue` (for GNOME). Your `Containerfile` defaults to `kinoite`, but your comments mention "Silverblue... Desktop Shared". Ensure this matches your desired desktop environment.

#### **B. In GitHub Repository Settings (Secrets)**

You **must** add a signing key for the build to succeed.

1. **Generate Key:** Run `cosign generate-key-pair` on your local machine.
2. **Add Secret:** Go to **Settings > Secrets and variables > Actions** in your GitHub repository.
3. **New Secret:** Create a secret named **`SIGNING_SECRET`** and paste the content of `cosign.key` (the private key).

### **4. Required Files to Add/Commit**

- **`cosign.pub`**: You must commit your public key to the root of the repository. This allows users (and you) to verify the image before rebasing.

### **5. Next Step: Rebasing to Your Image**

Once the GitHub Action completes successfully, rebase your system to the new image:

```bash
# 1. Authorize your signing key
sudo mkdir -p /etc/pki/containers
sudo cp path/to/cosign.pub /etc/pki/containers/bazzfin.pub

# 2. Rebase (Use your actual GitHub username)
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/aahsnr-common/bazzfin:latest

```
