# `terraform-github-pr-commenter/test/docker/README.md`

A complete test based on the [Terraform Get Started - Docker](https://developer.hashicorp.com/terraform/tutorials/docker-get-started)

1. Follow [Build Docker infrastructure using Terraform](https://developer.hashicorp.com/terraform/tutorials/docker-get-started/docker-build).
2. Generate log files with output from Terraform commands.
3. Trigger rendering and posting GitHub PR comments.
4. Follow [Change the Terraform code and the infrastructure](https://developer.hashicorp.com/terraform/tutorials/docker-get-started/docker-build).
   in order to obtain logs with different output.
   Then, repeat steps 2. and 3.

## 1. Build Infrastructure

```shell
terraform init
terraform apply
```

## 2. Generate log files

Obtain initial batch of logs using the `<ordinal>_<component>.<command>.{log,json}`
naming (see [README.md](../../README.md):

```shell
terraform validate -no-color            > 001_docker-step-2-build.validate.log
terraform fmt -no-color -check -diff    > 001_docker-step-2-build.fmt.log
terraform plan -no-color                > 001_docker-step-2-build.plan.log
terraform show -no-color -json          > 001_docker-step-2-build.plan.json
```

## 3. Post GitHub PR comment

Well, submit PR and let your pipelines run generating the log files,
then run the `terraform-pr-comment.sh` to render the comment content
and finally post the comment to GitHub using whatever mean you prefer,
e.g. Azure Pipelines task `GitHubCommenter@0`, GitHub Script or just `curl`.

## 4. Change Infrastructure

Obtain new set of logs:

```shell
terraform validate -no-color            > 002_docker-step-4-change.validate.log
terraform fmt -no-color -check -diff    > 002_docker-step-4-change.fmt.log
terraform plan -no-color                > 002_docker-step-4-change.plan.log
terraform show -no-color -json          > 002_docker-step-4-change.plan.json
```

## 5. Remove Infrastructure Resources

Delete resources from `main.tf`

- `resource "docker_image"`
- `resource "docker_container"`

and obtain logs of the new state:

```shell
terraform validate -no-color            > 003_docker-step-5-change.validate.log
terraform fmt -no-color -check -diff    > 003_docker-step-5-change.fmt.log
terraform plan -no-color                > 003_docker-step-5-change.plan.log
terraform show -no-color -json          > 003_docker-step-5-change.plan.json
```
