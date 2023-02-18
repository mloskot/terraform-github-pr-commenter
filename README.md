# terraform-github-pr-commenter

Bash script to render output of Terraform commands applicable as GitHub PR comment content.
The rendered content can be posted by Azure Pipeline using [GitHubComment@0]() task
or, in future, by GitHub Actions

## Requirements

- Bash
- `iconv` or `konwert` to convert the Terraform fancy outputs to plain and easily escapable ASCII.
- Terraform command output saved in `<00N>_<title>.<command>.{log,txt}` files (see [description](#description) below).

## Usage: CLI (testing)

```shell
./terraform-pr-comment.sh validate /home/mloskot/azure-infrastructure 12345
```

## Usage: CI

- for Azure Pipelines example see [.azure-pipelines.yml](.azure-pipelines.yml)

## Description

Collect output of given Terraform command from log files in given location
and render it in Markdown for PR comment,
then return it via exported environment variable.

The script renders single comment titled with given build number and command.

The script supports multiple logs from multiple runs of terraform <command>`,
e.g. separate run per directory, and each log is rendered as a separate section.

Log file name format is `<00N>_<title>.<command>.{log,txt}` where

- `<00N>` part controls order in which files are read
- `<title>` part is used as heading of section for given log
- `<command>` used in the comment title together with given build number

## Credits

- [@sbulav](https://github.com/sbulav) for [Terraform processing with `jq`](https://sbulav.github.io/terraform/terraform-vs-github-actions/)
   and showing how to use [github.issues.createComment](https://github.com/actions/github-script) from GitHub Script.
- [@nbellocam](https://github.com/nbellocam) for [Azure Pipelines task `GitHubComment@0` show case](https://medium.com/southworks/continuous-integration-for-smart-contracts-4a8b78d387c)
- [@robertwbradford](https://github.com/robertwbradford) for [solving multi-line comment with `GitHubComment@0`](https://stackoverflow.com/a/72277737/151641)
- [@robburger](https://github.com/robburger) for [terraform-pr-commenter scripted in Bash](https://github.com/robburger/terraform-pr-commenter/blob/10779c60059f0f099ef676a9dde158d646555473/entrypoint.sh)
