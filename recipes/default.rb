#
# Cookbook Name:: mackerel-agent
# Recipe:: default
#
# Copyright 2014, Hatena Co., Ltd.
#
# Apache License, Version 2.0
#

whyrun_config = Chef::Config[:why_run]
begin
  Chef::Config[:why_run] = false
  chef_gem "toml" do
    action :install
    compile_time true if respond_to?(:compile_time)
  end
ensure
  Chef::Config[:why_run] = whyrun_config
end

require "toml"

gpgkey_url = 'https://mackerel.io/assets/files/GPG-KEY-mackerel'
package_options = ""

if platform?('centos') or platform?('redhat') or platform?('amazon')
  include_recipe 'yum'
  yum_cookbook_ver = Gem::Version.new(run_context.cookbook_collection['yum'].version)
  if yum_cookbook_ver < Gem::Version.new('3.0.0')
    yum_key "RPM-GPG-KEY-mackerel" do
      url gpgkey_url
      action :add
    end
  end
  repo_url = "http://yum.mackerel.io/centos/$basearch"
  repo_url = "http://yum.mackerel.io/amznlinux/$releasever/$basearch" if platform?('amazon')
  yum_repository "mackerel" do
    gpgkey gpgkey_url if yum_cookbook_ver >= Gem::Version.new('3.0.0')
    description "mackerel-agent monitoring"
    url repo_url
    action :add
  end
elsif platform?('debian') or platform?('ubuntu')
  package_options = '--force-yes -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"'

  include_recipe 'apt'
  apt_repository "mackerel" do
    uri 'http://apt.mackerel.io/debian/'
    key gpgkey_url
    distribution 'mackerel'
    components ['contrib']
    action :add
  end
end

package 'mackerel-agent' do
  action node['mackerel-agent']['package-action'].to_sym
  options package_options
  if node['mackerel-agent']['start_on_setup']
    notifies :restart, 'service[mackerel-agent]'
  end
end

file "/etc/mackerel-agent/mackerel-agent.conf" do
  owner "root"
  group "root"
  mode 0644
  content lazy { TOML::Generator.new(node['mackerel-agent']['conf']).body }
  if node['mackerel-agent']['start_on_setup']
    notifies :restart, 'service[mackerel-agent]'
  end
end

env_file_path = ''
if platform?('centos') or platform?('redhat') or platform?('amazon')
  env_file_path = '/etc/sysconfig/mackerel-agent'
elsif platform?('debian') or platform?('ubuntu')
  env_file_path = '/etc/default/mackerel-agent'
end

template env_file_path do
  source 'env_file.erb'
  owner 'root'
  group 'root'
  mode 0644
  backup false
  variables({
    other_opts: node['mackerel-agent']['env_opts']['other_opts'],
    auto_retirement: node['mackerel-agent']['env_opts']['auto_retirement'],
    http_proxy: node['mackerel-agent']['env_opts']['http_proxy'],
    mackerel_agent_plugin_meta: node['mackerel-agent']['env_opts']['mackerel_agent_plugin_meta'],
  })
  if node['mackerel-agent']['start_on_setup']
    notifies :restart, 'service[mackerel-agent]'
  end
  action :create
end

service 'mackerel-agent' do
  supports :status => true, :restart => true
  if node['mackerel-agent']['start_on_setup']
    action [:enable, :start]
  else
    action :enable
  end
end
