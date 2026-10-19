#!/usr/bin/env bash

# A Kubernetes scheduler based on horoscope compatibility

set -eo pipefail
# set -x

SERVER="${SERVER:-localhost:8001}"
SCHEDULER="${SCHEDULER:-horoscopeScheduler}"

# Zodiac date ranges using start_month start_day end_month end_day
# Format: sm sd em ed
ZODIAC_BOUNDS=(
  "3 21 4 19"   # Aries: Mar 21 - Apr 19
  "4 20 5 20"   # Taurus: Apr 20 - May 20
  "5 21 6 20"   # Gemini: May 21 - Jun 20
  "6 21 7 22"   # Cancer: Jun 21 - Jul 22
  "7 23 8 22"   # Leo: Jul 23 - Aug 22
  "8 23 9 22"   # Virgo: Aug 23 - Sep 22
  "9 23 10 22"  # Libra: Sep 23 - Oct 22
  "10 23 11 21" # Scorpio: Oct 23 - Nov 21
  "11 22 12 21" # Sagittarius: Nov 22 - Dec 21
  "12 22 1 19"  # Capricorn: Dec 22 - Jan 19
  "1 20 2 18"   # Aquarius: Jan 20 - Feb 18
  "2 19 3 20"   # Pisces: Feb 19 - Mar 20
)

ZODIAC_NAMES=(
  "aries"
  "taurus"
  "gemini"
  "cancer"
  "leo"
  "virgo"
  "libra"
  "scorpio"
  "sagittarius"
  "capricorn"
  "aquarius"
  "pisces"
)

# Compatibility mapping: pod sign -> compatible node sign (by index)
# For fun, we use a simple circular offset: each sign is compatible with the sign 4 ahead
# Aries (0) -> Leo (4), Taurus (1) -> Virgo (5), Gemini (2) -> Libra (6),
# Cancer (3) -> Scorpio (7), Leo (4) -> Sagittarius (8), Virgo (5) -> Capricorn (9),
# Libra (6) -> Aquarius (10), Scorpio (7) -> Pisces (11), Sagittarius (8) -> Aries (0),
# Capricorn (9) -> Taurus (1), Aquarius (10) -> Gemini (2), Pisces (11) -> Cancer (3)
COMPATIBLE=(4 5 6 7 8 9 10 11 0 1 2 3)

# Helper: get zodiac index from month and day
get_zodiac() {
  local month="$1"
  local day="$2"

  for i in "${!ZODIAC_BOUNDS[@]}"; do
    local entry="${ZODIAC_BOUNDS[$i]}"
    local sm="${entry% *}"
    local rest="${entry#* }"
    local sd="${rest% *}"
    rest="${rest#* }"
    local em="${rest% *}"
    local ed="${rest##* }"

    # Handle year-crossing signs (Capricorn: Dec 22 - Jan 19)
    if [ "$em" -lt "$sm" ]; then
      # Crossover: if month >= start_month (Dec) or month <= end_month (Jan)
      if [ "$month" -ge "$sm" ] || [ "$month" -le "$em" ]; then
        if [ "$month" -eq "$sm" ] && [ "$day" -ge "$sd" ]; then
          echo "$i"
          return
        fi
        if [ "$month" -eq "$em" ] && [ "$day" -le "$ed" ]; then
          echo "$i"
          return
        fi
      fi
    else
      # Normal sign (no year crossing)
      if [ "$month" -eq "$sm" ] && [ "$day" -ge "$sd" ]; then
        echo "$i"
        return
      fi
      if [ "$month" -eq "$em" ] && [ "$day" -le "$ed" ]; then
        echo "$i"
        return
      fi
      # Months strictly between start and end month
      if [ "$month" -gt "$sm" ] && [ "$month" -lt "$em" ]; then
        echo "$i"
        return
      fi
    fi
  done

  # Fallback: should not happen
  echo "-1"
}

# Get the zodiac index for a given Kubernetes resource (pod or node)
# Uses creationTimestamp from the resource
get_resource_zodiac() {
  local kind="$1"   # "pod" or "node"
  local name="$2"
  local namespace="$3"  # empty for nodes

  local creation
  if [ "$kind" = "node" ]; then
    creation=$(kubectl --server "${SERVER}" get node "${name}" \
                --output jsonpath='{.metadata.creationTimestamp}')
  else
    creation=$(kubectl --server "${SERVER}" get pod "${name}" \
                --namespace "${namespace}" \
                --output jsonpath='{.metadata.creationTimestamp}')
  fi

  if [ -z "${creation}" ]; then
    echo "-1"
    return
  fi

  local month day
  month=$(echo "${creation}" | cut -d'-' -f2 | sed 's/^0*//')
  day=$(echo "${creation}" | cut -d'-' -f3 | cut -d'T' -f1 | sed 's/^0*//')

  get_zodiac "${month}" "${day}"
}

while true; do
  # Get all pending pods
  for POD in $(kubectl --server ${SERVER} get pods \
              --output jsonpath='{.items..metadata.name}' \
              --all-namespaces \
              --field-selector=status.phase==Pending); do

    SCHEDULER_NAME=$(kubectl get pod ${POD} \
                    --output jsonpath='{.spec.schedulerName}')

    if [ "${SCHEDULER_NAME}" == "${SCHEDULER}" ]; then
      NAMESPACE=$(kubectl get pod ${POD} \
                  --output jsonpath='{.metadata.namespace}')

      # Get pod's zodiac
      POD_ZODIAC=$(get_resource_zodiac "pod" "${POD}" "${NAMESPACE}")
      if [ "${POD_ZODIAC}" = "-1" ]; then
        echo "Could not determine zodiac for pod ${POD}, skipping"
        continue
      fi

      # Determine compatible zodiac index
      COMPATIBLE_INDEX="${COMPATIBLE[$POD_ZODIAC]}"
      COMPATIBLE_NAME="${ZODIAC_NAMES[$COMPATIBLE_INDEX]}"

      echo "Pod ${POD} zodiac: ${ZODIAC_NAMES[$POD_ZODIAC]}, compatible with: ${COMPATIBLE_NAME}"

      # Wait for a compatible node to appear (the stars must align)
      COMPATIBLE_NODE=""
      while [ -z "${COMPATIBLE_NODE}" ]; do
        ALL_NODES=($(kubectl --server ${SERVER} get nodes \
                     --output jsonpath='{.items..metadata.name}'))

        for NODE in "${ALL_NODES[@]}"; do
          NODE_ZODIAC=$(get_resource_zodiac "node" "${NODE}" "")
          if [ "${NODE_ZODIAC}" = "${COMPATIBLE_INDEX}" ]; then
            COMPATIBLE_NODE="${NODE}"
            break
          fi
        done

        if [ -z "${COMPATIBLE_NODE}" ]; then
          echo "No node with compatible zodiac ${COMPATIBLE_NAME} exists yet. Waiting for the stars to align..."
          sleep 6s
        fi
      done

      NODE="${COMPATIBLE_NODE}"

      # Bind pod to node
      curl --silent --fail \
        --header "Content-Type:application/json" \
        --request POST \
        --data '{"apiVersion":"v1",
                "kind": "Binding",
                "metadata": {
                  "name": "'${POD}'"
                  },
                "target": {
                  "apiVersion": "v1",
                  "kind": "Node",
                  "name": "'${NODE}'"
                  }
                }' \
        http://${SERVER}/api/v1/namespaces/${NAMESPACE}/pods/${POD}/binding/ >/dev/null \
        && echo "Assigned ${POD} to ${NODE} (compatible zodiac ${COMPATIBLE_NAME})" \
        || echo "Failed to assign ${POD} to ${NODE}"
    fi
  done
  echo "Nothing to do...sleeping."
  sleep 6s
done
