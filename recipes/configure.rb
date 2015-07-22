# encoding: UTF-8
# Cookbook Name:: apache_kafka
# Recipe:: configure
#
kafka_brokerid = nil

node["apache_kafka"]["servers"].each do |server|
  if does_server_match_node? server
    kafka_brokerid = id.to_s
  end

  id = id + 1
end

[
  node["apache_kafka"]["config_dir"],
  node["apache_kafka"]["bin_dir"],
  node["apache_kafka"]["data_dir"],
  node["apache_kafka"]["log_dir"],
].each do |dir|
  directory dir do
    recursive true
    owner node["apache_kafka"]["user"]
  end
end

%w{ kafka-server-start.sh kafka-run-class.sh kafka-topics.sh }.each do |bin|
  template ::File.join(node["apache_kafka"]["bin_dir"], bin) do
    source "bin/#{bin}.erb"
    owner "kafka"
    action :create
    mode "0755"
    variables(
      :config_dir => node["apache_kafka"]["config_dir"],
      :bin_dir => node["apache_kafka"]["bin_dir"]
    )
    notifies :restart, "service[kafka]", :delayed
  end
end

broker_id = node["apache_kafka"]["broker.id"]
broker_id = kafka_brokerid if kafka_brokerid
broker_id = 128 if broker_id.nil?

zookeeper_connect = node["apache_kafka"]["zookeeper.connect"]
zookeeper_connect = "localhost:2181" if zookeeper_connect.nil?

template ::File.join(node["apache_kafka"]["config_dir"],
                     node["apache_kafka"]["conf"]["server"]["file"]) do
  source "properties/server.properties.erb"
  owner "kafka"
  action :create
  mode "0644"
  variables(
    :broker_id => broker_id,
    :port => node["apache_kafka"]["port"],
    :zookeeper_connect => zookeeper_connect,
    :entries => node["apache_kafka"]["conf"]["server"]["entries"]
  )
  notifies :restart, "service[kafka]", :delayed
end

template ::File.join(node["apache_kafka"]["config_dir"],
                     node["apache_kafka"]["conf"]["log4j"]["file"]) do
  source "properties/log4j.properties.erb"
  owner "kafka"
  action :create
  mode "0644"
  variables(
    :log_dir => node["apache_kafka"]["log_dir"],
    :entries => node["apache_kafka"]["conf"]["log4j"]["entries"]
  )
  notifies :restart, "service[kafka]", :delayed
end

def does_server_match_node? server
  # We check that the server value is either the nodes fqdn, hostname or ipaddress.
  identities = [node["fqdn"], node["hostname"]]

  node["network"]["interfaces"].each_value do |interface|
    interface["addresses"].each_key do |address|
        identities << address
    end
  end

  # We also include ec2 identities as well
  identities << node["machinename"] if node.attribute?("machinename")
  identities << node["ec2"]["public_hostname"] if node.attribute?("ec2") && node["ec2"].attribute?("public_hostname")
  identities << node["ec2"]["public_ipv4"] if node.attribute?("ec2") && node["ec2"].attribute?("public_ipv4")

  identities.each do |id|
    # We also check if instead the value is of the form [HOST]:[PORT]:[PORT] which is also
    # valid in the case of defining quorum and leader election ports
    if server == id || server.start_with?("#{id}:")
      return true
    end
  end

  # Nothing matched
  false
end
