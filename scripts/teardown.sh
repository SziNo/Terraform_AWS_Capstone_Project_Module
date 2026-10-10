#!/bin/bash
set -euo pipefail

# Always run from the project root, wherever the script is called from
cd "$(dirname "$0")/.."

BUCKET="szino-terraform-state"
PREFIX="capstone-module/"
PATH_TO_TFSTATE="s3://$BUCKET/$PREFIX"

# 1. Terraform erőforrások törlése
terraform destroy -auto-approve

# 2. Csak a projekt saját state-jének törlése, majd a bucketé, ha üres maradt
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    echo "Törlöm a projekt state-jét: $PATH_TO_TFSTATE"
    aws s3 rm "$PATH_TO_TFSTATE" --recursive

    if aws s3 rb "s3://$BUCKET" 2>/dev/null; then
        echo "A bucket üres lett, töröltem: $BUCKET"
    else
        echo "A bucketben más state is van, a bucketet meghagyom."
    fi
else
    echo "Nincs $BUCKET bucket, kihagyom."
fi

echo "Teardown kész."