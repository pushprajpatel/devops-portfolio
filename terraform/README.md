# Terraform — Deploy StyleAI to AWS (EC2 + Auto Scaling Group)

Provisions an Application Load Balancer + Auto Scaling Group of EC2
instances that each boot up, install Docker, clone this repo, and run
`docker compose up` — the exact same stack validated locally and on
Minikube (FastAPI app + local Ollama LLM).

> ⚠️ **This creates real, billable AWS resources** (EC2, ALB). Nothing in
> this folder runs automatically — you run every command yourself, with
> your own AWS credentials. Remember to `terraform destroy` when you're
> done so you don't get charged for resources you forgot about.

## Architecture

```
Internet → ALB (port 80) → Target Group (port 8000) → ASG (1-3x EC2)
                                                          │
                                                          ├─ Docker: app container
                                                          └─ Docker: ollama container
```

Each EC2 instance is fully self-contained — it pulls the model and runs
the whole stack independently (no shared Ollama server). That keeps this
simple for a portfolio demo; a production version would split the LLM
into its own service so models aren't re-downloaded per instance.

## Prerequisites

1. **An AWS account** with billing enabled
2. **Terraform** installed: `brew install terraform` (or [terraform.io](https://terraform.io))
3. **AWS CLI configured** with credentials that can create EC2/ALB/ASG resources:
   ```bash
   brew install awscli
   aws configure   # paste your AWS Access Key ID + Secret Access Key
   ```
4. *(Optional, for SSH access)* an existing EC2 key pair in your target region

## Step-by-step

### 1. Copy and edit the variables file

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
- `aws_region` — pick a region close to you
- `instance_type` — keep `t3.large` (8GB RAM) or bigger; the model needs ~5GB+ to load
- `key_name` — your EC2 key pair name, or delete the line if you don't need SSH
- `allowed_ssh_cidr` — **set this to your own IP** (`curl ifconfig.me` to find it), never leave it open to the world
- `github_repo_url` — leave as-is, or point to your own fork

### 2. Initialize Terraform

```bash
terraform init
```

Downloads the AWS provider plugin.

### 3. Review the plan

```bash
terraform plan
```

Read through what it intends to create: 1 ALB, 1 target group, 1 launch
template, 1 Auto Scaling Group, 2 security groups. No surprises before
you commit to creating anything.

### 4. Apply

```bash
terraform apply
```

Type `yes` to confirm. Takes ~2-3 minutes for AWS resources to come up.

### 5. Wait for the app to actually be ready

```bash
terraform output app_url
```

This URL works once an instance passes its health check — but the
**first boot pulls a ~4.7GB model**, so the instance won't be marked
healthy in the target group for roughly **15-20 minutes** after launch.
Grab a coffee. You can watch progress by SSH-ing in (if you set `key_name`)
and running:

```bash
ssh ec2-user@<instance-public-ip>
sudo docker compose -f /opt/app/ai-search-service/docker-compose.yml logs -f
```

### 6. Use it

Once healthy, open `http://<alb-dns-name>` (from `terraform output app_url`)
in a browser — same StyleAI app you've been running locally, now live on
the internet behind a load balancer with auto-scaling.

### 7. Tear it down when you're done

```bash
terraform destroy
```

Type `yes` to confirm. **Do this** — an idle `t3.large` + ALB running
24/7 costs real money over time.

## What's deliberately simple here (portfolio scope, not production)

- Default VPC/subnets are used instead of a custom VPC module — fine for
  a demo, a real deployment would isolate this into its own VPC.
- Each instance runs its own Ollama — no shared model server, no
  EFS-backed shared model cache. Scaling out re-downloads the model per
  instance.
- No HTTPS/ACM certificate — the ALB listens on plain HTTP:80.
- No remote state backend (S3 + DynamoDB lock) — state is local
  (`terraform.tfstate`), fine solo, not for team use.

## Files

| File | Purpose |
|---|---|
| `main.tf` | All AWS resources — VPC data sources, security groups, ALB, target group, launch template, ASG |
| `variables.tf` | Configurable inputs (region, instance type, ASG sizing, etc.) |
| `outputs.tf` | Prints the app URL and ASG name after apply |
| `user_data.sh.tpl` | EC2 boot script — installs Docker, clones the repo, runs `docker compose up` |
| `terraform.tfvars.example` | Template for your own `terraform.tfvars` (never commit the real one) |
