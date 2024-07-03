#!/usr/bin/env bash
set -euxo pipefail

readonly KUBECONFIG_FILE="$HOME/.kube/config"

# Check if the kubeconfig file exists, if not, exit with an error
if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo "kubeconfig file does not exist."
    exit 1
fi

# Configuration
readonly VELERO_RESOURCE_GROUP="lb_Velero_Backups"
readonly VELERO_STORAGE_ACCOUNT="lbvelerobackup"
readonly VELERO_SA_BLOB_CONTAINER="lbvelerobackupcontainer"
readonly REGION="eastus"
readonly VELERO_VERSION="1.9.5"
readonly VELERO_PLUGIN_VERSION="v1.9.0"

# Create Resource Group
echo "Creating Resource Group: $VELERO_RESOURCE_GROUP..."
az group create -n "$VELERO_RESOURCE_GROUP" --location "$REGION"

# Check if the storage account already exists.
accountCheck=$(az storage account check-name --name $VELERO_STORAGE_ACCOUNT --query 'nameAvailable' -o tsv)

if [ "$accountCheck" == "true" ]; then
    echo "Storage account $StorageAccountName does not exist. Creating..."
    # Create the storage account.
    az storage account create --name "$VELERO_STORAGE_ACCOUNT" --resource-group "$VELERO_RESOURCE_GROUP" --location "$REGION" --kind StorageV2 --sku Standard_LRS --encryption-services blob --access-tier Hot
    echo "Storage account $VELERO_STORAGE_ACCOUNT created."
else
    echo "Storage account $VELERO_STORAGE_ACCOUNT already exists."
fi

# Create Storage Account
#echo "Creating Storage Account: $VELERO_STORAGE_ACCOUNT..."
#az storage account create --name "$VELERO_STORAGE_ACCOUNT" --resource-group "$VELERO_RESOURCE_GROUP" --location "$REGION" --kind StorageV2 --sku Standard_LRS --encryption-services blob --https-only true --access-tier Hot

## Create Blob Container
#az storage container create --name "$VELERO_SA_BLOB_CONTAINER" --public-access off --account-name "$VELERO_STORAGE_ACCOUNT"

# Get the account key.
AccountKey=$(az storage account keys list --resource-group $VELERO_RESOURCE_GROUP --account-name $VELERO_STORAGE_ACCOUNT --query '[0].value' -o tsv)

# Check if the blob container exists.
containerExists=$(az storage container exists --name $VELERO_SA_BLOB_CONTAINER --account-name $VELERO_STORAGE_ACCOUNT --account-key $AccountKey --query exists -o tsv)

if [ "$containerExists" != "true" ]; then
    echo "Container $VELERO_SA_BLOB_CONTAINER does not exist in storage account $VELERO_STORAGE_ACCOUNT. Creating..."
    # Optional: Create the container if it does not exist
    az storage container create --name $ContainerName --account-name $VELERO_STORAGE_ACCOUNT --account-key $AccountKey
    echo "Container $VELERO_SA_BLOB_CONTAINER created."
fi

# Download Velero
echo "Downloading Velero version $VELERO_VERSION..."
curl -LO "https://github.com/vmware-tanzu/velero/releases/download/v$VELERO_VERSION/velero-v$VELERO_VERSION-linux-amd64.tar.gz"
tar -xvf "velero-v$VELERO_VERSION-linux-amd64.tar.gz"
mv "velero-v$VELERO_VERSION-linux-amd64/velero" /usr/local/bin
rm "velero-v$VELERO_VERSION-linux-amd64.tar.gz"

# Prepare Azure credentials for Velero.
AZURE_SUBSCRIPTION_ID=$(az account list --query '[?isDefault].id' -o tsv)
AZURE_TENANT_ID=$(az account list --query '[?isDefault].tenantId' -o tsv)
AZURE_CLIENT_SECRET=$(az ad sp create-for-rbac -n "$VELERO_STORAGE_ACCOUNT" --role contributor --query password --output tsv --scopes "/subscriptions/$AZURE_SUBSCRIPTION_ID")
AZURE_CLIENT_ID=$(az ad sp list --display-name "$VELERO_STORAGE_ACCOUNT" --query '[0].appId' -o tsv)

# Retrieve AKS details.
#AKS_Cluster_Name=$(kubectl config view --minify -o jsonpath='{.contexts[0].context.cluster}')
AKS_Cluster_Name=$(az aks list --resource-group "lb-Privacy-RG"  --query "[0].name" -o tsv)
AKS_Resource_Group=$(az aks list --query "[?name == '$AKS_Cluster_Name'].resourceGroup" -o tsv)
AZURE_AKS_RESOURCE_GROUP=$(az aks show --query nodeResourceGroup --name "$AKS_Cluster_Name" --resource-group "$AKS_Resource_Group" --output tsv)

# Write credentials to file
cat << EOF > /tmp/credentials-velero
AZURE_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID
AZURE_TENANT_ID=$AZURE_TENANT_ID
AZURE_CLIENT_ID=$AZURE_CLIENT_ID
AZURE_CLIENT_SECRET=$AZURE_CLIENT_SECRET
AZURE_RESOURCE_GROUP=$AZURE_AKS_RESOURCE_GROUP
AZURE_CLOUD_NAME=AzurePublicCloud
EOF

# Install Velero
echo "Installing Velero..."
velero install --provider azure --plugins "velero/velero-plugin-for-microsoft-azure:$VELERO_PLUGIN_VERSION" --bucket "$VELERO_SA_BLOB_CONTAINER" --secret-file /tmp/credentials-velero --backup-location-config resourceGroup="$VELERO_RESOURCE_GROUP",storageAccount="$VELERO_STORAGE_ACCOUNT",subscriptionId="$AZURE_SUBSCRIPTION_ID" --use-restic --snapshot-location-config apiTimeout=5m,resourceGroup="$VELERO_RESOURCE_GROUP",subscriptionId="$AZURE_SUBSCRIPTION_ID"

rm /tmp/credentials-velero

# Verify Velero installation
echo "Verifying Velero installation..."
kubectl get all -n velero

# Backup commands (demonstration purposes - uncomment to use)
# velero backup create backup03 --include-namespaces lb --include-cluster-resources --default-volumes-to-restic

# Get existing backups if any
echo "Looking for any existing backup if found in the azure container"
velero get backups
sleep 10
# velero backup describe backup03
# velero backup logs backup03

# Restore from backup
# velero restore create --from-backup backup03

echo "Velero installation and configuration complete."
