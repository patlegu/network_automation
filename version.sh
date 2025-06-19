# CHKSUM: 1460e72a153104503bc0dfee916e8529e8d8b337fcbd6615b4a42e245e0a1265
# Example version script.
# Please choose one version or create your own

# Node.js: grep the version from a package.json file with jq
# jq -rM '.version' package.json

# Elixir: grep the version from a mix file
# cat mix.exs | grep version | grep '\([0-9]\+\.\?\)\{3\}' -o

# We get version from the Dockerfile
 cat Dockerfile | grep -e Version  | grep '\([0-9]\+\.\?\)\{2,\}' -o
