#
# Cookbook Name:: corosync
# Recipe:: authkey
#
# Copyright 2012, Rackspace US, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'base64'

# Find the authkey:
authkey_file = node[:corosync][:authkey_file]
if File.exists? authkey_file
  log "#{authkey_file} already exists"
  return
end

if Chef::Config[:solo]
  Chef::Application.fatal! "This recipe uses search. Chef Solo does not support search."
  return
end

cluster_name = node['corosync']['cluster_name']
unless cluster_name and ! cluster_name.empty?
  Chef::Application.fatal! "Couldn't figure out corosync cluster name"
  return
end

authkey_nodes = search(:node,
                       "chef_environment:#{node.chef_environment} AND " +
                        "corosync:authkey AND corosync_cluster_name:#{cluster_name}")
log("nodes with authkey: #{authkey_nodes}")
if authkey_nodes.length == 0
  # Generate the auth key and then save it

  # Ensure that the RNG has access to a decent entropy pool,
  # so that corosync-keygen doesn't take too long.
  package "haveged" do
    action :install
  end

  service "haveged" do
    action [:enable, :start]
  end

  # create the auth key
  execute "corosync-keygen" do
    creates authkey_file
    user "root"
    group "root"
    umask "0400"
    action :run
  end

  # Read authkey (it's binary) into encoded format and save to chef server
  ruby_block "Store authkey" do
    block do
      file = File.new(authkey_file, 'r')
      contents = ""
      file.each do |f|
        contents << f
      end
      packed = Base64.encode64(contents)
      node.set_unless['corosync']['authkey'] = packed
      node.save
    end
    action :nothing
    subscribes :create, resources(:execute => "corosync-keygen"), :immediately
  end
elsif authkey_nodes.length > 0
  authkey_node = authkey_nodes[0]
  authkey = authkey_node['corosync']['authkey']
  log("Using corosync authkey from node: #{authkey_node.name}")

  # decode so we can write out to file below
  corosync_authkey = Base64.decode64(authkey)

  file authkey_file do
    not_if {File.exists? authkey_file}
    content corosync_authkey
    owner "root"
    mode "0400"
    action :create
  end

  # set it to our own node hash so we can also be searched in future
  node.set['corosync']['authkey'] = authkey
end
