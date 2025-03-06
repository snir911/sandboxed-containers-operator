#!/bin/bash
# FILEPATH: aws-podvm-image-handler.sh

# This script is used to create or delete AWS AMI for podvm
# The basic assumption is that the required variables are set as environment variables in the pod
# Typically the variables are read from configmaps and set as environment variables in the pod
# The script will be called with one of the following options:
# Create image (-c)
# Delete image (-C)

[[ "$DEBUG" == "true" ]] && set -x

# include common functions from lib.sh
# shellcheck source=/dev/null
# The directory is where aws-podvm-image-handler.sh is located
source "$(dirname "$0")"/lib.sh

# Function to verify that the required variables are set

function verify_vars() {
    # Ensure CLOUD_PROVIDER is set to aws
    [[ -z "${CLOUD_PROVIDER}" || "${CLOUD_PROVIDER}" != "aws" ]] && error_exit "CLOUD_PROVIDER is empty or not set to aws"

    [[ -z "${AWS_ACCESS_KEY_ID}" ]] && error_exit "AWS_ACCESS_KEY_ID is not set"
    [[ -z "${AWS_SECRET_ACCESS_KEY}" ]] && error_exit "AWS_SECRET_ACCESS_KEY is not set"

    # Packer variables
    [[ -z "${INSTANCE_TYPE}" ]] && error_exit "INSTANCE_TYPE is not set"
    [[ -z "${PODVM_DISTRO}" ]] && error_exit "PODVM_DISTRO is not set"

    # if AWS_REGION is empty, try to get it from the metadata service
    if [[ ! "${AWS_REGION}" ]]; then
        AWS_REGION=$(curl -m 30 -s --show-error http://169.254.169.254/latest/meta-data/placement/region ||
            error_exit "Failed to get AWS_REGION from metadata service")
        export AWS_REGION
    fi
    [[ ! "${AWS_REGION}" ]] && error_exit "AWS_REGION is not set"

    # If AWS_VPC_ID is empty, try to get it from the metadata service
    if [[ ! "${AWS_VPC_ID}" ]]; then
        MAC=$(curl -m 3 -s http://169.254.169.254/latest/meta-data/mac ||
            error_exit "Failed to get MAC from metadata service")

        [[ "${MAC}" ]] && error_exit "MAC is not set"

        AWS_VPC_ID=$(curl -m 30 -s --show-error http://169.254.169.254/latest/meta-data/network/interfaces/macs/"${MAC}"/vpc-id ||
            error_exit "Failed to get AWS_VPC_ID from metadata service")
        export AWS_VPC_ID
    fi
    [[ ! "${AWS_VPC_ID}" ]] && error_exit "AWS_VPC_ID is not set"

    # If AWS_SUBNET_ID is empty, try to get it from the metadata service
    if [[ ! "${AWS_SUBNET_ID}" ]]; then
        MAC=$(curl -m 3 -s http://169.254.169.254/latest/meta-data/mac ||
            error_exit "Failed to get MAC from metadata service")

        [[ "${MAC}" ]] && error_exit "MAC is not set"

        AWS_SUBNET_ID=$(curl -m 30 -s --show-error http://169.254.169.254/latest/meta-data/network/interfaces/macs/"${MAC}"/subnet-id ||
            error_exit "Failed to get AWS_SUBNET_ID from metadata service")
        export AWS_SUBNET_ID
    fi
    [[ ! "${AWS_SUBNET_ID}" ]] && error_exit "AWS_SUBNET_ID is not set"

    [[ -z "${AMI_BASE_NAME}" ]] && error_exit "AMI_BASE_NAME is not set"
    [[ -z "${AMI_VERSION_MAJ_MIN}" ]] && error_exit "AMI_VERSION_MAJ_MIN is not set"
    [[ -z "${AMI_VOLUME_SIZE}" ]] && error_exit "AMI_VOLUME_SIZE is not set"

    [[ -z "${PODVM_DISTRO}" ]] && error_exit "PODVM_DISTRO is not set"
    [[ -z "${DISABLE_CLOUD_CONFIG}" ]] && error_exit "DISABLE_CLOUD_CONFIG is not set"

    [[ -z "${CAA_SRC}" ]] && error_exit "CAA_SRC is empty"
    [[ -z "${CAA_REF}" ]] && error_exit "CAA_REF is empty"

    # Ensure booleans are set
    [[ -z "${INSTALL_PACKAGES}" ]] && error_exit "INSTALL_PACKAGES is empty"
    [[ -z "${DOWNLOAD_SOURCES}" ]] && error_exit "DOWNLOAD_SOURCES is empty"
    [[ -z "${CONFIDENTIAL_COMPUTE_ENABLED}" ]] && error_exit "CONFIDENTIAL_COMPUTE_ENABLED is empty"
    [[ -z "${DISABLE_CLOUD_CONFIG}" ]] && error_exit "DISABLE_CLOUD_CONFIG is empty"
    [[ -z "${ENABLE_NVIDIA_GPU}" ]] && error_exit "ENABLE_NVIDIA_GPU is empty"
}

# function to download and install aws cli

function install_aws_cli() {
    # Install aws cli
    # If any error occurs, exit the script with an error message

    # Check if aws cli is already installed
    if command -v aws &>/dev/null; then
        echo "aws cli is already installed"
        return
    fi

    # Download aws cli v2
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip" ||
        error_exit "Failed to download aws cli"

    # Install aws cli v2
    unzip -q -o "/tmp/awscliv2.zip" -d "/tmp" ||
        error_exit "Failed to unzip aws cli"
    /tmp/aws/install ||
        error_exit "Failed to install aws cli"

    # Clean up temporary files
    rm -f "/tmp/awscliv2.zip"
}

# Function to use packer to create AWS ami

function create_ami_using_packer() {
    echo "Creating AWS AMI using packer"

    # Create AWS image using packer
    # If any error occurs, exit the script with an error message
    # The variables are set before calling the function

    # If PODVM_DISTRO is not set to rhel then exit
    [[ "${PODVM_DISTRO}" != "rhel" ]] && error_exit "unsupport distro"

    # Set the packer variables

    export PKR_VAR_instance_type="${INSTANCE_TYPE}"
    export PKR_VAR_region="${AWS_REGION}"
    export PKR_VAR_vpc_id="${AWS_VPC_ID}"
    export PKR_VAR_subnet_id="${AWS_SUBNET_ID}"
    export PKR_VAR_ami_name="${AMI_NAME}"
    export PKR_VAR_volume_size="${AMI_VOLUME_SIZE}"

    # The makefile in aws/image directory is explicitly using these
    # TBD: fix the makefile
    export IMAGE_NAME="${AMI_NAME}"
    export VOL_SIZE="${AMI_VOLUME_SIZE}"

    cd "${CAA_SRC_DIR}"/aws/image ||
        error_exit "Failed to change directory to ${CAA_SRC_DIR}/aws/image"
    packer init "${PODVM_DISTRO}"/
    make BINARIES= PAUSE_BUNDLE= image

    # Wait for the ami to be created

}

function set_ami_name() {
    # Set the AMI version
    # It should follow the Major(int).Minor(int).Patch(int)
    AMI_VERSION="${AMI_VERSION_MAJ_MIN}.$(date +'%Y%m%d%S')"
    export AMI_VERSION

    # Set the image name
    AMI_NAME="${AMI_BASE_NAME}-${AMI_VERSION}"
    export AMI_NAME
}

# Function to get the ami id of the newly created image

function get_ami_id() {
    echo "Getting the ami id"

    # Get the ami id of the newly created image
    # If any error occurs, exit the script with an error message

    # Get the ami id
    AMI_ID=$(aws ec2 describe-images --region "${AWS_REGION}" --filters "Name=name,Values=${AMI_NAME}" --query 'Images[*].ImageId' --output text) ||
        error_exit "Failed to get the ami id"

    # Set the ami id as an environment variable
    export AMI_ID

    echo "ID of the newly created ami: ${AMI_ID}"

}

# Function to get all the ami ids for the given base name

function get_all_ami_ids() {
    echo "Getting all ami ids"

    # Get all the ami ids for the given base name
    # If any error occurs, exit the script with an error message

    # Get the ami id list
    AMI_ID_LIST=$(aws ec2 describe-images --region "${AWS_REGION}" --filters "Name=name,Values=${AMI_BASE_NAME}-*" --query 'Images[*].ImageId' --output text) ||
        error_exit "Failed to get the ami id list"

    # Set the ami id list as an environment variable
    export AMI_ID_LIST

    # Display the list of amis
    echo "${AMI_ID_LIST}"

}

# Function to convert bootc container image to cloud image
# Input:
# 1. container_image_repo_url: The registry URL of the source container image.
# 2. image_tag: The tag of the source container image.
# 3. auth_json_file (can be empty): Path to the registry secret file to use for downloading the image.
# 4. aws_ami_name: Name for the AMI in AWS
# 5. aws_bucket: Target S3 bucket name for intermediate storage when creating AMI (bucket must exist)
# Output: ami

function bootc_to_ami() {
    container_image_repo_url="${1}"
    image_tag="${2}"
    auth_json_file="${3}"
    aws_ami_name="${4}"
    aws_bucket="${5}" # bucket must exist

    [[ -n "$AWS_ACCESS_KEY_ID" ]] && [[ -n "$AWS_SECRET_ACCESS_KEY" ]] && [[ -n "$AWS_REGION" ]] || error_exit "bootc_to_ami failed: AWS_* keys or AWS_REGION are missing"
    # TODO: check permissions
    run_args="--env AWS_ACCESS_KEY_ID --env AWS_SECRET_ACCESS_KEY"
    bib_args="--type ami --aws-ami-name ${aws_ami_name} --aws-bucket ${aws_bucket} --aws-region ${AWS_REGION}"
    bootc_image_builder_conversion "${container_image_repo_url}" "${image_tag}" "${auth_json_file}" "${run_args}" "${bib_args}"
}

# Function to create or update podvm-images configmap with all the amis
# Input AMI_ID_LIST is a list of ami ids

function create_or_update_image_configmap() {
    echo "Creating or updating podvm-images configmap"

    # Check if the podvm-images configmap already exists
    # If exists get the current value of the aws key and append the new ami id to it
    # If not exists, create the podvm-images configmap with the new ami id

    # Check if the podvm-images configmap exists
    if kubectl get configmap podvm-images -n openshift-sandboxed-containers-operator >/dev/null 2>&1; then
        # Get the current value of the aws key in podvm-images configmap
        AMI_ID_LIST=$(kubectl get configmap podvm-images -n openshift-sandboxed-containers-operator -o jsonpath='{.data.aws}' ||
            error_exit "Failed to get the current value of the aws key in podvm-images configmap")

        # If the current value of the aws key is empty, then set the value to the new ami id
        if [[ -z "${AMI_ID_LIST}" ]]; then
            AMI_ID_LIST="${AMI_ID}"
        else
            # If the current value of the aws key is not empty, then append the new ami id in the beginning
            # The first ami id in the list is the latest ami id
            AMI_ID_LIST="${AMI_ID} ${AMI_ID_LIST}"
        fi
    else
        # If the podvm-images configmap does not exist, set the value to the new ami id
        AMI_ID_LIST="${AMI_ID}"
    fi

    kubectl create configmap podvm-images \
        -n openshift-sandboxed-containers-operator \
        --from-literal=aws="${AMI_ID_LIST}" \
        --dry-run=client -o yaml |
        kubectl apply -f - ||
        error_exit "Failed to create or update podvm-images configmap"

}

# Funtion to recreate podvm-images configmap with all the amis

function recreate_image_configmap() {
    echo "Recreating podvm-images configmap"

    # Get list of all ami ids
    get_all_ami_ids

    # Check if IMAGE_ID_LIST is empty
    [[ -z "${AMI_ID_LIST}" ]] && error_exit "Nothing to recreate in podvm-images configmap"

    kubectl create configmap podvm-images \
        -n openshift-sandboxed-containers-operator \
        --from-literal=aws="${AMI_ID_LIST}" \
        --dry-run=client -o yaml |
        kubectl apply -f - ||
        error_exit "Failed to recreate podvm-images configmap"

    echo "podvm-images configmap recreated successfully"
}

# Function to add the ami id as annotation in the peer-pods-cm configmap

function add_ami_id_annotation_to_peer_pods_cm() {
    echo "Adding ami id to peer-pods-cm configmap"

    # Check if the peer-pods-cm configmap exists
    if ! kubectl get configmap peer-pods-cm -n openshift-sandboxed-containers-operator >/dev/null 2>&1; then
        echo "peer-pods-cm configmap does not exist. Skipping adding the ami id"
        return
    fi

    # Add the ami id as annotation to peer-pods-cm configmap
    # Overwrite any existing values
    kubectl annotate --overwrite configmap peer-pods-cm -n openshift-sandboxed-containers-operator \
        "LATEST_AMI_ID=${AMI_ID}" ||
        error_exit "Failed to add the ami id as annotation to peer-pods-cm configmap"

    echo "AMI id added as annotation to peer-pods-cm configmap successfully"
}

# Function to delete the LATEST_AMI_ID annotation from the peer-pods-cm configmap

function delete_ami_id_annotation_from_peer_pods_cm() {
    echo "Deleting ami id annotation from peer-pods-cm configmap"

    # Check if the peer-pods-cm configmap exists
    if ! kubectl get configmap peer-pods-cm -n openshift-sandboxed-containers-operator >/dev/null 2>&1; then
        echo "peer-pods-cm configmap does not exist. Skipping deleting the ami id"
        return
    fi

    # Delete the ami id annotation from peer-pods-cm configmap
    kubectl annotate configmap peer-pods-cm -n openshift-sandboxed-containers-operator \
        "LATEST_AMI_ID-" ||
        error_exit "Failed to delete the ami id annotation from peer-pods-cm configmap"

    echo "Ami id annotation deleted from peer-pods-cm configmap successfully"
}

function create_ami_from_prebuilt_artifact() {
    echo "Creating AWS AMI image from prebuilt artifact"

    echo "Pulling the podvm image from the provided path"
    image_src="/tmp/image"
    extraction_destination_path="/image"
    image_repo_auth_file="/tmp/regauth/auth.json"

    [[ ! ${BUCKET_NAME} ]] && error_exit "BUCKET_NAME is not defined"

    # Get the PODVM_IMAGE_TYPE, PODVM_IMAGE_TAG and PODVM_IMAGE_SRC_PATH
    get_image_type_url_and_path

    case "${PODVM_IMAGE_TYPE}" in
    oci) # TODO: test
        echo "Extracting the raw image from the given path."

        mkdir -p "${extraction_destination_path}" ||
            error_exit "Failed to create the image directory"

        extract_container_image "${PODVM_IMAGE_URL}" \
            "${PODVM_IMAGE_TAG}" \
            "${image_src}" \
            "${extraction_destination_path}" \
            "${image_repo_auth_file}"

        # Form the path of the podvm vhd image.
        podvm_image_path="${extraction_destination_path}/rootfs/${PODVM_IMAGE_SRC_PATH}"

        upload_image_to_s3

        register_ami
        ;;
    bootc)
        echo "Converting the bootc image to AMI"

        bootc_to_ami "${PODVM_IMAGE_URL}" "${PODVM_IMAGE_TAG}" "${image_repo_auth_file}" "${AMI_NAME}" "${BUCKET_NAME}"
        ;;
    *)
        error_exit "Currently only OCI image unpacking is supported, exiting."
        ;;
    esac
}

function upload_image_to_s3() {
    echo "Uploading the image to S3"

    # Check if the image exists
    [[ ! -f "${podvm_image_path}" ]] && error_exit "Image does not exist"

    get_podvm_image_format ${podvm_image_path}

    if [[ "${PODVM_IMAGE_FORMAT}" == "qcow2" ]]; then
        convert_qcow2_to_raw
	raw_to_upload=${RAW_IMAGE_PATH}
    elif [[ "${PODVM_IMAGE_FORMAT}" == "raw" ]]; then
	raw_to_upload=${podvm_image_path}
    else
        error_exit "Unsupported format"
    fi

    # Upload the image to S3
    aws s3 cp "${raw_to_upload}" "s3://${BUCKET_NAME}/${AMI_NAME}" ||
        error_exit "Failed to upload the image to S3"

    echo "Image uploaded to S3 successfully"
}

function register_ami() {
    echo "Starting image import..."

    local import_task_id=$(aws ec2 import-image \
        --description "podvm-image" \
        --disk-containers "file://<(echo '{\"Description\":\"podvm-image created from raw\",\"Format\":\"raw\",\"UserBucket\":{\"S3Bucket\":\"${BUCKET_NAME}\",\"S3Key\":\"${AMI_NAME}\"}}')" \
        --query 'ImportTaskId' \
        --output text)

    echo "Import task started. Task ID: $IMPORT_TASK_ID"

    echo "Monitoring the import task..."
    while true; do
        local status=$(aws ec2 describe-import-image-tasks \
            --import-task-ids "$import_task_id" \
            --query 'ImportImageTasks[0].Status' \
            --output text)

        echo "Current status: $status"

        if [[ "$status" == "completed" ]]; then
            local ami_id=$(aws ec2 describe-import-image-tasks \
                --import-task-ids "$IMPORT_TASK_ID" \
                --query 'ImportImageTasks[0].ImageId' \
                --output text)
            echo "Import completed. AMI ID: $ami_id"
            break
        elif [[ "$status" == "deleted" || "$status" == "cancelled" ]]; then
            echo "Import task failed or was cancelled."
            exit 1
        fi

        sleep 15
    done

    #  Tag the AMI
    aws ec2 create-tags --resources "$ami_id" --tags Key="name",Value="${AMI_NAME}"
    echo "Tags added successfully."
}

function create_ami_from_scratch() {
    echo "Creating AWS AMI from scratch"

    # Create the AWS image
    # If any error occurs, exit the script with an error message

    if [[ "${DOWNLOAD_SOURCES}" == "yes" ]]; then
        # Download source code from GitHub
        download_source_code
    fi

    # Prepare the source code for building the ami
    prepare_source_code

    # Prepare the pause image for embedding into the ami
    download_and_extract_pause_image "${PAUSE_IMAGE_REPO}" "${PAUSE_IMAGE_VERSION}" "${CLUSTER_PULL_SECRET_AUTH_FILE}"

    # Create AWS ami using packer
    create_ami_using_packer
}

# Function to create the ami in AWS

function create_ami() {
    echo "Creating AWS AMI"

    # Create the AWS image
    # If any error occurs, exit the script with an error message

    # Install packages if INSTALL_PACKAGES is set to yes
    if [[ "${INSTALL_PACKAGES}" == "yes" ]]; then
        # Install required rpm packages
        install_rpm_packages

        # Install required binary packages
        install_binary_packages
    fi

    # generate & set the ami name
    set_ami_name

    if [[ "${IMAGE_TYPE}" == "operator-built" ]]; then
        create_ami_from_scratch
    elif [[ "${IMAGE_TYPE}" == "pre-built" ]]; then
        create_ami_from_prebuilt_artifact
    fi

    # Get the ami id of the newly created image
    # This will set the AMI_ID environment variable
    get_ami_id

    # Add the ami id as annotation to peer-pods-cm configmap
    add_ami_id_annotation_to_peer_pods_cm

}

# Function to delete the ami's snapshots
# SNAPSHOT_IDS must be set as an environment variable

function delete_ami_snapshots() {
    echo "Deleting AWS AMIs snapshots"

    # SNAPSHOT_IDS shouldn't be empty
    [[ -z "${SNAPSHOT_IDS}" ]] && error_exit "SNAPSHOT_IDS is empty"

    SNAPSHOT_IDS_LIST=($SNAPSHOT_IDS)
    for SNAPSHOT_ID in "${SNAPSHOT_IDS_LIST[@]}"; do

        # Delete the associated snapshot
        aws ec2 delete-snapshot --region "${AWS_REGION}" --snapshot-id "${SNAPSHOT_ID}" ||
            error_exit "Failed to delete snapshot '${SNAPSHOT_ID}'"

        # Validate the snapshot was deleted
        snapshot_description=$(
            aws ec2 describe-snapshots \
            --region "${AWS_REGION}" \
            --filters "Name=snapshot-id,Values='${SNAPSHOT_ID}'" \
            --query "Snapshots" \
            --output text
        ) || error_exit "Failed to get the ami's snapshot description"
        if [[ -n "$snapshot_description" ]]; then
            error_exit "Snapshot '${SNAPSHOT_ID}' still exists after deletion attempt"
        else
            echo "Snapshot '${SNAPSHOT_ID}' successfully deleted"
        fi
    done
}

# Function to delete the ami
# AMI_ID must be set as an environment variable

function delete_ami_using_id() {
    echo "Deleting AWS AMI"

    # Delete the AMI
    # If any error occurs, exit the script with an error message

    # AMI_ID shouldn't be empty
    [[ -z "${AMI_ID}" ]] && error_exit "AMI_ID is empty"

    # Retrieve the associated snapshots before deleting the ami
    SNAPSHOT_IDS_JSON_PATH='Images[].BlockDeviceMappings[].Ebs.SnapshotId'
    SNAPSHOT_IDS=$(
        aws ec2 describe-images \
        --region "${AWS_REGION}" \
        --image-ids "${AMI_ID}" \
        --query "${SNAPSHOT_IDS_JSON_PATH}" \
        --output text
    ) || error_exit "Failed to get the ami's snapshot ids"
    export SNAPSHOT_IDS

    # Delete the ami
    aws ec2 deregister-image --region "${AWS_REGION}" --image-id "${AMI_ID}" ||
        error_exit "Failed to delete the ami"

    # Delete the amis snapshots
    delete_ami_snapshots

    # Remove the ami id annotation from peer-pods-cm configmap
    delete_ami_id_annotation_from_peer_pods_cm

}

# display help message

function display_help() {
    echo "This script is used to create AWS ami for podvm"
    echo "Usage: $0 [-c|-C] [-- install_binaries|install_rpms|install_cli]"
    echo "Options:"
    echo "-c  Create image"
    echo "-C  Delete image"
    echo "-R Recreate podvm-images configMap"
}

# main function

if [ "$#" -eq 0 ]; then
    display_help
    exit 1
fi

if [ "$1" = "--" ]; then
    shift
    # Handle positional parameters
    case "$1" in

    install_binaries)
        install_binary_packages
        ;;
    install_rpms)
        install_rpm_packages
        ;;
    install_cli)
        install_aws_cli
        ;;
    *)
        echo "Unknown argument: $1"
        exit 1
        ;;
    esac
else
    while getopts "cCRh" opt; do
        verify_vars
        case ${opt} in
        c)
            # Create the ami
            create_ami
            ;;
        C)
            # Delete the ami
            delete_ami_using_id

            ;;
        R)
            # Recreate the podvm-images configmap
            recreate_image_configmap
            ;;
        h)
            # Display help
            display_help
            exit 0
            ;;
        *)
            # Invalid option
            display_help
            exit 1
            ;;
        esac
    done
fi
