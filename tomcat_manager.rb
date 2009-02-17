=begin
Copyright 2008 Matt Mitchell

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at 

  http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License. 
=end

#
# Tomcat Manager Utility: Provides a wrapper around the common tomcat manager commands
# - supports multiple servers
# Example:
#

=begin
servers=%W(http://user:pass@server1.com:8080/manager http://user:pass@server2.com:8080/manager)
tm = TomcatManager::Base.new do
  servers.each {|s|add_server(s)}
end

tm.connect do |c|
  puts "#{c.server.url.host} : #{c.list.inspect}"
  c.list.each do |app|
    puts app.context
  end
  puts c.manager_info('my-solr')
  puts c.deployed?('my-solr')
  puts c.running?('my-solr')
  puts c.sessions('my-solr')
end
=end

require 'rubygems'
require 'uri'
require 'net/http'
require 'open-uri'
require 'ostruct'

module TomcatManager
  
  class Connection
    
    attr_accessor :server
    
    def initialize(server)
      self.server=server
    end
    
    def connect(&block)
      yield Net::HTTP.start(server.url.host, server.url.port)
    end
    
    def get(path='')
      # strip repetitive slashes...
      path.gsub!(/\/+/, '/')
      return connect do |http|
        req = Net::HTTP::Get.new(path)
        req.basic_auth(server.user, server.pass) if server.user and server.pass
        http.request(req)
      end
    end
    
    def ok?
      return get('/').code == '200'
    end
    
    def list
      apps=[]
      response = get("#{server.manager_path}/list").body
      response.split("\n").each do |line|
        app, state, sessions = line.split(/:/)
        # skip the first line
        next if app =~ /Listed applications for virtual host /
        apps << OpenStruct.new({:context=>app, :state=>state, :sessions=>sessions})
      end
      apps
    end
    
    def manager_info(context)
      list.detect do |app|
        "/#{context}" == app.context
      end
    end
    
    def deployed?(context)
      ! manager_info(context).nil?
    end
    
    def running?(context)
      app = manager_info(context)
      return false if app.nil?
      return app.state == 'running'
    end
    
    def status(context)
      running?(context)
    end
    
    def sessions(context)
      app = manager_info(context)
      return false if app.nil?
      return app.sessions
    end
    
    def undeploy!(context)
      if deployed?(context)
        get("#{server.manager_path}/undeploy?deployPath=/#{context}")
      end
    end
    
    def deploy!(context, config_file)
      if ! deployed?(context)
        get("#{server.manager_path}/deploy?deployPath=/#{context}&deployConfig=#{config_file}")
      end
    end
    
    def stop(context)
      if deployed?(context) && running?(context)
        get("#{server.manager_path}/stop?deployPath=/#{context}")
      end
    end
    
    def start(context)
      if deployed?(context) && ! running?(context)
        get("#{server.manager_path}/start?deployPath=/#{context}")
      end
    end
    
    def reload(context)
      if deployed?(context) && running?(context)
        get("#{server.manager_path}/reload?deployPath=/#{context}")
      end
    end
    
  end
  
  class Base
    
    attr_accessor :servers
    
    def initialize(&block)
      self.servers=[]
      instance_eval &block if block_given?
    end
    
    def add_server(url, manager_path='/manager')
      u = URI.parse(url)
      user, pass = u.userinfo.split(/:/) if u.userinfo
      server = OpenStruct.new({:url=>u, :user=>user, :pass=>pass, :manager_path=>manager_path})
      self.servers << server
    end
    
    # yields http connection
    def connect(&block)
      servers.each do |server|
        yield TomcatManager::Connection.new(server)
      end
    end
    
    def exec(method, *args)
      output={}
      connect do |c|
        output[c] = c.send(method.to_sym, *args)
      end
      output
    end
    
  end
  
end