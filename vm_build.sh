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
	cp $pwd/config/Vagrantfile ~/$vm_dir #копируем конфиг для виртуальной машины
	echo "Virtual machine successfully created"
}

function create_elastic_index {
	vagrant ssh -c "curl -X PUT -H 'Content-Type: application/json' -d '{
		  \"settings\": {
		    \"number_of_shards\": 1
		  },
		  \"mappings\": {
		    \"properties\": {
		      \"name\": { \"type\": \"text\" },
		      \"value\": { \"type\": \"long\" },
		      \"@timestamp\": { \"type\": \"date\" }
		    }
		  }
		}' 'http://localhost:9200/count'"
}

function install_elk {
	echo "Installing ELK..." 
	vagrant ssh -c 'sudo yum install --enablerepo=elasticsearch -y elasticsearch'
	vagrant ssh -c 'sudo yum install --enablerepo=elasticsearch -y logstash'
	vagrant ssh -c 'sudo mv elasticsearch/* /etc/elasticsearch/'
	vagrant ssh -c 'sudo mv logstash/*.conf /etc/logstash/conf.d/'
	vagrant ssh -c 'sudo systemctl start elasticsearch'
	vagrant ssh -c 'sudo systemctl enable elasticsearch'
	vagrant ssh -c 'sudo systemctl start logstash'
	vagrant ssh -c 'sudo systemctl enable logstash'
	sleep 120 # ждем пока сервисы стартанут
	create_elastic_index
	echo "ELK successfully installed"
}


function install_grafana {
	echo "Installing grafana..." 
	vagrant ssh -c 'sudo yum install -y grafana'
	vagrant ssh -c 'sudo mv grafana/datasources/*.yml /etc/grafana/provisioning/datasources/'
	vagrant ssh -c 'sudo mv grafana/dashboards/*.yml /etc/grafana/provisioning/dashboards/'
	vagrant ssh -c 'sudo mkdir /var/lib/grafana/dashboards/'
	vagrant ssh -c 'sudo mv grafana/dashboards/*.json /var/lib/grafana/dashboards/'
	vagrant ssh -c 'sudo systemctl enable grafana-server'
	vagrant ssh -c 'sudo systemctl start grafana-server'
	echo "Grafana successfully installed"
}


function install_maven {
	#Устанавливаю maven вручную, т.к. yum тянет довольно старую версию
	vagrant ssh -c 'sudo wget https://repos.fedorapeople.org/repos/dchen/apache-maven/epel-apache-maven.repo -O /etc/yum.repos.d/epel-apache-maven.repo'
	vagrant ssh -c 'sudo sed -i s/\$releasever/6/g /etc/yum.repos.d/epel-apache-maven.repo'
	vagrant ssh -c 'sudo yum install -y apache-maven'
}

function install_utils {
	vagrant ssh -c 'sudo yum install -y wget'
	vagrant ssh -c 'sudo yum install -y vim'
	vagrant ssh -c 'sudo yum install -y git'
}

function run_application {
	install_maven
	vagrant ssh -c 'git clone https://github.com/chenko16/twitter_streaming_elk.git'
	vagrant ssh -c 'sudo alternatives --set java /usr/lib/jvm/java-11-openjdk-11.0.9.11-0.el7_9.x86_64/bin/java'
	vagrant ssh -c 'mvn clean package -f ./twitter_streaming_elk/pom.xml'
	vagrant ssh -c 'nohup java -jar twitter_streaming_elk/target/twitter_streaming_elk-0.1.0.jar > twitter_streaming_elk.log & sleep 1' # Если не будет sleep, то не запуститься, т.к. ssh сессия сразу закроется
}


function init_vm {
	echo "Configuring virtual machine..." 
	vagrant up
	vagrant ssh -c 'sudo yum update -y'
	vagrant scp $pwd/config/repo . default
	vagrant scp $pwd/config/logstash . default
	vagrant scp $pwd/config/elasticsearch . default
	vagrant scp $pwd/config/grafana . default
	vagrant ssh -c 'sudo mv repo/*.repo /etc/yum.repos.d/'

	vagrant ssh -c 'sudo yum install -y java-11-openjdk-devel'
	install_utils
	install_elk
	install_grafana
	run_application

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
		vagrant destroy
		rm -rf ~/$vm_dir
	elif [[ $1 = "reload" ]]; then 
		cd ~/$vm_dir
		vagrant reload
		sleep 120 # ждем пока сервисы стартанут
		run_application
	elif [[ $1 = "stop" ]]; then 
		cd ~/$vm_dir
		vagrant halt
	elif [[ $1 = "start" ]]; then 
		cd ~/$vm_dir
		vagrant up
		sleep 120 # ждем пока сервисы стартанут
		run_application
	elif [[ $1 = "suspend" ]]; then 
		cd ~/$vm_dir
		vagrant suspend
	elif [[ $1 = "resume" ]]; then 
		cd ~/$vm_dir
		vagrant resume
	elif [[ $1 = "help" ]]; then 
		echo "Uage $0 [option]
			deploy - deploy, run and configure virtual machine
			destroy - stop and delete virtual machine
			reload - reload virtual machine
			stop - shut down virtual machine
			start - run virtual machine
			suspend - shut down virtual machine with saving RAM content
			resume - run suspended virtual machine
			help - get help info
		"
	else
		echo "$0: Wrong option. Use option help to get more info"
	fi
fi