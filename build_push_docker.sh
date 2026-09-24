#!/bin/bash

echo "Building and pushing Docker image for python-make-transparent"
docker buildx build --platform linux/arm64 --no-cache -t python-make-transparent:latest . 

echo "Tagging Docker image" # Replace 'your-ecr-registry' with your actual ECR registry URL
docker tag python-make-transparent:latest your-ecr-registry/python-make-transparent-registry:latest

echo "Pushing Docker image" # Replace 'your-ecr-registry' with your actual ECR registry URL
docker push your-ecr-registry/python-make-transparent-registry:latest 