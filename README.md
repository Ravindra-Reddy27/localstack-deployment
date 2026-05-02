#  Production-Ready Cloud Deployment Pipeline (LocalStack)

This repository contains a comprehensive, production-ready cloud deployment pipeline built entirely locally using **LocalStack**. It demonstrates senior-level cloud engineering practices, including multi-stage Docker optimization, Infrastructure as Code (IaC), advanced auto-scaling, disaster recovery (DR) automation, and FinOps cost reporting.

---

##  Architecture & Technologies

- **Cloud Emulation:** LocalStack  
- **Application:** Python FastAPI  
- **Containerization:** Docker & Docker Compose (Multi-stage builds)  
- **Infrastructure as Code (IaC):** AWS CLI & Bash (`setup.sh`)  
- **FinOps / AWS SDK:** Python `boto3`  
- **AWS Services Emulated:**  
  - VPC  
  - ACM  
  - ALB  
  - EC2 (Launch Templates)  
  - Auto Scaling Groups (ASG)  
  - AWS Backup  
  - EBS  

---

##  Prerequisites

Before you begin, ensure you have the following installed:

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (running)  
- [Git](https://git-scm.com/)  
- [Python 3.x](https://www.python.org/downloads/)  
- `pip` (Python package installer)

---

##  Quick Start Guide

###  Step 1: Clone the Repository

```bash
git clone https://github.com/Ravindra-Reddy27/localstack-deployment.git
cd localstack-deployment
```
---

### Step 2: Create env file
From the `.env.example` file is provided, you can copy it:

```bash
cp .example.env .env
```

Then update the values in .env ( Localstack auth token ).


---

###  Step 3: Spin Up the Environment

Start LocalStack, build the optimized FastAPI image, and provision infrastructure:

```bash
docker-compose up --build -d
```
Note: The aws_setup container waits for LocalStack to become healthy, executes setup.sh, and then exits cleanly.

---

###  Step 4: Verify the Optimized Docker Image

```bash
docker images localstack-deployment-app:latest
```

Expected: Image size around 50–60MB (optimized multi-stage build)

---
###  Step 5: Verify Application & Load Balancer

Test HTTP (Should return 301 redirect)
```bash
curl.exe -I "http://my-app-alb.elb.localhost.localstack.cloud:4566"
```

Test HTTPS (Should return app response)

```bash
curl.exe --insecure "https://my-app-alb.elb.localhost.localstack.cloud:4566"
```

---

##  Advanced Configurations & Testing

###  Step 5: Apply Auto-Scaling Policies

#### 1. Target Tracking (Reactive Scaling)

```bash
aws --endpoint-url=http://localhost:4566 autoscaling put-scaling-policy `
--auto-scaling-group-name my-app-asg `
--policy-name cpu-target-tracking `
--policy-type TargetTrackingScaling `
--target-tracking-configuration file://target-tracking-policy.json
  ```

#### 2. Predictive Scaling (Proactive Scaling)

```bash
aws --endpoint-url=http://localhost:4566 autoscaling put-scaling-policy `
--auto-scaling-group-name my-app-asg `
--policy-name my-predictive-policy `
--policy-type PredictiveScaling `
--predictive-scaling-configuration file://predictive-scaling-policy.json
```
---

### Step 6: Execute Disaster Recovery (DR) Drill

Copy script into container
```bash
docker cp run_dr_drill.sh localstack_main:/run_dr_drill.sh
```
Execute DR drill
```bash
docker exec `
-e AWS_ACCESS_KEY_ID=test `
-e AWS_SECRET_ACCESS_KEY=test `
-e AWS_DEFAULT_REGION=us-east-1 `
localstack_main `
bash -c "sed -i 's/\r$//' /run_dr_drill.sh && bash /run_dr_drill.sh"
```
 Expected Output: DR Drill Successful. Restored Volume ID: vol-xxxx

---

###  Step 7: Generate FinOps Cost Report


If boto3 package is not installed, install it using `pip install boto3`command.
```bash
python generate_cost_report.py
```
 Output file: cost_report.csv

---

##  Cleanup
To stop and remove everything:

```bash
docker-compose down -v
```
