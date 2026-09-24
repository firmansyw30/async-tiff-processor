#!/bin/bash
set -e

source_bucket="${source_bucket}"
aws_region="${aws_region}"
sqs_queue_url="${sqs_queue_url}"
worker_docker_image="${worker_docker_image}"

echo "Installing Docker"
sudo yum install -y docker

echo "Enable Docker Service"
sudo systemctl start docker

echo "Add current User to Docker Group"
sudo usermod -aG docker $USER

echo "Install ECR Credential Helper"
sudo dnf install -y amazon-ecr-credential-helper

echo "Setup NVM for running worker code"
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.8/install.sh | bash
export NVM_DIR="$HOME/.nvm"
. "$NVM_DIR/nvm.sh"

echo "Using Node JS 22"
nvm install 22
nvm use 22
nvm alias default 22

echo "Setup ECR Helper"
mkdir -p ~/.docker
cat << EOF > ~/.docker/config.json
{
	"credsStore": "ecr-login"
}
EOF

echo "Downloading Worker Source Code"
mkdir -p /home/ec2-user/worker
aws s3 cp s3://${source_bucket}/worker.js /home/ec2-user/worker/worker.js
aws s3 cp s3://${source_bucket}/package.json /home/ec2-user/worker/package.json

echo "Writing Worker Environment"
cat << EOF > /home/ec2-user/worker/.env
SQS_QUEUE_URL=${sqs_queue_url}
AWS_REGION=${aws_region}
WORKER_DOCKER_IMAGE=${worker_docker_image}
EOF

echo "Installing Library"
cd /home/ec2-user/worker
npm install

echo "Installing PM2"
npm install -g pm2

echo "Start Worker"
pm2 start worker.js --name async-tiff-worker