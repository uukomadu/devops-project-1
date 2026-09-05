# Migrating a Legacy System to AWS

Terraform-provisioned AWS infrastructure hosting a WordPress site on a LAMP stack, built as a hands-on cloud migration exercise: move a legacy application off an aging physical server and onto managed cloud infrastructure.

## Architecture

```
                          Internet
                              │
                    ┌─────────┴─────────┐
                    │  Internet Gateway │
                    │   (Project1-IGW)  │
                    └─────────┬─────────┘
                              │
┌─────────────────────────────┼──────────────────────────────┐
│ VPC  10.0.0.0/16            │            (Project1-VPC)    │
│                             │                              │
│  ┌──────────────────────────┴───────────────────────────┐  │
│  │ Public subnet  10.0.1.0/24                           │  │
│  │                                                      │  │
│  │   ┌────────────────┐        ┌──────────────────┐     │  │
│  │   │  EC2 t3.micro  │        │   NAT Gateway    │     │  │
│  │   │  Ubuntu 24.04  │        │   + Elastic IP   │     │  │
│  │   │                │        └────────┬─────────┘     │  │
│  │   │  Apache        │                 │               │  │
│  │   │  PHP           │                 │               │  │
│  │   │  MySQL         │                 │               │  │
│  │   │  WordPress     │                 │               │  │
│  │   │  + Elastic IP  │                 │               │  │
│  │   └────────────────┘                 │               │  │
│  └──────────────────────────────────────┼───────────────┘  │
│                                         │                  │
│  ┌──────────────────────────────────────┼───────────────┐  │
│  │ Private subnet  10.0.2.0/24          │               │  │
│  │                                      ▼               │  │
│  │   (reserved for a future RDS tier — outbound only)   │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

**Traffic flow:** the public route table sends `0.0.0.0/0` to the internet gateway, giving the web server two-way reachability. The private route table sends `0.0.0.0/0` to the NAT gateway, which permits outbound connections only — nothing on the internet can initiate a connection inward.

## Components

| Resource | Purpose |
|---|---|
| `aws_vpc.main` | Isolated network, `10.0.0.0/16`, DNS support and hostnames enabled |
| `aws_subnet.public` | `10.0.1.0/24` — hosts the web server and NAT gateway |
| `aws_subnet.private` | `10.0.2.0/24` — reserved for a future database tier |
| `aws_internet_gateway.main` | Two-way internet access for the public subnet |
| `aws_nat_gateway.main` + `aws_eip.nat` | Outbound-only internet for the private subnet |
| `aws_route_table.public` / `.private` | Default routes to IGW and NAT respectively |
| `aws_route_table_association.*` | Binds each subnet to its route table |
| `aws_security_group.EC2_SG` | Instance firewall — HTTP and HTTPS from anywhere, SSH from `admin_cidr` only; outbound 80 and 443 only |
| `data.aws_ami.ubuntu` | Resolves the latest Canonical Ubuntu 24.04 AMI at plan time |
| `aws_instance.project1_ec2_instance` | `t3.micro` running the LAMP stack — IMDSv2 required, encrypted root volume, detailed monitoring |
| `aws_eip.project1_eip` | Static public IP so the address survives stop/start |

## Prerequisites

- Terraform ≥ 1.0 (1.15.8 is what the lock file and CI use)
- AWS CLI configured with credentials (`aws configure`)
- An existing EC2 key pair in the target region (this config expects one named `1PU`)
- Docker, if you want to run the security gate locally (`make scan`)

## Usage

```bash
cd terraform
cp example.tfvars terraform.tfvars   # set admin_cidr to your own IP as a /32

terraform init
terraform plan
terraform apply
```

`admin_cidr` has no default and rejects `0.0.0.0/0`, so `plan` stops with a
validation error until a real address is given. `terraform.tfvars` is gitignored.

Then connect and build the stack:

```bash
ssh -i ~/.ssh/<your-key>.pem ubuntu@<public-ip>
```

### Server provisioning

```bash
# System packages
sudo apt update && sudo apt upgrade -y
sudo apt install apache2 php libapache2-mod-php php-mysql mysql-server -y

sudo systemctl enable --now apache2 mysql
sudo mysql_secure_installation

# WordPress
cd /tmp
wget https://wordpress.org/latest.tar.gz
tar -xvzf latest.tar.gz
sudo mv wordpress/* /var/www/html/
sudo chown -R www-data:www-data /var/www/html/
sudo chmod -R 755 /var/www/html/
sudo rm -f /var/www/html/index.html
```

### Database setup

```sql
CREATE DATABASE wordpress_db;
CREATE USER 'wordpress_user'@'localhost' IDENTIFIED BY '<strong-password>';
GRANT ALL PRIVILEGES ON wordpress_db.* TO 'wordpress_user'@'localhost';
FLUSH PRIVILEGES;
```

Then point WordPress at it:

```bash
sudo mv /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
sudo nano /var/www/html/wp-config.php   # set DB_NAME, DB_USER, DB_PASSWORD
sudo systemctl restart apache2
```

Finish the install at `http://<public-ip>`.

## Project structure

```
terraform/
├── providers.tf     # AWS provider and version constraints
├── variables.tf     # Input variables (region, admin_cidr)
├── example.tfvars   # Copy to terraform.tfvars and edit
├── vpc.tf           # VPC, subnets, gateways, route tables
├── main.tf          # AMI lookup, EC2 instance, Elastic IP
├── iam.tf           # Security group
└── outputs.tf       # VPC and subnet IDs
checks.txt           # The checkov checks the build fails on
scan.sh              # Runs them from a pinned Docker image
Makefile             # scan, scan-full, fmt, validate, all
output/              # Recorded output of a real run of the gate
.github/workflows/   # The same three steps in CI
```

## Security gate

The Terraform is scanned with checkov 3.3.16 on every push and pull request,
using the same 16-check allowlist as
[infrastructure-guardrails/terraform-security-gate](https://github.com/uukomadu/infrastructure-guardrails/tree/main/terraform-security-gate).
`make scan` runs it locally from the pinned image; `make scan-full` shows every
finding, including the ones the build does not fail on.

> **Scope, stated up front:** the gate is static analysis. Everything below was
> verified with checkov, `terraform validate` and a read-only `terraform plan`;
> the changes have not been applied to the account. The plan is recorded in
> [`output/security-gate-observed.txt`](output/security-gate-observed.txt).

### What it found in this code

Running the gate against `main` before any changes: 5 of 16 checks failed,
all in `iam.tf` and `main.tf`. An unfiltered scan reported 11.

| Check | Finding | What changed |
| --- | --- | --- |
| `CKV_AWS_24` | SSH ingress from `0.0.0.0/0`. The rule's own description said "admin only"; the CIDR said everyone. | `cidr_blocks = [var.admin_cidr]`. The variable has no default and a validation block that rejects `0.0.0.0/0`, so the wildcard cannot come back through a tfvars file. |
| `CKV_AWS_382` | Egress `-1` to `0.0.0.0/0`. | Two named rules: TCP 80 and TCP 443 outbound. That is what the provisioning steps use — apt through Ubuntu's EC2 mirrors is plain HTTP, WordPress downloads over HTTPS. DNS to the VPC resolver is not subject to security group rules and needs no rule. |
| `CKV_AWS_79` | IMDSv1 allowed. | `metadata_options` with `http_tokens = "required"` and hop limit 1. A WordPress site is a stack of PHP plugins, which is exactly where SSRF bugs live; IMDSv2 turns "read the instance credentials" into a 401. |
| `CKV_AWS_8` | Unencrypted root volume, which is where MySQL and the WordPress tree live. | `root_block_device { encrypted = true }`, `gp3`. |
| `CKV_AWS_126` | Detailed monitoring off. | `monitoring = true`. This is a cost decision more than a security one: seven CloudWatch metrics per instance at the per-metric rate, small next to the NAT gateway. Enabled because one-minute metrics are worth it when this instance is the whole site. |

Two things to know before applying this to an instance that already exists:

- **`root_block_device` is a replacing change.** Terraform destroys and recreates
  the instance; the MySQL data and the WordPress tree on the old root volume go
  with it. Snapshot first, or apply this on a fresh stack. Note that the AMI
  lookup uses `most_recent = true`, so any plan on a stale instance may already
  be a replacement for that reason alone.
- **The narrowed egress was not exercised against a live instance.** Port 80 and
  443 outbound covers `apt` and `wget` as written in the README. If something
  else turns out to need outbound access, add a named rule; do not reopen `-1`.

### What the gate did not catch, and why that is fine

Alongside the scan, `terraform fmt -check` exited 3 on `main.tf` and `vpc.tf`
(alignment only; fixed) and `terraform validate` was already clean.

After the fixes, `make scan-full` reports 5 findings outside the allowlist. None
of them fail the build, and each has a reason:

| Check | Why it is out of scope |
| --- | --- |
| `CKV_AWS_260` ingress `0.0.0.0/0` to port 80 | Intentional. It is a public web server. Written down here rather than suppressed inline, so the same check still fires if it ever appears on a database security group. |
| `CKV_AWS_135` EBS optimized | `t3` instances are EBS-optimized by default; the check does not model that. |
| `CKV2_AWS_41` IAM role on instance | The instance does not call AWS APIs; there is nothing for a role to grant. Would be required the moment it does (S3 backups, SSM). |
| `CKV2_AWS_12` default SG restricted | Genuine gap. The default security group is never attached here, but restricting it is cheap and belongs in the roadmap. |
| `CKV2_AWS_11` VPC flow logs | Genuine gap with a real per-GB cost, so it is an org logging decision rather than a default for a single-instance site. |

### Proving the validation works

```
$ terraform plan -var admin_cidr=0.0.0.0/0
Error: Invalid value for variable
admin_cidr must be a valid IPv4 CIDR and must not be 0.0.0.0/0. Use your own
address as a /32.
exit 1

$ terraform plan -var-file=example.tfvars
Plan: 13 to add, 0 to change, 0 to destroy.
exit 0
```

### Verified against

Terraform 1.15.8 · checkov 3.3.16 (pinned in `scan.sh`) · Docker 29.7.2 · macOS 14 arm64
· AWS provider 6.61.0, locked for `linux_amd64`, `darwin_arm64` and `darwin_amd64`
so CI and a laptop run `init` against the same lock file without `-upgrade`. A
fourth hash, `linux_arm64`, was added by `make validate` itself: the Terraform
image on an Apple Silicon host is a Linux arm64 binary, and `init` records the
hash for whatever platform it runs on.

## Notes and gotchas

Things that cost real time while building this, recorded so they don't cost it twice:

- **A route table is public or private by its *target*, not its CIDR.** Both tables use `0.0.0.0/0`; what distinguishes them is `gateway_id` (IGW) versus `nat_gateway_id` (NAT). Pointing the private table at the IGW silently makes the subnet public.
- **Route table associations are separate resources.** Without `aws_route_table_association`, a subnet quietly falls back to the VPC's main route table and neither custom table does anything.
- **`subnet_id` and `vpc_security_group_ids` are not optional in practice.** Omit them and the instance lands in the default VPC with the default security group, which allows no inbound traffic from outside itself — SSH times out with no useful error.
- **Security groups attach to network interfaces, not subnets.** Subnet-level filtering is a NACL. Group them by tier, and reference one group from another rather than hardcoding CIDRs.
- **The NAT gateway bills whether or not it carries traffic** — roughly $32/month plus its Elastic IP. It is orphaned cost until something actually lives in the private subnet.
- **DNS hostnames must be explicitly enabled** on the VPC (`enable_dns_hostnames = true`) or instances get no public DNS name.
- **SSH timeout vs. connection refused:** a timeout means packets were dropped (security group, routing, or an ISP blocking outbound 22). Refused means you reached the host but nothing was listening. They point at completely different problems.

## Cost and cleanup

The NAT gateway and Elastic IPs meter continuously. Tear everything down when not actively working:

```bash
terraform destroy
```

Note that deleting a NAT gateway does **not** release its Elastic IP — `terraform destroy` handles both, but a manual console deletion leaves the EIP allocated and billing.

## Roadmap

- [x] Restrict SSH ingress to a single admin IP instead of `0.0.0.0/0`
- [ ] Restrict the VPC's default security group (`CKV2_AWS_12`)
- [ ] Add a second subnet in another AZ (RDS requires a subnet group spanning two)
- [ ] Move MySQL to RDS in the private subnet
- [ ] Add HTTPS via ACM and an Application Load Balancer
- [ ] Automate server provisioning with `user_data` or Ansible
- [ ] Move Terraform state to an S3 backend with DynamoDB locking
