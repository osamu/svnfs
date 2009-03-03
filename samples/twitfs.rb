#! /usr/bin/env ruby
#
# twfs.rb $Id: twfs.rb 24 2007-05-06 14:50:23Z kita $
#
# Usage: twfs.rb config directory
#
# How To:
#  * cp config.sample config
#  * vi config
#    (modify 'username_here' and 'password_here')
#  ---
   :username: username_hear
   :password: password_here
   :update_interval: 60

#  * mkdir ~/twfs
#  * twfs.rb config ~/twfs
#
# Copyright (C) 2007, Junichiro Kita <junichiro.kita@gmail.com>
# You can redistribute it and/or modify it under GPL2.
#
require 'fusefs'
require 'open-uri-post' # http://d.hatena.ne.jp/urekat/20070201/1170349097
require 'uri'
require 'json'
require 'yaml'
require 'kconv'

$KCODE = 'u'

class TwitterUsers < FuseFS::MetaDir
   def initialize(type, config)
      @type = type
      @config = config
      @updated_at = Time.at(0)
      load_users
   end

   def contents(path)
      node = find_node(path)
      node.keys.sort
   end

   def directory?(path)
      node = find_node(path)
      node.is_a?(Hash)
   end

   def file?(path)
      node = find_node(path)
      !node.is_a?(Hash)
   end

   def read_file(path)
      node = find_node(path)
      node.to_s
   end

   private
   def find_node(path)
      load_users if @updated_at + @config[:update_interval] < Time.now
      items = scan_path(path)
      node = items.inject(@users) do |node, item|
         item ? node[item] : node
      end
      node
   end

   def load_users
      @users = {}
      begin
         users_json = open("http://twitter.com/statuses/#{@type}.json",
                         :http_basic_authentication => [@config[:username], @config[:password]])
         JSON.parse(users_json.read).each do |f|
            @users[f['screen_name']] = f
         end
         @updated_at = Time.now
      rescue
         STDERR.puts $!
      end
      STDERR.puts "#{@type} is (re)loaded."
   end
end

class TwitterTimelines
   def initialize(type, config)
      @type = type
      @config = config
   end

   def contents(path)
      ['xml', 'json', 'rss', 'atom']
   end

   def file?(path)
      contents('/').include?(path)
   end

   def read_file(path)
      begin
         open("http://twitter.com/statuses/#{@type}.#{File.basename(path)}",
            :http_basic_authentication => [@config[:username], @config[:password]]).read
      rescue
         $!
      end
   end
end

class TwitterUpdate
   STATUS = 'status'
   def initialize(config)
      @config = config
      @response = ''
   end

   def contents(path)
      [STATUS]
   end

   def file?(path)
      path == STATUS
   end

   def can_write?(path)
      path == STATUS
   end

   def can_delete?(path)
      path == STATUS
   end

   def write_to(path, str)
      return if path != STATUS
      str.strip!
      return if str.size == 0
      msg = URI::encode(NKF::nkf('-w -f160', str).split[0])
      begin
         open("http://twitter.com/statuses/update.xml",
            :http_basic_authentication => [@config[:username], @config[:password]],
            'postdata' => "status=#{msg}") do |f|
            @response = f.read
         end
      rescue
         @response = $!
      end
   end

   def read_file(path)
      return '' if path != STATUS
      @response
   end
end

if (File.basename($0) == File.basename(__FILE__))
   if (ARGV.size != 2)
     puts "Usage: #{$0} <config> <directory>"
     exit
   end

   config_file, dirname = ARGV

   unless File.exist?(config_file)
      puts "Usage: #{config_file} does'nt exist."
      exit
   end
   unless File.directory?(dirname)
      puts "Usage: #{dirname} is not a directory."
      exit
   end

   config = YAML.load(open(config_file))
   root = FuseFS::MetaDir.new

   ["friends", "followers"].each do |type|
      root.mkdir("/#{type}", TwitterUsers.new(type, config))
   end

   timeline = FuseFS::MetaDir.new
   ["public_timeline", "friends_timeline", "user_timeline"].each do |type|
      tt = TwitterTimelines.new(type, config)
      timeline.mkdir("/#{type}", tt)
   end
   root.mkdir('/timelines', timeline)

   root.mkdir('/update', TwitterUpdate.new(config))

   FuseFS.set_root(root)
   FuseFS.mount_under(dirname)
   FuseFS.run
end

