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
| `aws_security_group.EC2_SG` | Instance firewall — HTTP, HTTPS, SSH in; all out |
| `data.aws_ami.ubuntu` | Resolves the latest Canonical Ubuntu 24.04 AMI at plan time |
| `aws_instance.project1_ec2_instance` | `t3.micro` running the LAMP stack |
| `aws_eip.project1_eip` | Static public IP so the address survives stop/start |

## Prerequisites

- Terraform ≥ 1.0
- AWS CLI configured with credentials (`aws configure`)
- An existing EC2 key pair in the target region (this config expects one named `1PU`)

## Usage

```bash
cd terraform

terraform init
terraform plan
terraform apply
```

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
├── variables.tf     # Input variables (region)
├── vpc.tf           # VPC, subnets, gateways, route tables
├── main.tf          # AMI lookup, EC2 instance, Elastic IP
├── iam.tf           # Security group
└── outputs.tf       # VPC and subnet IDs
```

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

- [ ] Restrict SSH ingress to a single admin IP instead of `0.0.0.0/0`
- [ ] Add a second subnet in another AZ (RDS requires a subnet group spanning two)
- [ ] Move MySQL to RDS in the private subnet
- [ ] Add HTTPS via ACM and an Application Load Balancer
- [ ] Automate server provisioning with `user_data` or Ansible
- [ ] Move Terraform state to an S3 backend with DynamoDB locking
