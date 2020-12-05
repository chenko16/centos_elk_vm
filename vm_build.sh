#!/bin/bash

pwd=$(pwd)
vm_dir="elk_vm"


function install_vm {
	echo "Instaling virtual machine dependencies..."
	sudo apt install -y virtualbox
	sudo apt install -y virtualbox-dkms

	sudo dpkg-reconfigure virtualbox-dkms 
	sudo dpkg-reconfigure virtualbox

	sudo apt install --reinstall linux-headers-$(uname -r) virtualbox-dkms dkms

	sudo apt install -y vagrant
	vagrant plugin install vagrant-scp
	echo "Virtual machine dependencies successfully installed"
}


function deploy_vm {
	echo "Creating virtual machine..."
	rm -rf ~/$vm_dir
	mkdir ~/$vm_dir
	cd ~/$vm_dir
	cp $pwd/config/Vagrantfile ~/$vm_dir #copy vm config
	echo "Virtual machine successfully created"
}


function install_elk {
	echo "Installing ELK..." 
	vagrant ssh -c 'sudo yum install -y elasticsearch'
	vagrant ssh -c 'sudo yum install -y logstash'
	vagrant ssh -c 'sudo systemctl start elasticsearch'
	vagrant ssh -c 'sudo systemctl enable elasticsearch'
	echo "ELK successfully installed"
}


function install_grafana {
	echo "Installing grafana..." 
	vagrant ssh -c 'sudo yum install -y grafana'
	vagrant ssh -c 'sudo systemctl enable grafana-server'
	vagrant ssh -c 'sudo systemctl start grafana-server'
	echo "Grafana successfully installed"
}

function init_vm {
	echo "Configuring virtual machine..." 
	vagrant up
	vagrant ssh -c 'sudo yum update -y'
	vagrant scp $pwd/config/repo . default
	vagrant ssh -c 'sudo mv repo/*.repo /etc/yum.repos.d/'

	vagrant ssh -c 'sudo yum install -y java-11-openjdk-devel'
	install_elk
	install_grafana

	echo "Virtual machine successfully configured"
}


if [[ $# -ne 1 ]]; then
    echo "$0: A single input file is required."
    exit 4
else
	if [[ $1 = "deploy" ]]; then 
		install_vm
		deploy_vm
		init_vm 
		echo "Virtual machine successfully deployed"
		echo "Grafana page: http://localhost:3000"
	elif [[ $1 = "destroy" ]]; then 
		cd ~/$vm_dir
		vagrant destroy -y
	elif [[ $1 = "destroy" ]]; then 
		cd ~/$vm_dir
		vagrant reload
	elif [[ $1 = "help" ]]; then 
		echo "Uage $0 [option]
			deploy - deploy, start and configure virtual machine
			destroy - stop and delete virtual machine
			reload - reload virtual machine
			help - get help info
		"
	else
		echo "$0: Wrong option. Use option help to get more info"
	fi
fi