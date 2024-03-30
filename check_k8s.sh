#!/bin/bash

pods=$(kubectl get pods --all-namespaces -o custom-columns=:metadata.name,:metadata.namespace --no-headers)

while IFS= read -r line; do
  pod_name=$(echo $line | awk '{print $1}')
  namespace=$(echo $line | awk '{print $2}')

  containers=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.spec.containers[*].name}')

  for container in $containers; do
    echo "Checking container $container in pod $pod_name, namespace $namespace"

    # Check if 'readlink' is available in the container
    if ! kubectl exec "$pod_name" -n "$namespace" -c "$container" -- sh -c "command -v readlink >/dev/null"; then
      echo "The 'readlink' command is not available in container $container, skipping..."
      continue
    fi

    # Find the actual file path (following symlinks)
    actual_file_path=$(kubectl exec "$pod_name" -n "$namespace" -c "$container" -- readlink -f /lib/x86_64-linux-gnu/liblzma.so.5)

    if [ -n "$actual_file_path" ]; then
      
      # Create a temporary directory for this container's files
      tmp_dir="/tmp/${pod_name}_${container}"
      mkdir -p "$tmp_dir"
      
      #Note: This is not optimal in terms of performance and efficiency but will circumvent the missing hexdump within most containers 
      if kubectl cp "$namespace/$pod_name:$actual_file_path" "$tmp_dir/liblzma.so.5"; then
        echo "File copied successfully to $tmp_dir"
      else
        echo "Failed to copy lib."
        continue # Skip to the next container
      fi

      file_path="$tmp_dir/liblzma.so.5"
      if [ -f "$file_path" ]; then
        # Perform the hexdump check
        if hexdump -ve '1/1 "%.2x"' "$file_path" | grep -q f30f1efa554889f54c89ce5389fb81e7000000804883ec28488954241848894c2410; then       
          echo "Potential vulnerable version of xz in Docker container $container of pod $pod_name, namespace $namespace"
        else 
          echo "Docker container $container of pod $pod_name, namespace $namespace probably not vulnerable"
        fi
      else
        echo "Error: File does not exist at expected path after copy."
      fi

      # Cleanup temporary directory after analysis
      echo "Cleaning up $tmp_dir"
      rm -rf "$tmp_dir"
    else
      echo "Failed to resolve actual file path for /lib/x86_64-linux-gnu/liblzma.so.5 in container $container, or the command is not supported."
    fi
    echo "================================"
  done
done <<<"$pods"
