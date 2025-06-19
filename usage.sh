# CHKSUM: 68ff7b4dd3aaa5b2ffd9e41c918d4eb24be0a684341fc422c5f8587a1dc23967
# INSTALL
# - copy the files deploy.env, config.env, version.sh and Makefile to your repo
# - replace the vars in deploy.env
# - define the version script

# Build the container
make build

# Build and publish the container
make release

# Publish a container to AWS-ECR.
# This includes the login to the repo
make publish

# Run the container
make run

# Build an run the container
make up

# Stop the running container
make stop

# Build the container with differnt config and deploy file
make cnf=another_config.env dpl=another_deploy.env build