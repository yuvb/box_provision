# -*- mode: ruby -*-
# vi: set ft=ruby ts=2 sw=2 et sua= inex= :

require "vagrant-reload"

nodes = {
  'nfs' => {
    'box' => 'ubuntu/trusty64',
    'ip1' => '192.168.1.10',
    'ip2' => '172.16.1.10',
    'memory' => 1024,
    'cpus' => 1,
    'role' => 'nfs'
  },
  'grizzly' => {
    'box' => 'ubuntu/precise64',
    'ip1' => '192.168.1.2',
    'ip2' => '172.16.1.2',
    'role' => 'openstack',
    'memory' => 4096,
    'cpus' => 2,
    'hostname' => 'grizzly',
    'release' => 'grizzly'
  },
  'icehouse' => {
    'box' => 'ubuntu/trusty64',
    'ip1' => '192.168.1.3',
    'ip2' => '172.16.1.3',
    'role' => 'openstack',
    'memory' => 4096,
    'cpu' => 2,
    'hostname' => 'icehouse',
    'release' => 'icehouse'
  },
  'juno' => {
    'box' => 'ubuntu/trusty64',
    'ip1' => '192.168.1.8',
    'ip2' => '172.16.1.8',
    'role' => 'openstack',
    'memory' => 4096,
    'cpu' => 2,
    'hostname' => 'juno',
    'release' => 'juno'
  }
}

Vagrant.configure(2) do |config|
  nodes.each do |nodename, nodedata|
    config.vm.define nodename do |thisnode|
      thisnode.vm.box = nodedata['box']
      thisnode.vm.hostname = nodedata.fetch('hostname', nodename)
      thisnode.vm.network 'private_network', ip: nodedata['ip1']
      thisnode.vm.network 'private_network', ip: nodedata['ip2']
      thisnode.ssh.insert_key = false

      case nodedata.fetch('role', '')
      when 'openstack'
        thisnode.vm.provision 'shell', path: './provision/prepare.sh', args: nodedata['release']
        # https://bugs.launchpad.net/ubuntu/+source/openvswitch/+bug/962189 Openvswitch dkms module module won't
        # rebuild on kernel updates.
        thisnode.vm.provision :reload
        thisnode.vm.provision 'shell', path: './provision/keystone.sh', args: nodedata['release']
        thisnode.vm.provision 'shell', path: './provision/glance.sh', args: nodedata['release']
        thisnode.vm.provision 'shell', path: './provision/nova.sh', args: nodedata['release']
        thisnode.vm.provision 'shell', path: './provision/cinder.sh', args: [nodedata['release'], nodes['nfs']['ip1']]
        thisnode.vm.provision 'shell', path: './provision/horizon.sh'
        if nodename == 'grizzly'
          thisnode.vm.provision 'shell', path: './provision/quantum.sh'
        else
          thisnode.vm.provision 'shell', path: './provision/neutron.sh', args: nodedata['release']
        end
        thisnode.vm.provision 'shell', path: './provision/monit.sh', args: nodedata['release']

      when 'nfs'
        thisnode.vm.provision 'shell', path: './provision/nfs.sh'
      end

      thisnode.vm.provider 'virtualbox' do |v|
        v.memory = nodedata.fetch('memory', 1024)
        v.cpus = nodedata.fetch('cpus', 2)
        v.customize ['modifyvm', :id, '--cpuexecutioncap', '90']
      end
    end
  end
end
