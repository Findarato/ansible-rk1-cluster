[private]
default:
    just --list

# Start the development environment
start:
    distrobox-enter ansible.

# Update all the deployments
update:
    just update_all

# Update all the deployments
setup:
    just update_all

# Run ansible lint
lint_all:
    ansible-lint .

# Run ansible lint on a specific file
lint file:
    ansible-lint {{file}}

edit_vault:
    distrobox-enter -H ansible -- ansible-vault edit vars/main.vault.yml
    # $CONTAINER_ID

update_all:
    distrobox-enter -H ansible -- ansible-playbook infrastructure.yml -i hosts/production.yml

deploy tag:
    distrobox-enter -H ansible -- ansible-playbook deploy.yml -i hosts/production.yml --tags {{tag}}

deploy_all:
    distrobox-enter -H ansible -- ansible-playbook deploy.yml -i hosts/production.yml

start_mining:
    distrobox-enter -H ansible -- ansible-playbook mining.yml -i hosts/production.yml --tags start_mining

stop_mining:
    distrobox-enter -H ansible -- ansible-playbook mining.yml -i hosts/production.yml --tags stop_mining

start_polluting:
    distrobox-enter -H ansible -- ansible-playbook polluting.yml -i hosts/production.yml --tags start_polluting

stop_polluting:
    distrobox-enter -H ansible -- ansible-playbook polluting.yml -i hosts/production.yml --tags stop_polluting


