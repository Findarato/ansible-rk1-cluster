[private]
default:
    just --list

update:
    just update_all

update_all:
    distrobox-enter -H ansible -- ansible-playbook infrastructure.yml -i hosts/production.yml

deploy tag:
    distrobox-enter -H ansible -- ansible-playbook deploy.yml -i hosts/production.yml

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


