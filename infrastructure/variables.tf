variable "region" {
  description = "AWS region where the infrastructure lives"
  type        = string
  default     = "ap-southeast-3"
}

variable "vpc_id" {
  description = "VPC where the worker instances will run"
  type        = string
  default     = "vpc-0c561d1c60f78671f"
}

variable "subnet_ids" {
  description = "Subnets (one per AZ) that the Spot Fleet can use"
  type        = list(string)
  default = [
    "subnet-0478260065ee7b401",
    "subnet-0aaa21abcd819fe27",
    "subnet-018779ce4a05373c2",
  ]
}

variable "worker_ami" {
  description = "AMI for worker instances (must be arm64 to match c7g/c8g)"
  type        = string
  default     = "ami-0d7b8466440ab90ea"
}

variable "key_name" {
  description = "EC2 key pair name used for SSH access"
  type        = string
  default     = "mapidkeypair"
}

variable "instance_types" {
  description = "Instance types offered as Spot Fleet overrides"
  type        = list(string)
  default = [
    "c7g.large",
    "c7g.xlarge",
    "c7g.2xlarge",
    "c8g.large",
    "c8g.xlarge",
    "c8g.2xlarge",
  ]
}

variable "mapid_bucket_name" {
  description = "Public bucket receiving TIFF uploads under the tiff/ prefix"
  type        = string
  default     = "hki-mapid"
}

variable "source_bucket_name" {
  description = "Private bucket holding the worker source code (worker.js, package.json)"
  type        = string
  default     = "hki-worker-source-code-392987323540-ap-southeast-3-an"
}

variable "queue_name" {
  description = "SQS queue that receives S3 upload events"
  type        = string
  default     = "hki-upload-file-queue"
}

variable "queue_visibility_timeout" {
  description = "Visibility timeout in seconds; gdal2tiles is slow, so keep it high to avoid duplicate processing"
  type        = number
  default     = 600
}

variable "ecr_repository_name" {
  description = "ECR repository name for the make_transparent processing image"
  type        = string
  default     = "python-make-transparent-registry"
}

variable "ecr_image_tag" {
  description = "Image tag pulled by the worker"
  type        = string
  default     = "latest"
}

variable "owner_tag" {
  description = "Value for the Owner tag"
  type        = string
  default     = "firman_devops"
}

variable "project_tag" {
  description = "Value for the Project tag"
  type        = string
  default     = "async-tiff-processor"
}