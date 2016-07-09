# -*- mode: ruby -*-
# vi: set ft=ruby :

# Vagrantfile API/syntax version. Don't touch unless you know what you're doing!
VAGRANTFILE_API_VERSION = "2"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  # All Vagrant configuration is done here. The most common configuration
  # options are documented and commented below. For a complete reference,
  # please see the online documentation at vagrantup.com.

#  config.vm.box = "ubuntu/trusty64"
  config.vm.box = "ubuntu/precise64"

config.vm.provider "virtualbox" do |v|
  v.memory = 3072
#  v.cpu = 4
end

  
  config.vm.define "grizzly" do |v|
    v.vm.hostname = "grizzly"
#	config.vm.network "private_network", ip: "10.20.0.104"
	config.vm.network "private_network", ip: "192.168.1.2"
#	config.vm.network "private_network", ip: "172.16.1.2"
#   virtualbox__intnet: true
#This line add to test "default: stdin: is not a tty"
    config.vm.provision "shell", inline: "pushd /vagrant/provision; bash -x prepare.sh grizzly; popd"
	config.vm.provision "shell", inline: "pushd /vagrant/provision; bash -x keystone.sh grizzly; popd"
	config.vm.provision "shell", inline: "pushd /vagrant/provision; bash -x glance.sh grizzly; popd"
	config.vm.provision "shell", inline: "pushd /vagrant/provision; bash -x nova.sh grizzly; popd"
	config.vm.provision "shell", inline: "pushd /vagrant/provision; bash -x neutron.sh grizzly; popd"
	config.vm.provision "shell", inline: "pushd /vagrant/provision; bash -x neutron.sh grizzly; popd"
	config.vm.provision "shell", inline: "pushd /vagrant/provision; bash -x cinder.sh grizzly; popd"
	config.vm.provision "shell", inline: "pushd /vagrant/provision; bash -x horizon.sh grizzly; popd"
	config.vm.provision "shell", inline: "pushd /vagrant/provision; bash -x monit.sh grizzly; popd"
#  	config.vm.provision "shell",  path: "./provision/prepare.sh", args: "grizzly"
#	config.vm.provision "shell", inline: "wget https://apt.puppetlabs.com/puppetlabs-release-precise.deb && dpkg -i puppetlabs-release-precise.deb && apt-get update"
#	config.vm.provision "shell", inline: "puppet apply -e 'package { [git, mc]: ensure => installed }'"
#    config.vm.provision "shell", inline: "puppet apply  manifests/hosts.pp"
#	config.vm.provision :puppet do |puppet|
#      puppet.manifests_path = "manifests"
#	  puppet.manifest_file = "default.pp"
#	end
  end
end
