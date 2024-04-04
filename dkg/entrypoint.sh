#!/bin/sh

OPERATOR_CONFIG_DIR=${OPERATOR_DATA_DIR}/config
DKG_CONFIG_DIR=${DKG_DATA_DIR}/config
DKG_LOGS_DIR=${DKG_DATA_DIR}/logs
DKG_OUTPUT_DIR=${DKG_DATA_DIR}/output
DKG_DB_PATH=${DKG_DATA_DIR}/db

PRIVATE_KEY_FILE=${OPERATOR_CONFIG_DIR}/encrypted_private_key.json
PRIVATE_KEY_PASSWORD_FILE=${OPERATOR_CONFIG_DIR}/private_key_password
OPERATOR_ID_FILE=${OPERATOR_CONFIG_DIR}/operator_id.txt
DKG_CONFIG_FILE=${DKG_CONFIG_DIR}/dkg-config.yml
DKG_LOG_FILE=${DKG_LOGS_DIR}/dkg.log

mkdir -p ${DKG_CONFIG_DIR} ${DKG_LOGS_DIR} ${DKG_OUTPUT_DIR}

# Wait indefinitely for the private key file to be created using inotifywait.
echo "[INFO] Waiting for the operator service to create the private key file..."
while [ ! -f "${PRIVATE_KEY_FILE}" ]; do
    echo "[INFO] Waiting for ${PRIVATE_KEY_FILE} to be created..."
    inotifywait -e create -qq $(dirname "${PRIVATE_KEY_FILE}")
done

echo "[INFO] Private key file found."

# Immediately check for the password file; log an error and exit with status 0 if not found.
if [ ! -f "${PRIVATE_KEY_PASSWORD_FILE}" ]; then
    echo "[ERROR] ${PRIVATE_KEY_PASSWORD_FILE} not found. Cannot continue without the private key password file."
    exit 0
fi

if [ -z "${OPERATOR_ID}" ]; then

    # Read operator ID from the file if it exists and is not empty
    if [ -f "${OPERATOR_ID_FILE}" ] && [ -s "${OPERATOR_ID_FILE}" ]; then
        OPERATOR_ID=$(cat ${OPERATOR_ID_FILE})
        echo "[INFO] Using OPERATOR_ID from the file: ${OPERATOR_ID}"
    else
        echo "[INFO] OPERATOR_ID not provided. Fetching OPERATOR_ID from the API..."

        PUBLIC_KEY=$(jq -r '.publicKey' ${PRIVATE_KEY_FILE})

        # Fetch the operator ID using the public key
        RESPONSE=$(curl -s "https://api.ssv.network/api/v4/${NETWORK}/operators/public_key/${PUBLIC_KEY}")

        # Check if RESPONSE is successfully retrieved
        if [[ "${RESPONSE}" == *'"error"'* ]]; then
            echo "[ERROR] Failed to fetch the API. Set OPERATOR_ID manually in the package config to perform the DKG."
            exit 0
        else
            OPERATOR_ID=$(echo "${RESPONSE}" | jq -r '.data.id')

            # Check if OPERATOR_ID is successfully retrieved
            if [ -z "${OPERATOR_ID}" ] || [ "${OPERATOR_ID}" = "null" ]; then

                # Fetching Operator ID AGAIN
                echo "[ERROR] Failed to fetch OPERATOR_ID from the API. Trying again in 5 minutes."
                RESPONSE=$(curl --connect-timeout 5 \
                    --silent \
                    --retry 1 \
                    --retry-delay 300 "https://api.ssv.network/api/v4/${NETWORK}/operators/public_key/${PUBLIC_KEY}")

                OPERATOR_ID=$(echo "${RESPONSE}" | jq -r '.data.id')

                # Check if OPERATOR_ID is successfully retrieved AGAIN
                if [ -z "${OPERATOR_ID}" ] || [ "${OPERATOR_ID}" = "null" ]; then
                    echo "[ERROR] Failed to fetch the OPERATOR_ID from the API. Add it manually in the package config or restart the package to perform the DKG."
                    exit 1
                else
                    echo "[INFO] Successfully fetched OPERATOR_ID: ${OPERATOR_ID}"
                    echo "${OPERATOR_ID}" >${OPERATOR_ID_FILE}
                fi

            else
                echo "[INFO] Successfully fetched OPERATOR_ID: ${OPERATOR_ID}"
                echo "${OPERATOR_ID}" >${OPERATOR_ID_FILE}
            fi
        fi
    fi
else
    echo "[INFO] Using provided OPERATOR_ID: ${OPERATOR_ID}"
    echo "${OPERATOR_ID}" >${OPERATOR_ID_FILE}
fi

exec /bin/ssv-dkg start-operator \
    --operatorID ${OPERATOR_ID} \
    --configPath ${DKG_CONFIG_FILE} \
    --logFilePath ${DKG_LOG_FILE} \
    --logLevel ${LOG_LEVEL} \
    --outputPath ${DKG_OUTPUT_DIR} \
    --port ${DKG_PORT} \
    --privKey ${PRIVATE_KEY_FILE} \
    --privKeyPassword ${PRIVATE_KEY_PASSWORD_FILE}
