#!/bin/bash
set -e

source_bucket="${source_bucket}"
aws_region="${aws_region}"
sqs_queue_url="${sqs_queue_url}"
worker_docker_image="${worker_docker_image}"

echo "Installing Docker"
sudo yum install -y docker

echo "Enable Docker Service"
sudo systemctl enable docker
sudo systemctl start docker

echo "Add ec2-user to Docker Group"
sudo usermod -aG docker ec2-user

echo "Initial Docker Setup complete"

echo "Install ECR Credential Helper"
sudo dnf install -y amazon-ecr-credential-helper

echo "Setup ECR Helper for ec2-user"
mkdir -p /home/ec2-user/.docker
cat << EOF > /home/ec2-user/.docker/config.json
{
  "credsStore": "ecr-login"
}
EOF
chown -R ec2-user:ec2-user /home/ec2-user/.docker

echo "Setup NVM for ec2-user"
su - ec2-user -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.8/install.sh | bash"

echo "Using Node JS 22"
su - ec2-user -c "source ~/.nvm/nvm.sh && nvm install 22 && nvm use 22 && nvm alias default 22"

echo "Downloading Worker Source Code"
mkdir -p /home/ec2-user/worker
aws s3 cp s3://${source_bucket}/worker.js /home/ec2-user/worker/worker.js
aws s3 cp s3://${source_bucket}/package.json /home/ec2-user/worker/package.json
chown -R ec2-user:ec2-user /home/ec2-user/worker

echo "Writing Worker Environment"
cat << EOF > /home/ec2-user/worker/.env
SQS_QUEUE_URL=${sqs_queue_url}
AWS_REGION=${aws_region}
WORKER_DOCKER_IMAGE=${worker_docker_image}
EOF

echo "Installing Library for Worker Source Code"
su - ec2-user -c "source ~/.nvm/nvm.sh && cd /home/ec2-user/worker && npm install"

echo "Installing PM2"
su - ec2-user -c "source ~/.nvm/nvm.sh && npm install -g pm2"

echo "Start Worker Code using PM2"
su - ec2-user -c "source ~/.nvm/nvm.sh && cd /home/ec2-user/worker && pm2 start worker.js --name raster-hki-sqs-worker"

echo "Save PM2 process list and enable startup"
su - ec2-user -c "source ~/.nvm/nvm.sh && pm2 save"
env PATH=$PATH:/home/ec2-user/.nvm/versions/node/v22*/bin pm2 startup systemd -u ec2-user --hp /home/ec2-user || true
