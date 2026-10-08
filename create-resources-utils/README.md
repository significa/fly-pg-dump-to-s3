# Create Resources Utils

Utilities to easily create resources, permissions and credentials on Fly.io, AWS and Postgres.

Both backup methods authenticate to AWS with **OIDC**, so there are no AWS access keys
anywhere. The only difference between them is who AWS trusts:

| | Trusted identity provider | Subject (`sub`) |
| --- | --- | --- |
| **Method 1** (GitHub Actions) | `token.actions.githubusercontent.com` | `repo:<org>/<repo>:ref:refs/heads/<branch>` |
| **Method 2** (Fly worker) | `oidc.fly.io/<org-slug>` | `<org-slug>:<app-name>:<machine-id>` |

## Requirements

These dependencies must be present on the system

- jq
- aws-cli version 2
- aws (authenticated with buckets and IAM management permissions)
- flyctl (authenticated)

## 1. Create the backups bucket

`./create-aws-bucket.sh`

Creates the bucket, enables versioning and sets a lifecycle rule to expire old backups
(`BACKUP_RETENTION_DAYS`, 60 by default).

Output:

```
BACKUP_CONFIGURATION_NAMES=STAGING,PRODUCTION
STAGING_S3_DESTINATION=s3://example-bucket/project-name-db-backup-staging.tar.gz
PRODUCTION_S3_DESTINATION=s3://example-bucket/project-name-db-backup-production.tar.gz
```

## 2. Create the OIDC identity provider

`./setup-aws-oidc-provider.sh <fly|github>`

- `github` — trusts GitHub Actions. One time per AWS account.
- `fly` — trusts a Fly organization, asks for the org slug. One time per AWS account **and**
  Fly org.

If the provider already exists the script says so and exits successfully, move on.

## 3. Create the IAM role

`./create-aws-role.sh <fly|github> [bucket-name]`

Creates a role trusted by that identity provider, with write-only access to the backups
bucket. It asks for the role name and for the **subject**, which restricts who can assume it.
The script prints the format and examples for the provider you picked:

```
# github
repo:significa/sample:ref:refs/heads/main
repo:significa/sample@XXXXXX:ref:refs/heads/main   # repos with a name suffix, paste as is

# fly
significa:sample-db-backup-worker:*                # any machine of the worker app
significa:sample-db-backup-worker:148e2d1bc23198
```

The GitHub subject is matched **exactly** (`StringEquals`). `workflow_dispatch` and `schedule`
runs use the repository default branch, so `refs/heads/main` is what you want unless the
workflow lives elsewhere. To allow more refs, edit the trust policy afterwards and swap the
condition for `StringLike`.

The Fly subject is matched with `StringLike`, since machine ids change on every deploy, so
keep the trailing `*`.

Output:

```
AWS_ROLE_ARN=arn:aws:iam::123456789012:role/sample-db-backup-role
```

## 4. Create the database user and grant permissions

`./grant-db-permissions.sh`

1. Creates `db_backup_worker`
2. Grants read access to the listed databases

It prints the connection URL for both methods, pick the one matching your setup:

```
--- Method 1: backup from GitHub Actions (connects via `flyctl proxy`, host is localhost)
[ENV]_DATABASE_URL=postgres://db_backup_worker:password@localhost:5432/database_name

--- Method 2: backup from a Fly worker app (connects over the Fly private network)
[ENV]_DATABASE_URL=postgres://db_backup_worker:password@example-db.flycast:5432/database_name
```

## 5a. Method 1 — create the Fly deploy token

`./create-fly-deploy-token.sh`

The Fly deploy token is the only long lived secret of this setup: GitHub Actions needs it to
run `flyctl proxy` against the database.

Output:

```
FLY_API_TOKEN=FlyV1 ...
```

Then set these repository secrets in GitHub:

| Secret | Where it came from |
| --- | --- |
| `DB_BACKUP_FLY_API_TOKEN` | step 5a |
| `DB_BACKUP_DATABASE_URL` | step 4 (with the `localhost` host) |
| `DB_BACKUP_S3_DESTINATION_URL` | step 1 |
| `DB_BACKUP_AWS_ROLE_ARN` | step 3 |

And add the workflow, as documented in the
[root README](../README.md#method-1-simple-github-actions-backup).

## 5b. Method 2 — create the Fly backup worker

`./create-fly-backup-worker.sh`

Creates the database backup worker app on fly.io.

Setting `AWS_ROLE_ARN` on the app is all it takes for the worker to reach S3: Fly's init
writes the OIDC token and points the AWS CLI at it, no access keys involved.

```
fly -a [db-backup-worker-app] secrets import < .env
fly -a [db-backup-worker-app] deploy --remote-only
```

With a `.env` like:

```env
AWS_ROLE_ARN=arn:aws:iam::123456789012:role/sample-db-backup-role
AWS_REGION=eu-central-1
DATABASE_URL=postgres://db_backup_worker:password@example-db.flycast:5432/database_name
S3_DESTINATION=s3://sample-db-backups/backup.tar.gz
```

Note that the subject used in step 3 must match this app, for example
`significa:sample-db-backup-worker:*`.
