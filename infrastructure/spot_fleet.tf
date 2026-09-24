locals {
  # One override per (instance_type x subnet) combination
  fleet_overrides = [
    for combo in setproduct(var.instance_types, var.subnet_ids) : {
      instance_type     = combo[0]
      subnet_id         = combo[1]
      weighted_capacity = 1
    }
  ]
}

resource "aws_spot_fleet_request" "sqs_worker_fleet" {
  iam_fleet_role                      = aws_iam_role.spot_fleet_role.arn
  target_capacity                     = 1
  on_demand_target_capacity           = 0
  allocation_strategy                 = "priceCapacityOptimized"
  excess_capacity_termination_policy  = "Default"
  terminate_instances_with_expiration = true
  fleet_type                          = "maintain"
  instance_interruption_behaviour     = "terminate"
  wait_for_fulfillment                = false

  launch_template_config {
    launch_template_specification {
      id      = aws_launch_template.sqs_worker.id
      version = aws_launch_template.sqs_worker.latest_version
    }

    dynamic "overrides" {
      for_each = local.fleet_overrides
      content {
        instance_type     = overrides.value.instance_type
        subnet_id         = overrides.value.subnet_id
        weighted_capacity = overrides.value.weighted_capacity
      }
    }
  }

  tags = {
    Name    = "sqs-worker-fleet"
    Owner   = var.owner_tag
    Project = var.project_tag
  }

  depends_on = [
    aws_iam_role_policy_attachment.spot_fleet_tagging,
    aws_launch_template.sqs_worker
  ]
}