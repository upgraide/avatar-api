# GitHub Actions Setup Guide

This guide shows you how to configure GitHub Actions to automatically build and push your Docker image to Docker Hub.

## Why Use GitHub Actions?

**Problem:** Building the Docker image locally on ARM Macs or machines with limited RAM (<8GB) fails.

**Solution:** GitHub Actions provides free x86 cloud runners with 7GB RAM and 14GB disk space, perfect for building Docker images.

**Benefits:**
- ✅ Works on any machine (Mac, Windows, Linux, ARM or x86)
- ✅ No local resource constraints
- ✅ Automatic builds on every push to main
- ✅ Can manually trigger builds
- ✅ Build logs saved in GitHub

---

## Setup Instructions

### Step 1: Get Docker Hub Credentials

You need a Docker Hub account to store your container image.

1. **Create Docker Hub Account** (if you don't have one):
   - Go to [hub.docker.com](https://hub.docker.com/)
   - Sign up for a free account
   - Verify your email address

2. **Get your Docker Hub username:**
   - Your username is shown at the top-right after logging in
   - Example: `upgraide`, `myusername`, etc.

3. **Generate Access Token** (recommended over password):
   - Go to [Account Settings → Security](https://hub.docker.com/settings/security)
   - Click "New Access Token"
   - Description: `GitHub Actions - avatar-api`
   - Access permissions: **Read, Write, Delete**
   - Click "Generate"
   - **COPY THE TOKEN NOW** - you won't see it again!

---

### Step 2: Configure GitHub Repository Secrets

1. **Navigate to your GitHub repository**:
   - Go to `https://github.com/yourusername/avatar-api`
   - Click **Settings** (top right)

2. **Access Secrets and Variables**:
   - In the left sidebar, expand **Secrets and variables**
   - Click **Actions**

3. **Add DOCKER_USERNAME secret**:
   - Click **New repository secret**
   - Name: `DOCKER_USERNAME`
   - Secret: Your Docker Hub username (e.g., `upgraide`)
   - Click **Add secret**

4. **Add DOCKER_PASSWORD secret**:
   - Click **New repository secret** again
   - Name: `DOCKER_PASSWORD`
   - Secret: Your Docker Hub access token (from Step 1.3)
   - Click **Add secret**

**Verification:** You should now see 2 secrets listed:
- `DOCKER_USERNAME`
- `DOCKER_PASSWORD`

---

### Step 3: Trigger the Build

You have two options to trigger the Docker build:

#### Option A: Manual Trigger (Recommended for First Build)

1. Go to your repository → **Actions** tab
2. In the left sidebar, click **"Build and Push Docker Image"**
3. Click **Run workflow** (right side)
4. Select branch: `main` or `master`
5. (Optional) Change Docker tag from default `v1.0`
6. Click **Run workflow** (green button)

The build will start immediately. Builds take **10-15 minutes**.

#### Option B: Automatic Trigger (on Push to Main)

The workflow automatically runs when you push to `main` or `master` branch:

```bash
git add .
git commit -m "Add GitHub Actions workflow"
git push origin main
```

The build will start automatically within a few seconds.

---

### Step 4: Monitor the Build

1. **View build progress**:
   - Go to **Actions** tab in your repository
   - Click on the running workflow (yellow indicator)
   - Click on the job name to see live logs

2. **Build stages** (what you'll see in logs):
   - ✓ Checkout code
   - ✓ Set up Docker Buildx
   - ✓ Log in to Docker Hub
   - ✓ Determine Docker tag
   - ✓ Build and push Docker image (~10 min)
   - ✓ Build summary

3. **Success indicators**:
   - Green checkmark next to workflow run
   - Summary shows image tags pushed
   - Image appears on Docker Hub: `https://hub.docker.com/r/yourusername/avatar-api`

4. **If build fails**:
   - Click into the failed step to see error message
   - Common issues:
     - ❌ Wrong Docker Hub credentials → Check secrets are correct
     - ❌ Repository doesn't exist → Create it on Docker Hub first
     - ❌ Out of disk space → This shouldn't happen with GitHub runners

---

### Step 5: Verify on Docker Hub

1. Go to [hub.docker.com](https://hub.docker.com/)
2. Navigate to your repositories
3. Click on `yourusername/avatar-api`
4. You should see tags:
   - `v1.0` (or your custom tag)
   - `latest`

**Image size:** Should be ~4-5GB (models NOT included)

---

## Using the Built Image

Once the image is pushed to Docker Hub, you can deploy it to RunPod:

```bash
# Use this image in your RunPod Serverless endpoint configuration:
upgraide/avatar-api:v1.0
# or
yourusername/avatar-api:v1.0
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for complete RunPod deployment instructions.

---

## Troubleshooting

### Build fails: "unauthorized: authentication required"

**Cause:** GitHub can't authenticate with Docker Hub.

**Fix:**
1. Verify secrets are set correctly: Settings → Secrets → Actions
2. Check `DOCKER_USERNAME` matches your Docker Hub username exactly
3. Regenerate Docker Hub access token if needed
4. Update `DOCKER_PASSWORD` secret with new token

### Build fails: "repository does not exist"

**Cause:** Docker Hub repository hasn't been created yet.

**Fix:**
1. Go to Docker Hub → Create Repository
2. Name: `avatar-api`
3. Visibility: Public (recommended) or Private
4. Click Create

OR the image name in the workflow doesn't match your username:
1. Edit `.github/workflows/docker-build.yml`
2. Change `DOCKER_IMAGE: upgraide/avatar-api` to `DOCKER_IMAGE: yourusername/avatar-api`
3. Commit and push

### Build succeeds but image is huge (>10GB)

**Cause:** Docker layers not being cached efficiently.

**Fix:** This is normal for first build. Subsequent builds will be faster due to layer caching.

### Want to build a different version tag?

**Manual trigger:**
1. Go to Actions → "Build and Push Docker Image" → Run workflow
2. Enter custom tag in the input field (e.g., `v1.1`, `dev`, `staging`)
3. Run workflow

**Or update workflow file:**
1. Edit `.github/workflows/docker-build.yml`
2. Change `DEFAULT_TAG: v1.0` to your desired version
3. Commit and push

---

## Advanced: Rebuilding After Changes

After modifying code (e.g., fixing `core/models.py` or `startup.sh`):

1. **Commit your changes:**
   ```bash
   git add .
   git commit -m "Fix model download logic"
   git push origin main
   ```

2. **Automatic rebuild:**
   - GitHub Actions auto-triggers on push to main
   - New image pushed to Docker Hub (tagged `latest` and version)

3. **Deploy updated image to RunPod:**
   - Option A: Update endpoint to use new tag
   - Option B: Use `latest` tag (always gets newest image)

---

## Cost

**GitHub Actions:** 2,000 free minutes/month on free plan (plenty for this project)
**Docker Hub:** Free for public repositories (unlimited pulls)

---

## Next Steps

After successful build:
1. ✅ Image is on Docker Hub
2. → Proceed to [DEPLOYMENT.md](DEPLOYMENT.md) Step 2 (Configure RunPod)
3. → Deploy container to RunPod Serverless
4. → Test end-to-end video generation

---

**Questions?** Check the [GitHub Actions logs](https://docs.github.com/en/actions/monitoring-and-troubleshooting-workflows/using-workflow-run-logs) or open an issue.
