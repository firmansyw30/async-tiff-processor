# Async TIFF Processor

An event-driven AWS pipeline that processes large TIFF files asynchronously. When a TIFF is uploaded, it is converted into a transparent RGBA TIFF (white → transparent) and then tiled into web map tiles (PNG) using GDAL.

The whole flow is orchestrated by a long-polling **worker.js** running on an **EC2 Spot Fleet** instance: **S3 → SQS → Spot Fleet worker → Docker/GDAL → S3 outputs**.

## Architecture

```
                                Upload: s3://tiff-bucket/tiff/*.tif
                                          │
                                          ▼
                    ┌─────────────────────────────────┐
                    │   S3  tiff-bucket (public)      │
                    │   event notification            │
                    │   (prefix: tiff/)               │
                    └────────────┬────────────────────┘
                                 │ s3:ObjectCreated:*
                                 ▼
                    ┌─────────────────────────────────┐
                    │   SQS  tiff-upload-file-queue   │
                    │   (visibility timeout 600s)     │
                    └────────────┬────────────────────┘
                                 │ long poll (20s)
                                 ▼
                    ┌─────────────────────────────────┐
                    │   EC2 Spot Fleet worker (arm64) │
                    │   c7g / c8g, pm2 → worker.js    │
                    └────────────┬────────────────────┘
                                 │
        ┌──────────────┬─────────┴──────────────┐
        ▼              ▼                        ▼
  docker run      upload to S3            docker run
  make_transparent.py                  osgeo_utils.gdal2tiles
  (RGBA, white→    processed-tiff/     (-z 18-22, PNG, near)
   transparent)     *_transparent.tif   then aws s3 sync
        │                                │
        ▼                                ▼
  s3://tiff-bucket/               s3://tiff-bucket/
  processed-tiff/                 processed-tiles/{name}/
```

### Data flow

1. A TIFF is uploaded to `s3://tiff-bucket/tiff/` (the public upload bucket).
2. S3 emits an `s3:ObjectCreated:*` event notification to SQS (filtered to the `tiff/` prefix).
3. The Spot Fleet worker instance long-polls the SQS queue with a 20 s wait time.
4. `worker.js` downloads the TIFF from S3 to `/tmp/raster-data` on the instance.
5. It runs the GDAL Docker image, which executes `make_transparent.py` and produces an RGBA TIFF with white made transparent.
6. The transparent TIFF is uploaded to `s3://tiff-bucket/processed-tiff/{name}_transparent.tif`.
7. `worker.js` then runs `gdal2tiles` inside the same image (PNG tiles, zoom 18–22, nearest resampling) and syncs the tile tree to `s3://tiff-bucket/processed-tiles/{name}/`.
8. On success the SQS message is deleted. On failure the message is left in the queue so SQS retries it after the visibility timeout.

## Repository structure

```
async-tiff-processor/
├── worker.js                 # Node.js worker: polls SQS, runs Docker, uploads results
├── make_transparent.py       # GDAL/Python script: white → transparent RGBA TIFF
├── Dockerfile                # GDAL image + make_transparent.py entrypoint
├── build_push_docker.sh      # Build (arm64) and push the image to ECR
├── package.json              # Deps: @aws-sdk/client-s3, @aws-sdk/client-sqs, dotenv
├── package-lock.json
├── .env.example              # Worker env template (SQS_QUEUE_URL, AWS_REGION, WORKER_DOCKER_IMAGE)
├── .gitignore
└── infrastructure/           # Terraform provisioning of the whole architecture
    ├── terraform.tf          # Provider (aws ~5.0), region, caller identity
    ├── variables.tf          # All tunable variables (buckets, AMI, instance types, …)
    ├── s3.tf                 # tiff-bucket (public) + worker-source-code (private)
    ├── sqs.tf                # Queue + policy for S3 events and the worker role
    ├── ecr.tf                # ECR repository for the processing image
    ├── iam.tf                # Spot Fleet tagging role + EC2 worker role
    ├── launch_template.tf    # sqs-worker template (AMI, SG, EBS, user_data)
    ├── spot_fleet.tf         # Spot Fleet request with dynamic instance/subnet overrides
    ├── user_data.sh          # Boot script: Docker, Node 22, worker source, pm2
    ├── output.tf             # Terraform outputs (bucket names, queue URL, images, …)
    ├── example.tfvars        # Template for your own values
    └── prod.tfvars           # Production values (region ap-southeast-3)
```

## Getting started

### Prerequisites

- Terraform `>= 1.3` with AWS provider `~> 5.0`
- AWS CLI configured with an account that can create S3, SQS, ECR, IAM, and EC2 resources
- Docker with `buildx` for cross-platform (arm64) image builds
- An existing VPC, subnets, arm64 AMI, and EC2 key pair (referenced in `infrastructure/variables.tf`)

### 1. Build and push the Docker image

Replace `your-ecr-registry` in `build_push_docker.sh` with your ECR registry URL, then run:

```bash
./build_push_docker.sh
```

This builds `python-make-transparent:latest` for `linux/arm64`, tags it, and pushes it to ECR.

### 2. Upload the worker source to the private bucket

`user_data.sh` downloads `worker.js` and `package.json` from the source-code bucket at boot:

```bash
aws s3 cp worker.js s3://<source_bucket>/worker.js
aws s3 cp package.json s3://<source_bucket>/package.json
```

### 3. Provision the infrastructure

```bash
cd infrastructure
terraform init
terraform plan -var-file=prod.tfvars
terraform apply -var-file=prod.tfvars
```

Useful outputs after apply:

```bash
terraform output tiff_bucket
terraform output queue_url
terraform output worker_docker_image
terraform output source_code_bucket
```

### 4. Upload a TIFF and watch it process

```bash
aws s3 cp your_file.tif s3://tiff-bucket/tiff/
```

The pipeline runs and writes:

- `s3://tiff-bucket/processed-tiff/your_file_transparent.tif`
- `s3://tiff-bucket/processed-tiles/your_file/` (PNG tile tree, zoom 18–22)

## Processing pipeline details

### White → transparent conversion (`make_transparent.py`)

Converts palette, RGB, or RGBA TIFFs into a 4-band RGBA TIFF where pure-white pixels get alpha 0:

- Blocked processing (2048×2048 windows) with a RAM cache of 1 GB
- Tiled output (512×512) with `COMPRESS=DEFLATE, ZLEVEL=1, PREDICTOR=2`
- `NUM_THREADS=ALL_CPUS` and `BIGTIFF=IF_SAFER` for files > 4 GB

### Tile generation (`gdal2tiles`)

```bash
python3 -m osgeo_utils.gdal2tiles \
  --tiledriver=PNG --resampling=near -z 18-22 \
  /data/{name}_transparent.tif /data/tiles_{name}
```

The tile tree is synced to S3 with `aws s3 sync` and cleaned up from the instance afterward.

## Configuration reference

### Worker environment (`.env.example`)

| Variable               | Description                                        |
| ---------------------- | -------------------------------------------------- |
| `SQS_QUEUE_URL`        | SQS queue the worker polls for S3 events           |
| `AWS_REGION`           | AWS region (e.g., `ap-southeast-3`)                |
| `WORKER_DOCKER_IMAGE`  | Full ECR image reference run by the worker         |

### Key Terraform variables (`infrastructure/variables.tf`)

| Variable              | Default            | Description                                   |
| --------------------- | ------------------ | --------------------------------------------- |
| `region`              | `ap-southeast-3`   | AWS region                                    |
| `vpc_id`              | (existing VPC)     | VPC hosting the worker instances              |
| `subnet_ids`          | 3 subnets          | Subnets the Spot Fleet can use                 |
| `worker_ami`          | (arm64 AMI)        | Must be arm64 to match c7g/c8g instances      |
| `key_name`            | `mapidkeypair`     | EC2 key pair for SSH                          |
| `instance_types`      | c7g/c8g large–2xlarge | Spot Fleet overrides (arm64, Graviton)     |
| `tiff_bucket_name`    | `tiff-bucket`      | Public bucket receiving uploads under `tiff/` |
| `source_bucket_name`  | (private bucket)   | Bucket storing `worker.js` / `package.json`   |
| `queue_name`          | `tiff-upload-file-queue` | SQS queue for upload events            |
| `queue_visibility_timeout` | 600             | High because gdal2tiles is slow; avoids duplicate work |
| `ecr_repository_name` | `python-make-transparent-registry` | ECR image repository        |
| `owner_tag` / `project_tag` | firman_devops / async-tiff-processor | Resource tags          |

## Operational notes

- **Retries & error handling**: `worker.js` only deletes an SQS message after the full pipeline succeeds. Failures (e.g., a Python/Docker crash) are left in the queue for retry after the 600 s visibility timeout. If a message references a file that no longer exists in S3 (`NoSuchKey`), the worker deletes the "ghost" message to break the loop.
- **Cost**: instances are Graviton/arm64 spot instances (c7g/c8g) with `priceCapacityOptimized` allocation and are cheaper than x86 on-demand. EBS is 10 GB gp3 and deleted on termination.
- **Security considerations**: the TIFF bucket is intentionally public for uploads (public-read policy, permissive CORS) — restrict if your use case demands private uploads. SSH ingress is open to `0.0.0.0/0`; consider locking it to your IP. The worker uses managed policies (`AmazonS3FullAccess`, `AmazonSQSFullAccess`) — tighten to least-privilege for production hardening.
- **ECR helper**: the user-data script configures the ECR credential helper so `docker run --pull=always` on bootstrapped instances can pull the image without a manual login.