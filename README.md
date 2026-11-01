# Secure Backend Service Example

## Project

This project provides Azure Functions for managing products.

### Available Endpoints

- `GET /api/products` - List all products (supports OAuth2 token with optional `read:products` scope)
- `POST /api/products` - Upsert (create or update) a product
- `PUT /api/products` - Upsert (create or update) a product

### OAuth2 Token Validation and Price Redaction

The `GET /api/products` endpoint supports optional OAuth2 access token validation using the `jose` library.

- **Without a valid token**: Products are returned with `pricePence` set to `null` (prices are redacted).
- **With a valid token but missing `read:products` scope**: Products are returned with `pricePence` set to `null`.
- **With a valid token and `read:products` scope**: Products are returned with actual prices.

OAuth2 token validation must be enabled via configuration (see below).

## Local Setup

1. Install dependencies:

```bash
npm install
```

2. Create your local settings file:

Copy the template to create your local development settings:

```bash
cp local.settings.template.json local.settings.json
```

> **Note:** Never commit your `local.settings.json` to source control. The template is safe to share.

3. Build the project:

```bash
npm run build
```

## Local testing with curl

### Start the Function App

```bash
npm start
```

The function app will start on `http://localhost:7071`.

### List Products

Split the VS Code terminal so you can see the output from the localling running app whilst having a new shell prompt to make a test HTTP call:

```bash
curl -i http://localhost:7071/api/products
```

The fake repo initialises empty, so expect an empty array of products.

### Upsert a Product

Using the sample data file (and a new bash terminal):

```bash
curl -i -X POST http://localhost:7071/api/products \
  -H "Content-Type: application/json" \
  -d @samples/product-post.json
```

Repeating the list products call should now show the new item.

## Azure Setup

All Azure infrastructure is provisioned with Terraform, from the [infra/](infra/) folder. See [infra/README.md](infra/README.md) for the full list of resources and the free-tier cost notes.

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) 1.6 or later
- Azure CLI (Terraform uses its sign-in)
- Azure Functions Core Tools (`func`), installed as a dev dependency by `npm install`

### Sign into Azure CLI

1. Ensure you are signed in, and point Terraform at your subscription:

```bash
az login
az account show
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

2. Ensure you know which locations (e.g. uksouth) you are permitted to use:

```bash
az policy assignment list \
  --query "[?name.contains(@, 'sys.regionrestriction')].parameters.listOfAllowedLocations.value | []" \
  -o tsv
```

### Configure the deployment

Create your variables file from the template:

```bash
cp infra/terraform.tfvars.example infra/terraform.tfvars
```

Edit `infra/terraform.tfvars`:

- `location`: one of your permitted locations. Choose it before the first `apply`: changing it later destroys and recreates every resource.
- `cors_allowed_origins`: origins allowed to call the API, e.g. `["http://localhost:5173"]`.
- `oauth2_*`: see [OAuth2 Access Tokens](#oauth2-access-tokens).
- `product_updated_*`: see [Product Updated Notifications](#product-updated-notifications).

> **Note:** `terraform.tfvars` is git-ignored because it can contain secrets. Never commit it.

Resource names are generated with a random 6-character suffix, so they follow our naming convention and are globally unique:

- `shopping-lab-<suffix>-rg`
- `shoppinglab<suffix>funcsa`
- `products-lab-<suffix>-func`

### Create the infrastructure

```bash
terraform -chdir=infra init
terraform -chdir=infra plan
terraform -chdir=infra apply
```

This creates the resource group, storage account, Flex Consumption plan, Function App (Node.js, Functions v4) and Application Insights. It also applies the CORS and app settings from `terraform.tfvars`.

> **Important:** the Terraform state (`infra/terraform.tfstate`) records what was created. Keep it, as Terraform needs it to update or destroy the resources.

### Publish the Project to Azure

Build and deploy your code to the Function App:

```bash
npm run build
func azure functionapp publish $(terraform -chdir=infra output -raw function_app_name)
```

You can now access your endpoints at:

```bash
terraform -chdir=infra output products_url
```

### Read the host auth key

```bash
terraform -chdir=infra output -raw master_key
```

This key will need to be shared with any backend service that needs to call `upsertProduct`. Calls to `upsertProduct` must include the key in the `x-functions-key` HTTP header. A narrower key is also available with `terraform -chdir=infra output -raw default_function_key`.

### Change configuration

To change any setting (CORS, OAuth2, notifications), edit `infra/terraform.tfvars` and run `terraform -chdir=infra apply` again. Azure restarts the Function App automatically when its app settings change.

Avoid changing settings with `az functionapp config appsettings set` or in the portal: the next `terraform apply` overwrites them.

### Tear down

```bash
terraform -chdir=infra destroy
```

## Product Updated Notifications

This service emits a "product updated" integration event after a successful upsert.

- Default behaviour: uses a dummy adapter that logs the event to the console.
- HTTP adapter: enabled when the environment variable `PRODUCT_UPDATED_BASE_URL` is set.

When enabled, the service will POST to:

- `POST ${PRODUCT_UPDATED_BASE_URL}/integration/events/product-updated`

with a JSON body shaped as:

```
{
  "id": "string",
  "name": "string",
  "pricePence": 1234,
  "description": "string",
  "updatedAt": "2025-01-01T12:34:56.000Z" // ISO string
}
```

### Configure locally

Update `local.settings.json` (created from the template) to include the base URL of your receiver. If your receiver is an Azure Function protected by a host key, also include the key. The adapter uses the `x-functions-key` header automatically.

```
{
  "IsEncrypted": false,
  "Values": {
    "FUNCTIONS_WORKER_RUNTIME": "node",
    "PRODUCT_UPDATED_BASE_URL": "https://your-receiver.azurewebsites.net",
    "PRODUCT_UPDATED_KEY": "<your-host-key>"
  }
}
```

Remove `PRODUCT_UPDATED_BASE_URL` (or leave it empty) to fall back to the dummy logger.

### Configure in Azure

Set `product_updated_base_url` in `infra/terraform.tfvars` to the receiver's base URL. If your receiver requires a host key, also set `product_updated_key`. Then apply:

```hcl
product_updated_base_url = "https://your-receiver.azurewebsites.net"
product_updated_key      = "<your-host-key>"
```

```bash
terraform -chdir=infra apply
```

The app will automatically switch to the HTTP adapter at startup. Leave both values empty to use the dummy logger.

## Auth0 Setup

### 1. Create an Auth0 Tenancy (if you don't have one already)

Visit [auth0.com](https://auth0.com/) and sign-up. Create and name your first tenancy following our usual naming conventions, for example `shopping-dev-ab47`.

### 2. Sign-in to Auth0 CLI

In the VSCode terminal:

```bash
auth0 login
```

Confirm your Auth0 domain (e.g. shopping-dev-ab47.uk.auth0.com):

```bash
auth0 tenants list
```

Keep a note of your domain as you will need it later.

### 3. Register an API (resource server)

Call you api registration something like `products-dev-api`. Use something like `https://products.shopping.thamco.com` for the identifier (it looks like a domain name but doesn't need to actually exist).

```bash
auth0 apis create \
 --name <your-api-name> \
 --identifier <your-api-identifier> \
 --scopes "read:products" \
 --no-input \
 --json
```

> The `identifier` will become the audience (`aud`) for the access tokens your app acquires to access your backend service.

The `scopes` above are examples and can be changed to match your needs.

Since you are the frontend app and backend api author, you can skip requesting user consent to use the API: In the Auth0 web dashboard: APIs → your API → Settings → Access Settings → “Allow Skipping User Consent”.

To use role based access control with your api it will need enabling in the Auth0 web dashboard: APIs → your API → Settings → RBAC Settings → “Enable RBAC” and “Add Permissions in the Access Token”.

### 4. Give users permission to use the API

A role can include one or more API permissions (scopes).

> You must have enabled RBAC on your API (above) for these steps to work.

Create a role (if you don’t have one):

```bash
auth0 roles create \
  --name "ProductReader" \
  --description "Can read products including prices"
```

Assign API scopes (permissions) to the role (if you've just created one):

```bash
auth0 roles permissions add <ROLE_ID> \
  --api-id <API_ID> \
  --permissions "read:products"
```

Again, the permissions above are examples to be tailored for your needs.

Create a test user (if you don't already have one):

```bash
auth0 users create \
  --connection-name "Username-Password-Authentication" \
  --email "testuser1@example.com" \
  --password "P@ssw0rd!" \
  --no-input
```

Note the user id as you'll need it below.

Assign the role to a user:

```bash
auth0 users roles add "<USER_ID>" --roles <ROLE_ID>
```

Now that user has all permissions associated with the role — and when they log in, Auth0 includes those permissions in their access token if you’ve enabled “Add Permissions in the Access Token” for that API.

## OAuth2 Access Tokens

> You must have an auth server (see Auth0 setup above).

To enable OAuth2 validation, set the following environment variables:

- `OAUTH2_JWKS_URI`: The JWKS endpoint URL for your OAuth2 provider (e.g., `https://your-tenant.auth0.com/.well-known/jwks.json`)
- `OAUTH2_ISSUER`: The expected token issuer (e.g., `https://your-tenant.auth0.com/`)
- `OAUTH2_AUDIENCE`: The expected audience/API identifier (e.g., `https://products.shopping.thamco.com`)

If these variables are not set, the endpoint still works but treats all requests as unauthenticated (prices will be redacted).

### Local Configuration

Update `local.settings.json`:

```json
{
  "IsEncrypted": false,
  "Values": {
    "FUNCTIONS_WORKER_RUNTIME": "node",
    "OAUTH2_JWKS_URI": "https://your-tenant.auth0.com/.well-known/jwks.json",
    "OAUTH2_ISSUER": "https://your-tenant.auth0.com/",
    "OAUTH2_AUDIENCE": "https://products.shopping.thamco.com"
  }
}
```

### Azure Configuration

Set the OAuth2 values in `infra/terraform.tfvars` and apply:

```hcl
oauth2_jwks_uri = "https://your-tenant.auth0.com/.well-known/jwks.json"
oauth2_issuer   = "https://your-tenant.auth0.com/"
oauth2_audience = "https://products.shopping.thamco.com"
```

```bash
terraform -chdir=infra apply
```

### Testing with a Token

To test with an OAuth2 access token, include it in the `Authorization` header:

```bash
curl -i http://localhost:7071/api/products \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

The token must:

- Be signed by the configured issuer
- Have the configured audience
- Be valid (not expired)
- Include the `read:products` scope (either in the `scope` or `scp` claim) to see actual prices

Tokens can be obtained using Postman, but it will probably be easier to test via the products app.
