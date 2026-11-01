# Infrastructure (Terraform)

Terraform equivalent of the `az` commands in the main README's **Azure Setup** section. It creates:

- Resource group
- Storage account (required by Azure Functions)
- Flex Consumption (FC1) plan + Node.js Function App (Functions v4)
- Log Analytics workspace + Application Insights
- CORS origins and app settings (`OAUTH2_*`, `PRODUCT_UPDATED_*`)

Auth0 setup (API, roles, users) is not managed here. Follow the main README for that, then put the resulting values into `terraform.tfvars`.

## Cost / free tier

Every resource uses the cheapest option that has a free allowance:

| Resource | Configuration | Free allowance |
| --- | --- | --- |
| Resource group | n/a | Always free |
| Function App plan | Flex Consumption `FC1`, 512 MB instances, max 40 instances | 100,000 GB-s + 250,000 executions per month |
| Storage account | Standard, LRS, StorageV2 Hot | 5 GB LRS blob for 12 months on a free account; otherwise a few pence/month |
| Log Analytics | `PerGB2018`, 30-day retention | 5 GB ingestion/month, 31 days retention |
| Application Insights | Workspace-based (billed via Log Analytics) | Same 5 GB as above |

`log_daily_quota_gb` (default `0.16`) caps ingestion at about 5 GB/month, so logs stay inside the free allowance. Once the cap is reached, telemetry stops for the rest of the day.

What is not fully free: the Function App needs a storage account (the deployment package blob plus runtime blob/queue usage). At lab scale this costs pennies, but it has no permanent free tier.

Why Flex Consumption and not the classic Consumption (`Y1`) plan: many new subscriptions have a `Y1 VMs` quota of 0, so `Y1` fails with `Operation cannot be completed without additional quota`. Microsoft also recommends Flex Consumption for new apps. The App Service Free (`F1`) plan cannot host Function Apps.

## Provision

```bash
az login
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)

cd infra
cp terraform.tfvars.example terraform.tfvars   # then edit settings
terraform init
terraform plan
terraform apply
```

Resource names are generated with a random 6-character suffix (`random_string.suffix`) so they are globally unique:

- `shopping-lab-<suffix>-rg`
- `shoppinglab<suffix>funcsa`
- `products-lab-<suffix>-func`

The suffix is stored in Terraform state and stays the same across applies. Run `terraform output name_suffix` to see it.

## Deploy the code

Once the infrastructure exists, publish from the repo root as usual:

```bash
npm run build
func azure functionapp publish $(terraform -chdir=infra output -raw function_app_name)
```

Or let Terraform zip-deploy a pre-built package by setting `app_package_path`:

```bash
npm ci && npm run build && npm prune --omit=dev
zip -r app.zip host.json package.json dist node_modules
# in terraform.tfvars: app_package_path = "../app.zip"
terraform -chdir=infra apply
```

## Outputs

```bash
terraform output products_url
terraform output -raw master_key   # x-functions-key for upsertProduct
```

## Tear down

```bash
terraform destroy
```
